class LoadSample < ApplicationRecord
  COMPARE_CACHE_VERSION = 1
  RUNS_CACHE_KEY = 'load_runs:v1'

  def self.compare(run_id:, route:, step:)
    key = "load_compare:v#{COMPARE_CACHE_VERSION}:#{run_id}:#{route}:#{step}"
    cached = RedisService.safe_get(key)
    return JSON.parse(cached) if cached

    sql = <<~SQL
      SELECT
        floor(extract(epoch FROM ls.at) / ?) * ? AS bucket,
        count(*)                                                          AS sent,
        count(t.id)                                                       AS traced,
        count(*) - count(t.id)                                            AS gap,
        percentile_disc(0.50) WITHIN GROUP (ORDER BY ls.waiting)           AS client_p50,
        percentile_disc(0.99) WITHIN GROUP (ORDER BY ls.waiting)           AS client_p99,
        percentile_disc(0.50) WITHIN GROUP (ORDER BY t.duration)           AS server_p50,
        percentile_disc(0.99) WITHIN GROUP (ORDER BY t.duration)           AS server_p99,
        count(*) FILTER (WHERE ls.status >= 500 OR ls.status = 0)          AS errors
      FROM load_samples ls
      LEFT JOIN traces t ON t.request_id = ls.request_id
      WHERE ls.run_id = ? AND ls.route = ?
      GROUP BY bucket
      ORDER BY bucket
    SQL

    buckets = connection.execute(sanitize_sql_array([sql, step, step, run_id, route]))

    rows = buckets.map do |bucket|
      {
        bucket:     Time.at(bucket['bucket'].to_i).utc,
        rps:        (bucket['sent'].to_f / step).round(1),
        sent:       bucket['sent'].to_i,
        traced:     bucket['traced'].to_i,
        gap:        bucket['gap'].to_i,
        errors:     bucket['errors'].to_i,
        client_p50: bucket['client_p50'].to_f,
        client_p99: bucket['client_p99'].to_f,
        server_p50: bucket['server_p50'].to_f,
        server_p99: bucket['server_p99'].to_f,
      }
    end

    finished = rows.any? && rows.last[:bucket] < 5.minutes.ago
    RedisService.safe_set(key, rows.to_json) if finished

    rows
  end

  def self.runs
    cached = RedisService.safe_get(RUNS_CACHE_KEY)
    return JSON.parse(cached) if cached

    sql = <<~SQL
      SELECT run_id,
             route,
             MIN(at)  AS started_at,
             MAX(at)  AS ended_at,
             COUNT(*) AS samples
      FROM load_samples
      GROUP BY run_id, route
      ORDER BY started_at DESC
    SQL

    result = connection.select_all(sql)

    runs = result.map do |run|
      { run_id:     run['run_id'],
        route:      run['route'],
        started_at: run['started_at'],
        ended_at:   run['ended_at'],
        samples:    run['samples'] }
    end

    finished = runs.any? && runs.map { |run| run[:ended_at] }.max < 5.minutes.ago
    RedisService.safe_set(RUNS_CACHE_KEY, runs.to_json) if finished

    runs
  end

  def self.expire_runs
    RedisService.safe_del(RUNS_CACHE_KEY)
  end
end