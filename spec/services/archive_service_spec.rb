require 'rails_helper'

RSpec.describe(ArchiveService) do
  let(:objects) { {} }
  let(:s3) do
    Aws::S3::Client.new(stub_responses: true).tap do |client|
      client.stub_responses(:put_object, lambda { |context|
        body = context.params[:body]
        body.rewind
        objects[context.params[:key]] = { body: body.read, metadata: context.params[:metadata] }
        {}
      })
      client.stub_responses(:head_object, lambda { |context|
        object = objects.fetch(context.params[:key])
        { content_length: object[:body].bytesize, metadata: object[:metadata] }
      })
    end
  end
  let(:day) { Date.new(2026, 10, 29) }
  let(:noon) { Time.utc(2026, 10, 29, 12) }

  before { described_class.client = s3 }
  after { described_class.client = nil }

  def trace(source, at, **attrs)
    Trace.create!(endpoint: "GET /stocks/symbol/marketdata", status: 200, duration: 5.0, source: source,
                  created_at: at, updated_at: at, **attrs)
  end

  def sample(at)
    IngesterSample.create!(at: at, boot_id: SecureRandom.uuid, kind: 'tick', state: 'streaming', frames: 3)
  end

  def rows(table)
    gz = Zlib::GzipReader.new(StringIO.new(objects.fetch(described_class.key(table, day))[:body]))
    gz.each_line.map { |line| JSON.parse(line) }
  end

  it("writes one UTC day of every trace but load traces, and of ingester samples, as gzipped JSON lines") do
    canary = trace('canary', noon, spans: [{ name: 'GET /stocks/symbol/marketdata', category: 'app' }])
    user = trace('user', Time.utc(2026, 10, 29, 0, 0, 0))
    unknown = trace('unknown', Time.utc(2026, 10, 29, 23, 59, 59))
    trace('load', noon)
    trace('canary', Time.utc(2026, 10, 30))
    trace('canary', Time.utc(2026, 10, 28, 23, 59, 59))
    kept = sample(noon)
    sample(Time.utc(2026, 10, 30))

    counts = described_class.export_day(day)

    expect(counts).to(eq('traces' => 3, 'ingester_samples' => 1))
    expect(rows('traces').map { |r| r['id'] }).to(contain_exactly(canary.id, user.id, unknown.id))
    expect(rows('traces').find { |r| r['id'] == canary.id }['spans']).to(eq([{ 'name' => 'GET /stocks/symbol/marketdata', 'category' => 'app' }]))
    expect(rows('ingester_samples').map { |r| r['id'] }).to(eq([kept.id]))
    expect(objects.dig('traces/2026-10-29.jsonl.gz', :metadata)).to(eq('rows' => '3'))
  end

  it("pages through more rows than one batch, keeping rows that share a timestamp") do
    stub_const("#{described_class}::BATCH", 2)
    ids = Array.new(5) { trace('canary', noon).id }

    described_class.export_day(day)

    expect(rows('traces').map { |r| r['id'] }).to(eq(ids))
  end

  it("writes an empty object for a day with no rows") do
    expect(described_class.export_day(day)).to(eq('traces' => 0, 'ingester_samples' => 0))
    expect(rows('traces')).to(eq([]))
  end

  it("fails when S3 doesn't hold what was written") do
    trace('canary', noon)
    s3.stub_responses(:head_object, { content_length: 1, metadata: { 'rows' => '1' } })

    expect { described_class.export_day(day) }.to(raise_error(described_class::UploadMismatch))
  end

  it("scopes deletes to the rows it exported") do
    exported = trace('canary', noon)
    load = trace('load', noon)
    later = trace('user', Time.utc(2026, 10, 30, 0, 0, 1))

    expect(described_class.traces_scope(day)).to(contain_exactly(exported))
    expect(described_class.traces_scope(day)).not_to(include(load, later))
  end

  it("finds the oldest day still holding rows the prune would delete, ignoring load traces") do
    trace('load', Time.utc(2026, 9, 1))
    trace('canary', Time.utc(2026, 10, 29, 8))
    sample(Time.utc(2026, 10, 28, 23))

    expect(described_class.oldest_day).to(eq(Date.new(2026, 10, 28)))
  end
end
