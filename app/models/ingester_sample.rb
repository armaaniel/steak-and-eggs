class IngesterSample < ApplicationRecord
  SPAN_CAP_SECONDS = 90

  # How wall-clock time is attributed to states. Shared by .spans and .uptime so the strip
  # and the percentage cannot disagree about the same window.
  #
  # A sample vouches for at most SPAN_CAP_SECONDS. Time past that is time nothing reported,
  # and for a process that samples every minute — into the same database this reads from —
  # not reporting means it was not running, so the remainder is emitted as its own `down`
  # span. That row is derived, not stored: it comes from the pair of samples straddling the
  # gap, which is also why `ordered` is deliberately NOT partitioned by boot_id. Partitioning
  # would sever the very pair that spans a restart.
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
  TERMINAL_CAUSES = %w[stale error closed].freeze
  BASE_LAG_MS = 902_000

  def self.lag(from:, to:)
    sql = <<~SQL
      SELECT
        at,
        max_lag_ms - #{BASE_LAG_MS} AS max_excess_ms,
        CASE WHEN sampled_events > 0
             THEN (sum_lag_ms::float / sampled_events) - #{BASE_LAG_MS}
        END AS mean_excess_ms,
        sampled_events,
        symbols
      FROM ingester_samples
      WHERE at >= :from AND at < :to
        AND kind = 'tick'
        AND state = 'streaming'
        AND sampled_events > 0
      ORDER BY at
    SQL

    sanitized = sanitize_sql_array([sql, { from: from, to: to }])

    connection.exec_query(sanitized, 'IngesterSample').to_a
  end
  
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

  def self.uptime(from:, to:)
    # The window is measured from the first sample on record when :from predates it, so a
    # long window over a young deployment reports on the time it actually has telemetry for
    # rather than booking the difference as downtime. GREATEST ignores NULL, so an empty
    # table falls back to the requested window.
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
    terminal = TERMINAL_CAUSES.map { |cause| "'#{cause}'" }.join(', ')

    # The window decides which connections to list; it must not decide what we know about
    # them. A socket spawned before :from still has its spawn sample on record, so the
    # facts are aggregated over every sample for those ids — otherwise the healthiest
    # case, one connection held across the whole window, has no spawn row inside it and
    # drops out entirely.
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
          -- the cause at that same moment: min(cause) would pick alphabetically, so a
          -- connection that both errored and went stale would report the wrong reason
          (array_agg(samples.cause ORDER BY samples.at)
            FILTER (WHERE samples.cause IN (#{terminal})))[1] AS ended_by
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
        ended_by,
        EXTRACT(epoch FROM first_message_at - spawned_at) AS connect_seconds,
        EXTRACT(epoch FROM last_seen_at - spawned_at) AS duration_seconds
      FROM per_connection
      ORDER BY last_seen_at DESC
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