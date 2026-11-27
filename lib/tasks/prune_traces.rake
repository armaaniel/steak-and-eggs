require 'zlib'

BATCH_SIZE = 10_000
BATCH_PAUSE = 0.05  # seconds between batches, to let autovacuum keep up
RETENTION = 31.days
ARCHIVE_BUCKET = ENV.fetch('ARCHIVE_BUCKET', 'steakneggs-datacat-archive')
ARCHIVE_BATCH = 1_000

prune = lambda do |scope, label|
  deleted = 0
  scope.in_batches(of: BATCH_SIZE) do |batch|
    deleted += batch.delete_all
    sleep BATCH_PAUSE
  end
  Rails.logger.info("prune_traces: deleted #{deleted} #{label}")
end

day_range = lambda do |day|
  from = Time.utc(day.year, day.month, day.day)
  from...(from + 1.day)
end

trace_sources = lambda do
  Trace.connection.select_values(<<~SQL)
    WITH RECURSIVE s AS (
      (SELECT source FROM traces ORDER BY source LIMIT 1)
      UNION ALL
      SELECT (SELECT source FROM traces WHERE source > s.source ORDER BY source LIMIT 1) FROM s WHERE s.source IS NOT NULL
    )
    SELECT source FROM s WHERE source IS NOT NULL AND source <> 'load'
  SQL
end

copy_rows = lambda do |out, table, time, day, source = nil|
  range = day_range.(day)
  rows, last_at, last_id = 0, range.begin, 0
  loop do
    sql = <<~SQL
      SELECT #{time}, id, row_to_json(t)::text FROM #{table} t
      WHERE #{time} >= :from AND #{time} < :to AND (#{time}, id) > (:last_at, :last_id)
      #{'AND source = :source' if source}
      ORDER BY #{time}, id
      LIMIT :batch
    SQL
    batch = Trace.connection.select_rows(Trace.sanitize_sql_array([sql, {
      from: range.begin, to: range.end, last_at: last_at, last_id: last_id, source: source, batch: ARCHIVE_BATCH
    }]))
    break if batch.empty?

    batch.each { |(_, _, line)| out.puts(line) }
    rows += batch.size
    last_at, last_id = batch.last[0], batch.last[1]
  end
  rows
end

upload = lambda do |s3, table, day, write|
  Tempfile.create([table, '.jsonl.gz'], binmode: true) do |file|
    gz = Zlib::GzipWriter.new(file)
    rows = write.(gz)
    gz.finish
    file.flush
    size = file.size
    file.rewind

    key = "#{table}/#{day.iso8601}.jsonl.gz"
    s3.put_object(bucket: ARCHIVE_BUCKET, key: key, body: file, content_type: 'application/gzip', metadata: { 'rows' => rows.to_s })
    head = s3.head_object(bucket: ARCHIVE_BUCKET, key: key)
    unless head.content_length == size && head.metadata['rows'] == rows.to_s
      raise "#{key}: wrote #{size} bytes and #{rows} rows, S3 has #{head.content_length} and #{head.metadata['rows']}"
    end

    Rails.logger.info("archive: #{key} #{rows} rows, #{size} bytes")
    rows
  end
end

export_day = lambda do |s3, day|
  sources = trace_sources.()
  {
    'traces' => upload.(s3, 'traces', day, ->(out) { sources.sum { |source| copy_rows.(out, 'traces', 'created_at', day, source) } }),
    'ingester_samples' => upload.(s3, 'ingester_samples', day, ->(out) { copy_rows.(out, 'ingester_samples', 'at', day) })
  }
end

oldest_day = lambda do
  times = trace_sources.().map { |source| Trace.where(source: source).minimum(:created_at) }
  times << IngesterSample.minimum(:at)
  times.compact.min&.utc&.to_date
end

task prune_traces: :environment do
  JobRun.track('prune_traces') do
    s3 = Aws::S3::Client.new(region: 'us-west-1')
    keep_from = (Time.now.utc - RETENTION).to_date
    oldest = oldest_day.()

    (oldest...keep_from).each do |day|
      export_day.(s3, day)
      prune.call(Trace.where(source: trace_sources.(), created_at: day_range.(day)), "traces for #{day}")
      prune.call(IngesterSample.where(at: day_range.(day)), "ingester_samples for #{day}")
    end if oldest

    export_day.(s3, Time.now.utc.to_date - 1)
  end
end

namespace :archive do
  task backfill: :environment do
    s3 = Aws::S3::Client.new(region: 'us-west-1')
    from = ENV['FROM'] ? Date.parse(ENV['FROM']) : oldest_day.()
    to = ENV['TO'] ? Date.parse(ENV['TO']) : Time.now.utc.to_date - 1
    (from..to).each do |day|
      counts = export_day.(s3, day)
      puts "#{day} #{counts.map { |table, rows| "#{table} #{rows}" }.join(', ')}"
    end
  end
end
