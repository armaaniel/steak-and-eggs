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

  ROUTE_PATTERNS = {
    'GET /stocks/symbol/marketdata'  => 'GET /stocks/%/marketdata',
    'GET /stocks/symbol/companydata' => 'GET /stocks/%/companydata',
    'GET /stocks/symbol/chartdata'   => 'GET /stocks/%/chartdata%',
    'GET /stocks/symbol/tickerdata'  => 'GET /stocks/%/tickerdata',
    'GET /stocks/symbol/userdata'    => 'GET /stocks/%/userdata',
    'GET /stocks/symbol/stockprice'  => 'GET /stocks/%/stockprice',
    'POST /stocks/symbol/buy'        => 'POST /stocks/%/buy',
    'POST /stocks/symbol/sell'       => 'POST /stocks/%/sell',
    'GET /search'                    => 'GET /search%'
  }.freeze

  def self.normalize_endpoint(endpoint)
    endpoint = endpoint.to_s
    ROUTE_PATTERNS[endpoint] || sanitize_sql_like(endpoint)
  end

  def self.route_case
    whens = ROUTE_PATTERNS.map do |label, pattern|
      sanitize_sql_array(['WHEN endpoint LIKE ? THEN ?', pattern, label])
    end
    "CASE #{whens.join("\n")} ELSE endpoint END"
  end

  def self.summary
    sql = <<~SQL
      SELECT #{route_case} as route,
        COUNT(*) as total_requests,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration) as p99,
        ROUND(
          COUNT(*) FILTER (WHERE breakdown::text LIKE '%"used_redis":true%') * 100.0
          / NULLIF(COUNT(*) FILTER (WHERE breakdown IS NOT NULL AND breakdown::text != '{}'), 0),
          1
        ) as cache_hit_rate
      FROM traces
      WHERE source = 'user'
      GROUP BY route
      ORDER BY total_requests DESC
    SQL

    results = connection.execute(sql)
    results.map do |row|
      {
        route: row['route'],
        clean_route: row['route'].downcase.delete(' '),
        total_requests: row['total_requests'].to_i,
        p99: row['p99']&.to_f || 0.0,
        cache_hit_rate: row['route'].start_with?('POST') ? nil : row['cache_hit_rate']&.to_f
      }
    end
  end

  def self.list(endpoint:)
    route = normalize_endpoint(endpoint)

    where("endpoint ILIKE ?", route)
      .where(source: 'user')
      .order(created_at: :desc)
  end

  def self.breakdown(endpoint:)
    route = normalize_endpoint(endpoint)

    query = where("endpoint ILIKE ?", route).where.not("breakdown::text = ? OR breakdown IS NULL", '{}').where(source: 'user')

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
        COUNT(*) FILTER (WHERE status >= 500) as error_count,
        bool_or(breakdown::text LIKE '%"used_redis"%') as uses_redis,
        bool_or(breakdown::text LIKE '%"used_api"%') as uses_api
      FROM traces
    SQL

    sanitized = sanitize_sql_array(
      ["#{base_sql} WHERE source = 'user' AND endpoint ILIKE ?", route]
    )

    result = connection.execute(sanitized).first

    {total_requests: result['total_requests'].to_i,
      p50: result['p50']&.to_f || 0.0,
      p95: result['p95']&.to_f || 0.0,
      p99: result['p99']&.to_f || 0.0,
      error_rate: result['total_requests'].to_i > 0 ? (result['error_count'].to_f / result['total_requests'].to_f * 100).round(2) : 0.0,
      uses_redis: ActiveRecord::Type::Boolean.new.cast(result['uses_redis']) || false,
      uses_api: ActiveRecord::Type::Boolean.new.cast(result['uses_api']) || false
    }
  end

  def self.latent
    where.not(endpoint: ['POST /graphql', 'POST /record']).where(source: 'user').order(duration: :desc).limit(1000)
  end

  def self.synthetic_buckets(range: '1h')
    config = RANGES.fetch(range, RANGES['1h'])
    step   = config[:step]
    sql = <<~SQL
      SELECT
        floor(extract(epoch FROM created_at) / ?) * ? AS bucket,
        count(DISTINCT run_id)                                                 AS started,
        count(DISTINCT run_id) FILTER (WHERE result = 'pass')                  AS completed,
        count(DISTINCT run_id) FILTER (WHERE result = 'fail' OR status >= 500) AS failures
      FROM traces
      WHERE source = 'canary'
        AND created_at > ?
      GROUP BY bucket
      ORDER BY bucket
    SQL
    cutoff = Time.now.utc - (step * (config[:count] + 1))
    rows = connection.execute(sanitize_sql_array([sql, step, step, cutoff]))
    
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

  def self.synthetic_runs(bucket:, range:)
    step       = RANGES.fetch(range, RANGES['1h'])[:step]
    bucket_end = bucket + step.seconds

    sql = <<~SQL
      SELECT run_id,
             MIN(created_at)                        AS started_at,
             COUNT(*)                               AS request_count,
             COUNT(*) FILTER (WHERE status >= 500)  AS failures,
             MAX(result)                            AS result
      FROM traces
      WHERE source = 'canary'
        AND run_id IS NOT NULL
        AND created_at >= ?
        AND created_at <  ?
      GROUP BY run_id
      ORDER BY started_at ASC
    SQL

    runs = connection.select_all(sanitize_sql_array([sql, bucket, bucket_end]))

    runs.map do |run|
      { run_id:        run['run_id'],
        started_at:    run['started_at'],
        request_count: run['request_count'],
        failures:      run['failures'],
        result:        run['result'] }
    end
  end

  def self.run_traces(run_id:)
    where(run_id: run_id).order(created_at: :asc)
  end

  private_class_method :normalize_endpoint
end
