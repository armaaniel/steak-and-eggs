class IngesterSample < ApplicationRecord
  SPAN_CAP_SECONDS = 90
  MIN_RATE_GAP = 10
  TERMINAL_CAUSES = %w[stale error closed].freeze
  BASE_LAG_MS = 902_000

  def self.lag(from:, to:)
    query(<<~SQL, from, to).to_a
      SELECT
        at,
        max_lag_ms - #{BASE_LAG_MS} AS max_excess_ms,
        CASE WHEN lagged_events > 0
             THEN (sum_lag_ms::float / lagged_events) - #{BASE_LAG_MS}
        END AS mean_excess_ms,
        lagged_events,
        symbols
      FROM ingester_samples
      WHERE at >= :from AND at < :to
        AND kind = 'tick'
        AND state = 'streaming'
        AND lagged_events > 0
      ORDER BY at
    SQL
  end
  
  def self.spans(from:, to:)
    sql = <<~SQL
      WITH ordered AS (
        SELECT 
        at, 
        boot_id, 
        connection_id, 
        state,
        lead(at) OVER (ORDER BY at, id) AS next_at
        FROM ingester_samples
        WHERE at >= :from AND at < :to
      )
      SELECT at,
             boot_id::text,
             connection_id::text,
             state,
             LEAST(
               EXTRACT(epoch FROM COALESCE(next_at, :to) - at), #{SPAN_CAP_SECONDS}) AS seconds
      FROM ordered
      ORDER BY at
    SQL

    sanitized = sanitize_sql_array([sql, { from: from, to: to }])

    connection.exec_query(sanitized, 'IngesterSample').to_a
  end

  def self.uptime(from:, to:)
    sql = <<~SQL
      WITH ordered AS (
        SELECT
          at,
          state,
          lead(at) OVER (ORDER BY at, id) AS next_at
        FROM ingester_samples
        WHERE at >= :from AND at < :to
      ),
      spans AS (
        SELECT
          state,
          LEAST(
            EXTRACT(epoch FROM COALESCE(next_at, :to) - at),#{SPAN_CAP_SECONDS}) AS span_seconds
        FROM ordered
      )
      SELECT
        COALESCE(sum(span_seconds) FILTER (WHERE state = 'streaming'), 0) AS streaming_seconds,
        COALESCE(sum(span_seconds) FILTER (WHERE state = 'idle'), 0) AS idle_seconds,
        COALESCE(sum(span_seconds) FILTER (WHERE state NOT IN ('streaming', 'idle')), 0) AS down_seconds,
        EXTRACT(epoch FROM (:to::timestamptz - :from::timestamptz)) AS window_seconds
      FROM spans
    SQL

    sanitized = sanitize_sql_array([sql, { from: from, to: to }])

    row = connection.exec_query(sanitized, 'IngesterSample').first || {}

    streaming = row['streaming_seconds'].to_f
    idle      = row['idle_seconds'].to_f
    down      = row['down_seconds'].to_f
    window    = row['window_seconds'].to_f

    unaccounted = [window - streaming - idle - down, 0].max
    denominator = window - idle

    {
      streaming_seconds: streaming,
      idle_seconds: idle,
      down_seconds: down,
      unaccounted_seconds: unaccounted,
      window_seconds: window,
      pct: denominator.positive? ? ((streaming / denominator) * 100).round(3) : 0.0
    }
  end

  def self.boots(from:, to:)
    sql = <<~SQL
      SELECT
        boot_id::text AS boot_id,
        min(at) AS started_at,
        max(at) AS last_seen_at,
        EXTRACT(epoch FROM max(at) - min(at)) AS duration_seconds,
        count(DISTINCT connection_id) AS connections,
        greatest(count(DISTINCT connection_id) - 1, 0) AS reconnects,
        bool_or(cause = 'sigterm') AS clean_exit,
        max(events) AS events,
        max(max_lag_ms) AS peak_lag_ms
      FROM ingester_samples
      WHERE at >= :from AND at < :to
      GROUP BY boot_id
      ORDER BY min(at) DESC
    SQL

    sanitized = sanitize_sql_array([sql, { from: from, to: to }])

    connection.exec_query(sanitized, 'IngesterSample').to_a
  end

  def self.connections(from:, to:)
    sql = <<~SQL
      WITH per_connection AS (
        SELECT
          connection_id,
          min(boot_id::text) AS boot_id,
          min(at) FILTER (WHERE cause = 'subscriber_spawned') AS spawned_at,
          min(first_message_at) AS first_message_at,
          max(at) AS last_seen_at,
          min(cause) FILTER (WHERE cause IN ('stale', 'error', 'closed')) AS ended_by
        FROM ingester_samples
        WHERE at >= :from AND at < :to AND connection_id IS NOT NULL
        GROUP BY connection_id
      )
      SELECT
        connection_id::text AS connection_id,
        boot_id,
        spawned_at,
        first_message_at,
        last_seen_at,
        ended_by,
        EXTRACT(epoch FROM first_message_at - spawned_at) AS connect_seconds,
        EXTRACT(epoch FROM last_seen_at - spawned_at) AS duration_seconds
      FROM per_connection
      WHERE spawned_at IS NOT NULL
      ORDER BY spawned_at DESC
    SQL

    sanitized = sanitize_sql_array([sql, { from: from, to: to }])

    connection.exec_query(sanitized, 'IngesterSample').to_a
  end

  def self.rate(from:, to:)
    sql = <<~SQL
      WITH deltas AS (
        SELECT
          at,
          max_lag_ms,
          symbols,
          events - lag(events) OVER w AS d_events,
          frames - lag(frames) OVER w AS d_frames,
          EXTRACT(epoch FROM at - lag(at) OVER w) AS d_seconds
        FROM ingester_samples
        WHERE at >= :from AND at < :to AND kind = 'tick'
        WINDOW w AS (PARTITION BY boot_id ORDER BY at, id)
      )
      SELECT
        at,
        max_lag_ms,
        symbols,
        d_events / d_seconds AS events_per_sec,
        d_frames / d_seconds AS frames_per_sec
      FROM deltas
      WHERE d_seconds >= #{MIN_RATE_GAP} AND d_events >= 0
      ORDER BY at
    SQL

    sanitized = sanitize_sql_array([sql, { from: from, to: to }])

    connection.exec_query(sanitized, 'IngesterSample').to_a
  end

  def self.reconnect_causes(from:, to:)
    sql = <<~SQL
      SELECT cause, count(*) AS count
      FROM ingester_samples
      WHERE at >= :from AND at < :to
        AND cause IN (#{TERMINAL_CAUSES.map { |c| "'#{c}'" }.join(', ')})
      GROUP BY cause
      ORDER BY count DESC
    SQL

    sanitized = sanitize_sql_array([sql, { from: from, to: to }])

    connection.exec_query(sanitized, 'IngesterSample').to_a
  end
end