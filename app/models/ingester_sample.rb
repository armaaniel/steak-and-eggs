class IngesterSample < ApplicationRecord
  SPAN_CAP_SECONDS = 90
  TRANSITION_LIMIT = 200

  # Attributes wall-clock seconds to each state; shared by .spans and .uptime, and not partitioned by boot_id so the pair straddling a restart survives.
  SPAN_SQL = <<~SQL.freeze
    WITH ordered AS (
      SELECT
        at,
        id,
        boot_id,
        connection_id,
        state,
        lead(at) OVER (ORDER BY at, id) AS next_at
      FROM ingester_samples
      WHERE at >= :from AND at < :to
    ),
    measured AS (
      SELECT
        at,
        boot_id,
        connection_id,
        state,
        EXTRACT(epoch FROM COALESCE(next_at, :to) - at) AS raw_seconds
      FROM ordered
    ),
    spans AS (
      SELECT
        at,
        boot_id,
        connection_id,
        state,
        LEAST(raw_seconds, #{SPAN_CAP_SECONDS}) AS seconds
      FROM measured

      UNION ALL

      SELECT
        at + (#{SPAN_CAP_SECONDS} * INTERVAL '1 second'),
        boot_id,
        NULL::uuid,
        'down',
        raw_seconds - #{SPAN_CAP_SECONDS}
      FROM measured
      WHERE raw_seconds > #{SPAN_CAP_SECONDS}
    )
  SQL
  MIN_RATE_GAP = 10
  TERMINAL_CAUSES = %w[stale error closed force_disconnect].freeze
  BASE_LAG_MS = 902_000

  # Each sample's mean lag above the feed's baseline. Gated on sampled_events rather
  # than state: the feed runs ~15 min delayed, so a bucket written after the close
  # still carries regular-session events, and state would mask them as idle.
  def self.lag(from:, to:)
    sql = <<~SQL
      SELECT
        at,
        CASE WHEN sampled_events > 0
             THEN (sum_lag_ms::float / sampled_events) - #{BASE_LAG_MS}
        END AS mean_excess_ms,
        sampled_events,
        symbols
      FROM ingester_samples
      WHERE at >= :from AND at < :to
        AND kind = 'tick'
        AND sampled_events > 0
      ORDER BY at
    SQL

    sanitized = sanitize_sql_array([sql, { from: from, to: to }])

    connection.exec_query(sanitized, 'IngesterSample').to_a
  end
  
  # One row per stretch the ingester spent in a state, with how long it lasted.
  def self.spans(from:, to:)
    sql = <<~SQL
      #{SPAN_SQL}
      SELECT
        at,
        boot_id::text,
        connection_id::text,
        state,
        seconds
      FROM spans
      ORDER BY at
    SQL

    sanitized = sanitize_sql_array([sql, { from: from, to: to }])

    connection.exec_query(sanitized, 'IngesterSample').to_a
  end

  # Streaming, idle and down seconds for the window, plus streaming as a percentage.
  def self.uptime(from:, to:)
    sql = <<~SQL
      #{SPAN_SQL}
      SELECT
        COALESCE(sum(seconds) FILTER (WHERE state = 'streaming'), 0) AS streaming_seconds,
        COALESCE(sum(seconds) FILTER (WHERE state = 'idle'), 0) AS idle_seconds,
        COALESCE(sum(seconds) FILTER (WHERE state NOT IN ('streaming', 'idle')), 0) AS down_seconds,
        EXTRACT(epoch FROM (
          :to::timestamptz - GREATEST(:from::timestamptz, (SELECT min(at) FROM ingester_samples)::timestamptz)
        )) AS window_seconds
      FROM spans
    SQL

    sanitized = sanitize_sql_array([sql, { from: from, to: to }])

    row = connection.exec_query(sanitized, 'IngesterSample').first || {}

    streaming = row['streaming_seconds'].to_f
    idle      = row['idle_seconds'].to_f
    down      = row['down_seconds'].to_f
    window    = row['window_seconds'].to_f

    denominator = window - idle

    {
      streaming_seconds: streaming,
      idle_seconds: idle,
      down_seconds: down,
      window_seconds: window,
      pct: denominator.positive? ? ((streaming / denominator) * 100).round(3) : 0.0
    }
  end

  # One row per ingester process, with its connection count and how it exited.
  def self.boots(from:, to:)
    sql = <<~SQL
      SELECT
        boot_id::text AS boot_id,
        min(at) AS started_at,
        max(at) AS last_seen_at,
        EXTRACT(epoch FROM max(at) - min(at)) AS duration_seconds,
        count(DISTINCT connection_id) AS connections,
        greatest(count(DISTINCT connection_id) - 1, 0) AS reconnects,
        CASE
          WHEN bool_or(cause = 'sigterm') THEN 'sigterm'
          WHEN max(at)::timestamptz >= :to::timestamptz - (#{SPAN_CAP_SECONDS} * INTERVAL '1 second') THEN 'running'
          ELSE 'none'
        END AS exit_state
      FROM ingester_samples
      WHERE at >= :from AND at < :to
      GROUP BY boot_id
      ORDER BY min(at) DESC
    SQL

    sanitized = sanitize_sql_array([sql, { from: from, to: to }])

    connection.exec_query(sanitized, 'IngesterSample').to_a
  end

  # One row per websocket connection, with its events, lag and how it ended.
  def self.connections(from:, to:)
    terminal = TERMINAL_CAUSES.map { |cause| "'#{cause}'" }.join(', ')

    sql = <<~SQL
      WITH in_window AS (
        SELECT DISTINCT connection_id
        FROM ingester_samples
        WHERE at >= :from AND at < :to AND connection_id IS NOT NULL
      ),
      per_connection AS (
        SELECT
          samples.connection_id,
          min(samples.boot_id::text) AS boot_id,
          min(samples.at) FILTER (WHERE samples.cause = 'subscriber_spawned') AS spawned_at,
          min(samples.first_message_at) AS first_message_at,
          max(samples.at) AS last_seen_at,
          min(samples.at) FILTER (WHERE samples.cause IN (#{terminal})) AS ended_at,
          (array_agg(samples.cause ORDER BY samples.at)
            FILTER (WHERE samples.cause IN (#{terminal})))[1] AS ended_by,
          max(samples.events) AS events,
          round(
            percentile_cont(0.99) WITHIN GROUP (
              ORDER BY samples.sum_lag_ms::float / NULLIF(samples.sampled_events, 0)
            ) FILTER (
              WHERE samples.kind = 'tick' AND samples.sampled_events > 0
            )
          )::int - #{BASE_LAG_MS} AS p99_mean_excess_ms
        FROM ingester_samples samples
        JOIN in_window ON in_window.connection_id = samples.connection_id
        GROUP BY samples.connection_id
      )
      SELECT
        connection_id::text AS connection_id,
        boot_id,
        spawned_at,
        first_message_at,
        last_seen_at,
        ended_at,
        CASE
          WHEN ended_by IS NOT NULL THEN ended_by
          WHEN last_seen_at::timestamptz >= :to::timestamptz - (#{SPAN_CAP_SECONDS} * INTERVAL '1 second') THEN 'open'
          ELSE 'no record'
        END AS ended_by,
        EXTRACT(epoch FROM last_seen_at - spawned_at) AS duration_seconds,
        events,
        p99_mean_excess_ms
      FROM per_connection
      ORDER BY last_seen_at DESC
    SQL

    sanitized = sanitize_sql_array([sql, { from: from, to: to }])

    connection.exec_query(sanitized, 'IngesterSample').to_a
  end

  # Per-sample events and frames per second, with that sample's symbol count.
  def self.rate(from:, to:)
    sql = <<~SQL
      WITH deltas AS (
        SELECT
          at,
          symbols,
          CASE WHEN sampled_events > 0
               THEN (sum_lag_ms::float / sampled_events) - #{BASE_LAG_MS}
          END AS mean_excess_ms,
          CASE WHEN events < lag(events) OVER w THEN events
               ELSE events - lag(events) OVER w END AS d_events,
          CASE WHEN frames < lag(frames) OVER w THEN frames
               ELSE frames - lag(frames) OVER w END AS d_frames,
          EXTRACT(epoch FROM at - lag(at) OVER w) AS d_seconds
        FROM ingester_samples
        WHERE at >= :from AND at < :to AND kind = 'tick'
        WINDOW w AS (PARTITION BY boot_id ORDER BY at, id)
      )
      SELECT
        at,
        symbols,
        mean_excess_ms,
        d_events / d_seconds AS events_per_sec,
        d_frames / d_seconds AS frames_per_sec
      FROM deltas
      WHERE d_seconds >= #{MIN_RATE_GAP} AND d_events >= 0
      ORDER BY at
    SQL

    sanitized = sanitize_sql_array([sql, { from: from, to: to }])

    connection.exec_query(sanitized, 'IngesterSample').to_a
  end

  # How many connections ended for each terminal cause.
  # The most recent transition rows, newest first, carrying cause and detail.
  def self.transitions(from:, to:)
    where(kind: 'transition')
      .where(at: from...to)
      .order(at: :desc)
      .limit(TRANSITION_LIMIT)
  end
end
