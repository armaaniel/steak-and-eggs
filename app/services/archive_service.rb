require 'zlib'

class ArchiveService
  BUCKET = ENV.fetch('ARCHIVE_BUCKET', 'steakneggs-datacat-archive')
  REGION = 'us-west-1'
  BATCH = 1_000

  class UploadMismatch < StandardError; end

  class << self
    def export_day(day)
      { 'traces' => export_traces(day), 'ingester_samples' => export_ingester_samples(day) }
    end

    def traces_scope(day)
      Trace.where(source: trace_sources, created_at: bounds(day))
    end

    def ingester_samples_scope(day)
      IngesterSample.where(at: bounds(day))
    end

    def oldest_day
      times = trace_sources.map { |source| Trace.where(source: source).minimum(:created_at) }
      times << IngesterSample.minimum(:at)
      times.compact.min&.utc&.to_date
    end

    def key(table, day)
      "#{table}/#{day.iso8601}.jsonl.gz"
    end

    def client
      @client ||= Aws::S3::Client.new(region: REGION)
    end

    attr_writer :client

    private

    def bounds(day)
      from = Time.utc(day.year, day.month, day.day)
      from...(from + 1.day)
    end

    def trace_sources
      Trace.connection.select_values(<<~SQL)
        WITH RECURSIVE s AS (
          (SELECT source FROM traces ORDER BY source LIMIT 1)
          UNION ALL
          SELECT (SELECT source FROM traces WHERE source > s.source ORDER BY source LIMIT 1) FROM s WHERE s.source IS NOT NULL
        )
        SELECT source FROM s WHERE source IS NOT NULL AND source <> 'load'
      SQL
    end

    def export_traces(day)
      write('traces', day) do |out|
        trace_sources.sum { |source| copy(out, 'traces', 'created_at', day, source: source) }
      end
    end

    def export_ingester_samples(day)
      write('ingester_samples', day) { |out| copy(out, 'ingester_samples', 'at', day) }
    end

    def copy(out, table, time, day, source: nil)
      range = bounds(day)
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
          from: range.begin, to: range.end, last_at: last_at, last_id: last_id, source: source, batch: BATCH
        }]))
        break if batch.empty?

        batch.each { |(_, _, line)| out.puts(line) }
        rows += batch.size
        last_at, last_id = batch.last[0], batch.last[1]
      end
      rows
    end

    def write(table, day)
      Tempfile.create([table, '.jsonl.gz'], binmode: true) do |file|
        gz = Zlib::GzipWriter.new(file)
        rows = yield(gz)
        gz.finish
        file.flush
        size = file.size
        file.rewind

        key = key(table, day)
        client.put_object(bucket: BUCKET, key: key, body: file, content_type: 'application/gzip',
                          metadata: { 'rows' => rows.to_s })
        head = client.head_object(bucket: BUCKET, key: key)
        unless head.content_length == size && head.metadata['rows'] == rows.to_s
          raise UploadMismatch, "#{key}: wrote #{size} bytes and #{rows} rows, S3 has #{head.content_length} and #{head.metadata['rows']}"
        end

        Rails.logger.info("archive: #{key} #{rows} rows, #{size} bytes")
        rows
      end
    end
  end
end
