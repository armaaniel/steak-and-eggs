class JobRun < ApplicationRecord
  SCHEDULE = {'tickers:sync' => 4, 'record' => 5, 'prune_traces' => 6}.freeze
  GRACE = 1.hour
  DAY = 1.day.to_i
  DAYS = 30

  def self.track(name)
    run = create!(name: name, started_at: Time.current)
    yield
    run.update!(finished_at: Time.current)
  rescue => e
    event_id = Sentry.capture_exception(e)&.event_id
    run&.update!(finished_at: Time.current, error_class: e.class.name, sentry_event_id: event_id)
    raise
  end

  def status
    if error_class
      'failed'
    elsif finished_at
      'succeeded'
    elsif started_at < GRACE.ago
      'failed'
    else
      'running'
    end
  end

  def self.buckets
    now = Time.now
    today = Time.at((now.to_i / DAY) * DAY).utc
    first_day = today - ((DAYS - 1) * DAY)
    tracked_since = minimum(:started_at)&.utc&.beginning_of_day

    sql = <<~SQL
      SELECT name,
             floor(extract(epoch FROM started_at) / :day) * :day AS bucket,
             COUNT(*)                                            AS started,
             COUNT(*) FILTER (WHERE finished_at IS NOT NULL
                                AND error_class IS NULL)         AS completed,
             COUNT(*) FILTER (WHERE error_class IS NOT NULL
                                 OR (finished_at IS NULL AND started_at < :cutoff)) AS failures
      FROM job_runs
      WHERE started_at >= :from
      GROUP BY name, bucket
    SQL

    rows = connection.select_all(sanitize_sql_array([sql, {day: DAY, cutoff: now - GRACE, from: first_day}]))
    by_bucket = rows.index_by { |row| [row['name'], row['bucket'].to_i] }

    SCHEDULE.flat_map do |name, hour|
      (DAYS - 1).downto(0).map do |days_back|
        bucket = today - (days_back * DAY)
        row = by_bucket[[name, bucket.to_i]] || {}
        due = tracked_since && bucket >= tracked_since && now >= bucket + hour.hours + GRACE

        { name:       name,
          bucket:     bucket,
          bucket_end: bucket + DAY,
          started:    row['started'].to_i,
          completed:  row['completed'].to_i,
          failures:   row['failures'].to_i,
          expected:   due ? 1 : 0 }
      end
    end
  end

  def self.runs(name:, bucket:, bucket_end:)
    where(name: name, started_at: bucket...bucket_end).order(:started_at)
  end
end
