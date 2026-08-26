class Trace < ApplicationRecord
  PROBE_INTERVAL = 300  # seconds between synthetic probe runs (5 min)

  # step  = width of one bucket, in seconds
  # count = how many buckets to render (the bars on the chart)
  RANGES = {
    '1h'  => {step: 300,   count: 12},  # 12 × 5 min
    '12h' => {step: 3600,  count: 12},  # 12 × 1 hr
    '24h' => {step: 3600,  count: 24},  # 24 × 1 hr
    '7d'  => {step: 21600, count: 28},  # 28 × 6 hr
    '14d' => {step: 43200, count: 28},  # 28 × 12 hr
    '30d' => {step: 86400, count: 30}   # 30 × 1 day
  }

  def self.summary
    sql = <<~SQL
      SELECT
        CASE
          WHEN endpoint LIKE 'GET /stocks/%/marketdata' THEN 'GET /stocks/:symbol/marketdata'
          WHEN endpoint LIKE 'GET /stocks/%/companydata' THEN 'GET /stocks/:symbol/companydata'
          WHEN endpoint LIKE 'GET /stocks/%/chartdata' THEN 'GET /stocks/:symbol/chartdata'
          WHEN endpoint LIKE 'GET /positions/%' THEN 'GET /positions/:symbol'
          WHEN endpoint LIKE 'GET /search%' THEN 'GET /search'
          WHEN endpoint LIKE 'GET /stocks/%/tickerdata' THEN 'GET /stocks/:symbol/tickerdata'
          WHEN endpoint LIKE 'GET /stocks/%/userdata' THEN 'GET /stocks/:symbol/userdata'
          WHEN endpoint LIKE 'GET /stocks/%/stockprice' THEN 'GET /stocks/:symbol/stockprice'
          WHEN endpoint LIKE 'POST /stocks/%/buy' THEN 'POST /stocks/:symbol/buy'
          WHEN endpoint LIKE 'POST /stocks/%/sell' THEN 'POST /stocks/:symbol/sell'
          ELSE endpoint
        END as route,
        COUNT(*) as total_requests,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration) as p99,
        ROUND(
          COUNT(*) FILTER (WHERE breakdown::text LIKE '%"used_redis":true%') * 100.0
          / NULLIF(COUNT(*) FILTER (WHERE breakdown IS NOT NULL AND breakdown::text != '{}'), 0),
          1
        ) as cache_hit_rate
      FROM traces
      WHERE NOT synthetic
      GROUP BY route
      ORDER BY total_requests DESC
    SQL

    results = connection.execute(sql)
    results.map do |row|
      {
        route: row['route'],
        clean_route: row['route'].downcase.gsub(' ', '').gsub(':', ''),
        total_requests: row['total_requests'].to_i,
        p99: row['p99']&.to_f || 0.0,
        cache_hit_rate: row['route'].start_with?('POST') ? nil : row['cache_hit_rate']&.to_f
      }
    end
  end

  def self.list(endpoint:)
    route = normalize_endpoint(endpoint)

    if endpoint == 'GET /stocks/symbol'
      where("endpoint ILIKE ? AND endpoint NOT LIKE ?", route, 'GET /stocks/%/%')
      .where(synthetic: false)
      .order(created_at: :desc)
    else
    where("endpoint ILIKE ?", route)
    .where(synthetic: false)
    .order(created_at: :desc)
    end
  end

  def self.breakdown(endpoint:)
    route = normalize_endpoint(endpoint)

    query = where("endpoint LIKE ?", route).where.not("breakdown::text = ? OR breakdown IS NULL", '{}').where(synthetic: false)

    {
      redis_query: query.where("breakdown::text LIKE ?", '%"used_redis":true%').order(created_at: :desc),
      db_api_query: query.where("breakdown::text LIKE ? OR breakdown::text LIKE ?", '%"used_api":true%', '%"used_db":true%').order(created_at: :desc),
    }
  end

  def self.stats(endpoint:)
    route = normalize_endpoint(endpoint)

    base_sql = <<~SQL
      SELECT
        COUNT(*) as total_requests,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY duration) as p50,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration) as p95,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration) as p99,
        COUNT(*) FILTER (WHERE status >= 500) as error_count
      FROM traces
    SQL

    sanitized = if endpoint == 'GET /stocks/symbol'
      sanitize_sql_array(
        ["#{base_sql} WHERE NOT synthetic AND endpoint ILIKE ? AND endpoint NOT LIKE ?", route, 'GET /stocks/%/%']
      )
    else
      sanitize_sql_array(
        ["#{base_sql} WHERE NOT synthetic AND endpoint ILIKE ?", route]
      )
    end

    result = connection.execute(sanitized).first

    {total_requests: result['total_requests'].to_i,
      p50: result['p50']&.to_f || 0.0,
      p95: result['p95']&.to_f || 0.0,
      p99: result['p99']&.to_f || 0.0,
      error_rate: result['total_requests'].to_i > 0 ? (result['error_count'].to_f / result['total_requests'].to_f * 100).round(2) : 0.0
    }
  end

  def self.latent
    where.not(endpoint: ['POST /graphql', 'POST /record']).where(synthetic: false).order(duration: :desc).limit(1000)
  end

  def self.synthetic_buckets(range: '1h')
    config = RANGES.fetch(range, RANGES['1h'])
    step   = config[:step]
    sql = <<~SQL
      SELECT
        floor(extract(epoch FROM created_at) / ?) * ? AS bucket,
        COUNT(*) FILTER (WHERE endpoint = 'POST /signup')           AS started,
        COUNT(*) FILTER (WHERE endpoint = 'GET /portfoliodata' AND status = 401) AS completed,
        COUNT(*) FILTER (WHERE status >= 500)                       AS failures
      FROM traces
      WHERE synthetic
        AND created_at > ?
      GROUP BY bucket
      ORDER BY bucket
    SQL
    cutoff = Time.now.utc - (step * (config[:count] + 1))
    rows = connection.execute(
      sanitize_sql_array([sql, step, step, cutoff])
    )
    by_bucket = rows.index_by { |r| r['bucket'].to_i }
    current = Time.at((Time.now.to_i / step) * step).utc
    config[:count].downto(1).map do |a|
      bucket = current - (a * step)
      row    = by_bucket[bucket.to_i]
      {
        bucket: bucket,
        started:   row ? row['started'].to_i   : 0,
        completed: row ? row['completed'].to_i : 0,
        failures:  row ? row['failures'].to_i  : 0,
        expected:  step / PROBE_INTERVAL
      }
    end
  end

  def self.synthetic_runs(bucket:, range: '1h')
    step = RANGES.fetch(range, RANGES['1h'])[:step]
    where(synthetic: true)
      .where.not(user_id: nil)
      .where(created_at: bucket...(bucket + step.seconds))
      .group(:user_id)
      .order(Arel.sql('MIN(created_at) ASC'))
      .pluck(
        :user_id,
        Arel.sql('MIN(created_at)'),
        Arel.sql('COUNT(*)'),
        Arel.sql('COUNT(*) FILTER (WHERE status >= 500)'),
        Arel.sql("bool_or(endpoint = 'DELETE /delete_account')")
      )
      .map { |id, started, count, failures, completed|
        {user_id: id, started_at: started, request_count: count,
         failures: failures, completed: completed}
      }
  end

  # a run is identified by its ephemeral user, so its requests are just that user's traces
  def self.run_traces(user_id:)
    where(synthetic: true, user_id: user_id).order(created_at: :asc)
  end

  def self.normalize_endpoint(endpoint)
    case endpoint
    when 'GET /stocks/symbol/marketdata'
      'GET /stocks/%/marketdata'
    when 'GET /stocks/symbol/companydata'
      'GET /stocks/%/companydata'
    when 'GET /stocks/symbol/chartdata'
      'GET /stocks/%/chartdata'
    when 'GET /stocks/symbol'
      'GET /stocks/%'
    when 'GET /search'
      'GET /search%'
    when 'GET /stocks/symbol/tickerdata'
      'GET /stocks/%/tickerdata'
    when 'GET /stocks/symbol/userdata'
      'GET /stocks/%/userdata'
    when 'GET /stocks/symbol/stockprice'
      'GET /stocks/%/stockprice'
    when 'POST /stocks/symbol/buy'
      'POST /stocks/%/buy'
    when 'POST /stocks/symbol/sell'
      'POST /stocks/%/sell'
    else
      endpoint
    end
  end
  private_class_method :normalize_endpoint
end
