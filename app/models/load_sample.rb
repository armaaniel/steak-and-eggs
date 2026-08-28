class LoadSample < ApplicationRecord
  def self.compare(run_id:, route:, step: 15)
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

    rows = connection.execute(sanitize_sql_array([sql, step, step, run_id, route]))

    rows.map do |r|
      client_p99 = r['client_p99']&.to_f || 0.0
      server_p99 = r['server_p99']&.to_f || 0.0
      {
        bucket:     Time.at(r['bucket'].to_i).utc,
        rps:        (r['sent'].to_i / step.to_f).round(1),
        sent:       r['sent'].to_i,
        traced:     r['traced'].to_i,
        gap:        r['gap'].to_i,
        errors:     r['errors'].to_i,
        client_p50: r['client_p50']&.to_f || 0.0,
        client_p99: client_p99,
        server_p50: r['server_p50']&.to_f || 0.0,
        server_p99: server_p99,
        queue_p99:  (client_p99 - server_p99).round(2)
      }
    end
  end

  def self.queue_delay(run_id:, route:)
    joins("JOIN traces t ON t.request_id = load_samples.request_id")
      .where(run_id: run_id, route: route)
      .pluck(Arel.sql('load_samples.waiting - t.duration'))
  end

  # One row per run and route, newest first — what the run picker lists.
  def self.runs(limit: 25)
    group(:run_id, :route)
      .order(Arel.sql('MIN(at) DESC'))
      .limit(limit)
      .pluck(:run_id, :route, Arel.sql('MIN(at)'), Arel.sql('MAX(at)'), Arel.sql('COUNT(*)'))
      .map { |run_id, route, started_at, ended_at, samples|
        {run_id: run_id, route: route, started_at: started_at, ended_at: ended_at, samples: samples}
      }
  end
end
