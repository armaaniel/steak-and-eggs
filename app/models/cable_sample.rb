class CableSample < ApplicationRecord

  def self.compare(run_id:)
    sql = <<~SQL
      WITH buckets AS (
        SELECT
          at,
          sum(frames) FILTER (WHERE source = 'publisher')     AS published,
          sum(frames) FILTER (WHERE source = 'client')        AS received,
          count(DISTINCT vu) FILTER (WHERE source = 'client') AS clients
        FROM cable_samples
        WHERE run_id = :run_id
        GROUP BY at
        HAVING count(DISTINCT vu) FILTER (WHERE source = 'client') > 0
      ),
      lag_stats AS (
        SELECT
          at,
          avg(lag)::float                                     AS mean_lag_ms,
          percentile_cont(0.99) WITHIN GROUP (ORDER BY lag)   AS p99_lag_ms
        FROM cable_samples, unnest(lags) AS lag
        WHERE run_id = :run_id AND source = 'client'
        GROUP BY at
      )
      SELECT
        buckets.at,
        buckets.published,
        buckets.received,
        buckets.clients,
        max(buckets.clients) OVER ()                      AS peak_clients,
        buckets.published * max(buckets.clients) OVER ()  AS expected,
        lag_stats.mean_lag_ms,
        lag_stats.p99_lag_ms
      FROM buckets
      LEFT JOIN lag_stats ON lag_stats.at = buckets.at
      ORDER BY buckets.at
    SQL

    sanitized = sanitize_sql_array([sql, { run_id: run_id }])

    connection.exec_query(sanitized, 'CableSample').to_a
  end

  def self.runs(limit: 25)
    group(:run_id)
      .order(Arel.sql('MIN(at) DESC'))
      .limit(limit)
      .pluck(:run_id, Arel.sql('MIN(at)'), Arel.sql('MAX(at)'), Arel.sql('COUNT(*)'))
      .map { |run_id, started_at, ended_at, samples|
        { run_id: run_id, started_at: started_at, ended_at: ended_at, samples: samples }
      }
  end
end
