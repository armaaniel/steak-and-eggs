class CableSample < ApplicationRecord
  COMPARE_CACHE_VERSION = 1
  RUNS_CACHE_KEY = 'cable_runs:v1'

  def self.compare(run_id:, step:)
    key = "cable_compare:v#{COMPARE_CACHE_VERSION}:#{run_id}:#{step}"
    cached = RedisService.safe_get(key)
    return JSON.parse(cached) if cached

    sql = <<~SQL
      WITH buckets AS (
        SELECT
          date_bin(make_interval(secs => :step), at, TIMESTAMP 'epoch') AS at,
          sum(frames) FILTER (WHERE source = 'publisher')     AS published,
          sum(frames) FILTER (WHERE source = 'client')        AS received,
          count(DISTINCT vu) FILTER (WHERE source = 'client') AS clients
        FROM cable_samples
        WHERE run_id = :run_id
        GROUP BY 1
        HAVING count(DISTINCT vu) FILTER (WHERE source = 'client') > 0
      ),
      lag_stats AS (
        SELECT
          date_bin(make_interval(secs => :step), at, TIMESTAMP 'epoch') AS at,
          percentile_disc(0.50) WITHIN GROUP (ORDER BY lag)   AS p50_lag_ms,
          percentile_disc(0.99) WITHIN GROUP (ORDER BY lag)   AS p99_lag_ms
        FROM cable_samples, unnest(lags) AS lag
        WHERE run_id = :run_id AND source = 'client'
        GROUP BY 1
      )
      SELECT
        buckets.at,
        buckets.published,
        buckets.received,
        buckets.clients,
        max(buckets.clients) OVER ()                      AS peak_clients,
        buckets.published * max(buckets.clients) OVER ()  AS expected,
        lag_stats.p50_lag_ms,
        lag_stats.p99_lag_ms
      FROM buckets
      LEFT JOIN lag_stats ON lag_stats.at = buckets.at
      ORDER BY buckets.at
    SQL

    sanitized = sanitize_sql_array([sql, { run_id: run_id, step: step }])
    rows = connection.exec_query(sanitized, 'CableSample').to_a

    finished = rows.any? && rows.last['at'] < 5.minutes.ago
    RedisService.safe_set(key, rows.to_json) if finished

    rows
  end

  def self.runs
    cached = RedisService.safe_get(RUNS_CACHE_KEY)
    return JSON.parse(cached) if cached

    runs = group(:run_id)
      .order(Arel.sql('MIN(at) DESC'))
      .pluck(:run_id, Arel.sql('MIN(at)'), Arel.sql('MAX(at)'), Arel.sql('COUNT(*)'))
      .map { |run_id, started_at, ended_at, samples|
        { run_id: run_id, started_at: started_at, ended_at: ended_at, samples: samples }
      }

    finished = runs.any? && runs.map { |run| run[:ended_at] }.max < 5.minutes.ago
    RedisService.safe_set(RUNS_CACHE_KEY, runs.to_json) if finished

    runs
  end

  def self.expire_runs
    RedisService.safe_del(RUNS_CACHE_KEY)
  end
end
