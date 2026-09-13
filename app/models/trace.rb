class Trace < ApplicationRecord
  PROBE_INTERVAL = 300  # seconds between synthetic probe runs (5 min)

  RANGES = {
    '1h'  => {seconds_per_bucket: 300,   buckets: 12},  # 12 × 5 min
    '12h' => {seconds_per_bucket: 3600,  buckets: 12},  # 12 × 1 hr
    '24h' => {seconds_per_bucket: 3600,  buckets: 24},  # 24 × 1 hr
    '7d'  => {seconds_per_bucket: 21600, buckets: 28},  # 28 × 6 hr
    '14d' => {seconds_per_bucket: 43200, buckets: 28},  # 28 × 12 hr
    '30d' => {seconds_per_bucket: 86400, buckets: 30}   # 30 × 1 day
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

    query = where("endpoint ILIKE ?", route)
    .where.not("breakdown::text = ? OR breakdown IS NULL", '{}')
    .where(source: 'user')

    {
      redis_query: query.where("breakdown::text LIKE ?", '%"used_redis":true%').order(created_at: :desc),
      db_api_query: query.where("breakdown::text LIKE ? OR breakdown::text LIKE ?", '%"used_api":true%', '%"used_db":true%').order(created_at: :desc),
    }
  end

  def self.stats(endpoint:)
    route = normalize_endpoint(endpoint)

    sql = <<~SQL
      SELECT
        COUNT(*) AS total_requests,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY duration) AS p50,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration) AS p95,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration) AS p99,
        COUNT(*) FILTER (WHERE status >= 500) AS error_count,
        bool_or(breakdown::text LIKE '%"used_redis"%') AS uses_redis,
        bool_or(breakdown::text LIKE '%"used_api"%')   AS uses_api
      FROM traces
      WHERE source = 'user'
        AND endpoint ILIKE ?
    SQL

    result = connection.select_all(sanitize_sql_array([sql, route])).first
      
    total  = result['total_requests'].to_i
    errors = result['error_count'].to_f

    {total_requests: total,
      p50: result['p50'].to_f,
      p95: result['p95'].to_f,
      p99: result['p99'].to_f,
      error_rate: total.zero? ? 0.0 : (errors / total * 100).round(2),
      uses_redis: result['uses_redis'] || false,
      uses_api: result['uses_api'] || false}
  end

  def self.latent
    where.not(endpoint: ['POST /graphql', 'POST /record']).where(source: 'user').order(duration: :desc).limit(1000)
  end

  def self.synthetic_buckets(range:)
    spec = RANGES.fetch(range, RANGES['1h'])
    
    seconds_per_bucket = spec[:seconds_per_bucket]
    buckets = spec[:buckets]
    
    sql = <<~SQL
      SELECT
        floor(extract(epoch FROM created_at) / ?) * ? AS bucket,
        COUNT(DISTINCT run_id)                                                 AS started,
        COUNT(DISTINCT run_id) FILTER (WHERE result = 'pass')                  AS completed,
        COUNT(DISTINCT run_id) FILTER (WHERE result = 'fail' OR status >= 500) AS failures
      FROM traces
      WHERE source = 'canary'
        AND created_at > ?
      GROUP BY bucket
      ORDER BY bucket
    SQL
    current_bucket = Time.at((Time.now.to_i / seconds_per_bucket) * seconds_per_bucket).utc
    cutoff  = current_bucket - (seconds_per_bucket * buckets)
    
    rows = connection.execute(sanitize_sql_array([sql, seconds_per_bucket, seconds_per_bucket, cutoff]))
    
    by_bucket = rows.index_by do |row| 
      row['bucket'].to_i 
    end
    
    buckets.downto(1).map do |buckets_back|
      bucket = current_bucket - (buckets_back * seconds_per_bucket)
      row    = by_bucket[bucket.to_i] || {}
      { bucket: bucket,
        started:   row['started'].to_i,
        completed: row['completed'].to_i,
        failures:  row['failures'].to_i,
        expected:  seconds_per_bucket / PROBE_INTERVAL }
    end
  end

  def self.synthetic_runs(bucket:, range:)
    seconds_per_bucket = RANGES.fetch(range, RANGES['1h'])[:seconds_per_bucket]
    bucket_end = bucket + seconds_per_bucket

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
