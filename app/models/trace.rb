class Trace < ApplicationRecord
  PROBE_INTERVAL = 300
  SLO_TARGET = 0.995
  SLO_PERIOD = 30.days
  POLYGON_LOOKBACK = 1.day
  SCATTER_COLUMNS = 600
  SCATTER_ROWS_PER_DECADE = 25

  RANGES = {
    '10m' => {seconds_per_bucket: 300,   buckets: 2},
    '1h'  => {seconds_per_bucket: 300,   buckets: 12},  # 12 × 5 min
    '12h' => {seconds_per_bucket: 3600,  buckets: 12},  # 12 × 1 hr
    '24h' => {seconds_per_bucket: 3600,  buckets: 24},  # 24 × 1 hr
    '7d'  => {seconds_per_bucket: 21600, buckets: 28},  # 28 × 6 hr
    '14d' => {seconds_per_bucket: 43200, buckets: 28},  # 28 × 12 hr
    '30d' => {seconds_per_bucket: 86400, buckets: 30}   # 30 × 1 day
  }

  TRACE_SORT_COLUMNS = %w[created_at duration status].freeze

  CACHE_CONDITIONS = {
    'cached' => ['breakdown::text LIKE ?', '%"used_redis":true%'],
    'uncached' => ['breakdown::text LIKE ? OR breakdown::text LIKE ?', '%"used_api":true%', '%"used_db":true%']
  }.freeze

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

  def self.summary(range: nil)
    start = window_start(range)

    sql = <<~SQL
      SELECT #{route_case} as route,
        COUNT(*) as total_requests,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY duration) as p99,
        COUNT(*) FILTER (WHERE breakdown::text LIKE '%"used_redis":true%') as cache_hits,
        COUNT(*) FILTER (WHERE breakdown IS NOT NULL AND breakdown::text != '{}') as with_breakdown
      FROM traces
      WHERE source IN ('user', 'canary')
        AND endpoint <> 'POST /graphql'
        AND created_at >= ?
      GROUP BY route
      ORDER BY total_requests DESC
    SQL

    results = connection.execute(sanitize_sql_array([sql, start]))
    results.map do |row|
      route = row['route']
      with_breakdown = row['with_breakdown'].to_i
      rate = (row['cache_hits'].to_f / with_breakdown * 100).round(1) unless with_breakdown.zero?
      
      {
        route: route,
        clean_route: route.downcase.delete(' '),
        total_requests: row['total_requests'].to_i,
        p99: row['p99'].to_f,
        cache_hit_rate: route.start_with?('POST') ? nil : rate
      }
    end
  end

  def self.cache_condition(cache)
    cache ? sanitize_sql_array(CACHE_CONDITIONS.fetch(cache)) : 'TRUE'
  end

  def self.list(endpoint: nil, range: nil, bucket: nil, bucket_end: nil, status: nil, cache: nil, sort: nil, direction: nil)
    sort ||= 'created_at'
    direction ||= 'desc'
    raise(ArgumentError, "can't sort traces by #{sort}") unless TRACE_SORT_COLUMNS.include?(sort)
    raise(ArgumentError, "can't sort traces #{direction}") unless %w[asc desc].include?(direction)

    window = bucket && bucket_end ? (bucket...bucket_end) : (window_start(range)..)
    traces = endpoint ? where("endpoint ILIKE ?", normalize_endpoint(endpoint)) : where.not(endpoint: 'POST /graphql')
    traces = traces.where(status: status) if status
    traces = traces.where(cache_condition(cache)) if cache
    column = direction == 'asc' ? arel_table[sort].asc.nulls_last : arel_table[sort].desc.nulls_last

    traces.where(source: %w[user canary])
      .where(created_at: window)
      .order(column, id: direction)
      .limit(1000)
  end

  def self.stats(endpoint:, range: nil)
    route = normalize_endpoint(endpoint)

    sql = <<~SQL
      SELECT
        COUNT(*) AS total_requests,
        PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY duration) AS p50,
        PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY duration) AS p95,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY duration) AS p99,
        COUNT(*) FILTER (WHERE status >= 500) AS error_count,
        bool_or(breakdown::text LIKE '%"used_redis"%') AS used_redis,
        bool_or(breakdown::text LIKE '%"used_api"%')   AS used_api
      FROM traces
      WHERE source IN ('user', 'canary')
        AND endpoint ILIKE ?
        AND created_at >= ?
    SQL

    result = connection.select_all(sanitize_sql_array([sql, route, window_start(range)])).first
      
    total  = result['total_requests'].to_i
    errors = result['error_count'].to_f

    {total_requests: total,
      p50: result['p50'].to_f,
      p95: result['p95'].to_f,
      p99: result['p99'].to_f,
      error_rate: total.zero? ? 0.0 : (errors / total * 100).round(2),
      used_redis: result['used_redis'] || false,
      used_api: result['used_api'] || false}
  end

  def self.synthetic_buckets(range:)
    window = RANGES.fetch(range, RANGES['1h'])
    
    seconds_per_bucket = window[:seconds_per_bucket]
    buckets = window[:buckets]
    
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
    
    now = Time.now
    current_bucket = Time.at((now.to_i / seconds_per_bucket) * seconds_per_bucket).utc
    cutoff  = current_bucket - (seconds_per_bucket * buckets)
    
    rows = connection.execute(sanitize_sql_array([sql, seconds_per_bucket, seconds_per_bucket, cutoff]))
    
    by_bucket = rows.index_by { |row| row ['bucket'].to_i }
    
    buckets.downto(0).map do |buckets_back|
      bucket     = current_bucket - (buckets_back * seconds_per_bucket)
      bucket_end = bucket + seconds_per_bucket
      elapsed    = [bucket_end, now].min - bucket
      row        = by_bucket[bucket.to_i] || {}
      { bucket:     bucket,
        bucket_end: bucket_end,
        started:    row['started'].to_i,
        completed:  row['completed'].to_i,
        failures:   row['failures'].to_i,
        expected:   (elapsed / PROBE_INTERVAL).floor }
    end
  end

  def self.synthetic_runs(bucket:, bucket_end:)
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

  def self.synthetic_run_traces(run_id:)
    where(run_id: run_id).order(created_at: :asc)
  end

  def self.service_timeseries(range:, endpoint: nil, include_partial: false, status: nil, cache: nil)
    window = overview_window(range)
    step = window[:step]
    buckets = window[:buckets] + (include_partial ? 1 : 0)
    finish = window[:start] + (buckets * step)
    route = endpoint && normalize_endpoint(endpoint)

    sql = <<~SQL
      SELECT floor(extract(epoch FROM created_at) / ?) * ?          AS bucket,
             COUNT(*)                                               AS requests,
             COUNT(*) FILTER (WHERE status >= 500)                  AS errors,
             percentile_disc(0.50) WITHIN GROUP (ORDER BY duration) AS p50,
             percentile_disc(0.95) WITHIN GROUP (ORDER BY duration) AS p95,
             percentile_disc(0.99) WITHIN GROUP (ORDER BY duration) AS p99
      FROM traces
      WHERE source IN ('user', 'canary')
        AND endpoint <> 'POST /graphql'
        AND (?::text IS NULL OR endpoint ILIKE ?)
        AND (?::int IS NULL OR status = ?)
        AND (#{cache_condition(cache)})
        AND created_at >= ?
        AND created_at < ?
      GROUP BY bucket
    SQL

    rows = connection.select_all(sanitize_sql_array([sql, step, step, route, route, status, status, window[:start], finish]))
    by_bucket = rows.index_by { |row| row['bucket'].to_i }

    buckets.times.map do |index|
      bucket = window[:start] + (index * step)
      row = by_bucket[bucket.to_i] || {}

      { bucket:     bucket,
        bucket_end: bucket + step,
        partial:    index == window[:buckets],
        requests:   row['requests'].to_i,
        errors:     row['errors'].to_i,
        p50:        row['p50']&.to_f,
        p95:        row['p95']&.to_f,
        p99:        row['p99']&.to_f }
    end
  end

  def self.scatter(endpoint:, range: nil, status: nil, cache: nil)
    route = normalize_endpoint(endpoint)
    start = window_start(range)
    column = [(Time.current - start) / SCATTER_COLUMNS, 1].max

    sql = <<~SQL
      SELECT (array_agg(id ORDER BY duration DESC))[1]         AS id,
             (array_agg(created_at ORDER BY duration DESC))[1] AS at,
             (array_agg(status ORDER BY duration DESC))[1]     AS status,
             MAX(duration)                                     AS duration,
             COUNT(*)                                          AS count
      FROM traces
      WHERE source IN ('user', 'canary')
        AND endpoint ILIKE ?
        AND created_at >= ?
        AND (?::int IS NULL OR status = ?)
        AND (#{cache_condition(cache)})
      GROUP BY floor(extract(epoch FROM created_at) / ?),
               floor(log(greatest(duration, 1)) * ?),
               status >= 500
      ORDER BY at
    SQL

    connection.select_all(sanitize_sql_array([sql, route, start, status, status, column, SCATTER_ROWS_PER_DECADE])).map do |row|
      { id:       row['id'],
        at:       row['at'],
        status:   row['status'],
        duration: row['duration'].to_f,
        count:    row['count'].to_i }
    end
  end

  def self.polygon_calls(range:)
    start = window_start(range)

    sql = <<~SQL
      WITH calls AS (
        SELECT traces.created_at,
               traces.created_at >= ? AS recent,
               span.value->>'exception' IS NOT NULL
                 AND span.value->'exception'->>0 <> 'MarketService::NotFoundError' AS failed
        FROM traces
        CROSS JOIN LATERAL json_each(traces.breakdown) AS span
        WHERE traces.source IN ('user', 'canary')
          AND traces.created_at >= ?
          AND traces.breakdown::text LIKE '%"used_api":true%'
          AND span.value->>'used_api' = 'true'
      )
      SELECT COUNT(*) FILTER (WHERE recent)            AS calls,
             COUNT(*) FILTER (WHERE recent AND failed) AS failures,
             MAX(created_at) FILTER (WHERE NOT failed) AS last_success_at
      FROM calls
    SQL

    row = connection.select_all(sanitize_sql_array([sql, start, [start, POLYGON_LOOKBACK.ago].min])).first

    { calls:           row['calls'].to_i,
      failures:        row['failures'].to_i,
      last_success_at: row['last_success_at'] }
  end

  def self.window_start(range)
    range ? overview_window(range)[:start] : Time.at(0)
  end

  def self.overview_window(range)
    window = RANGES.fetch(range, RANGES['24h'])
    step = window[:seconds_per_bucket]
    finish = Time.at((Time.now.to_i / step) * step).utc

    {start: finish - (step * window[:buckets]), finish: finish, step: step, buckets: window[:buckets]}
  end

  def self.canary_slo(range:)
    window = RANGES.fetch(range, RANGES['1h'])
    finish = Time.at((Time.now.to_i / PROBE_INTERVAL) * PROBE_INTERVAL).utc

    sli = canary_counts(start: finish - (window[:seconds_per_bucket] * window[:buckets]), finish: finish)
    budget = canary_counts(start: finish - SLO_PERIOD, finish: finish)

    { target:          SLO_TARGET,
      good:            sli[:good],
      expected:        sli[:expected],
      period_good:     budget[:good],
      period_expected: budget[:expected],
      budget_allowed:  (budget[:expected] * (1 - SLO_TARGET)).floor,
      budget_used:     budget[:expected] - budget[:good] }
  end

  def self.canary_counts(start:, finish:)
    sql = <<~SQL
      WITH runs AS (
        SELECT run_id,
               bool_or(result = 'pass')                  AS passed,
               bool_or(result = 'fail' OR status >= 500) AS failed
        FROM traces
        WHERE source = 'canary'
          AND run_id IS NOT NULL
          AND created_at >= ?
          AND created_at <  ?
        GROUP BY run_id
      )
      SELECT COUNT(*) FILTER (WHERE passed AND failed IS NOT TRUE) FROM runs
    SQL

    good = connection.select_value(sanitize_sql_array([sql, start, finish])).to_i
    expected = ((finish - start) / PROBE_INTERVAL).to_i

    {good: [good, expected].min, expected: expected}
  end

  private_class_method(:normalize_endpoint, :canary_counts, :overview_window, :window_start)
end
