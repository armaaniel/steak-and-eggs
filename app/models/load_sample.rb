class LoadSample < ApplicationRecord
  def self.compare(run_id:, route:, step:)
    
    sql = <<~SQL
      SELECT
        floor(extract(epoch FROM ls.at) / ?) * ? AS bucket,
        count(*)                                                          AS sent,
        count(t.id)                                                       AS traced,
        count(*) - count(t.id)                                            AS gap,
        percentile_cont(0.50) WITHIN GROUP (ORDER BY ls.waiting)           AS client_p50,
        percentile_cont(0.99) WITHIN GROUP (ORDER BY ls.waiting)           AS client_p99,
        percentile_cont(0.50) WITHIN GROUP (ORDER BY t.duration)           AS server_p50,
        percentile_cont(0.99) WITHIN GROUP (ORDER BY t.duration)           AS server_p99,
        count(*) FILTER (WHERE ls.status >= 500 OR ls.status = 0)          AS errors
      FROM load_samples ls
      LEFT JOIN traces t ON t.request_id = ls.request_id
      WHERE ls.run_id = ? AND ls.route = ?
      GROUP BY bucket
      ORDER BY bucket
    SQL

    buckets = connection.execute(sanitize_sql_array([sql, step, step, run_id, route]))

    buckets.map do |bucket|
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
        queue_p99:  (bucket['client_p99'].to_f - bucket['server_p99'].to_f).round(2),
      }
    end
  end

  def self.runs
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

    result.map do |run|
      { run_id:     run['run_id'],
        route:      run['route'],
        started_at: run['started_at'],
        ended_at:   run['ended_at'],
        samples:    run['samples'] }
    end
  end
end