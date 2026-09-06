class CableSample < ApplicationRecord

  def self.compare(run_id:)
    sql = <<~SQL
      WITH buckets AS (
        SELECT
          at,
          sum(frames) FILTER (WHERE source = 'publisher')            AS published,
          sum(frames) FILTER (WHERE source = 'client')               AS received,
          count(DISTINCT vu) FILTER (WHERE source = 'client')        AS clients,
          sum(sum_lag_ms) FILTER (WHERE source = 'client')           AS sum_lag_ms,
          sum(frames) FILTER (WHERE source = 'client' AND suspect = false) AS clean_frames
        FROM cable_samples
        WHERE run_id = :run_id
        GROUP BY at
        HAVING count(DISTINCT vu) FILTER (WHERE source = 'client') > 0
      ),
      lags AS (
        SELECT at, unnest(sample_lags) AS lag
        FROM cable_samples
        WHERE run_id = :run_id AND source = 'client' AND suspect = false
      )
      SELECT
        buckets.at,
        buckets.published,
        buckets.received,
        buckets.clients,
        buckets.published * buckets.clients AS expected,
        CASE WHEN buckets.clean_frames > 0
             THEN buckets.sum_lag_ms::float / buckets.clean_frames
        END AS mean_lag_ms,
        percentile_cont(0.99) WITHIN GROUP (ORDER BY lags.lag) AS p99_lag_ms
      FROM buckets
      LEFT JOIN lags ON lags.at = buckets.at
      GROUP BY buckets.at, buckets.published, buckets.received,
               buckets.clients, buckets.sum_lag_ms, buckets.clean_frames
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
