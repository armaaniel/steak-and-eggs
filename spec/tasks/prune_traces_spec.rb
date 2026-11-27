require 'rails_helper'
require 'rake'

RSpec.describe("prune_traces") do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("prune_traces") }

  let(:objects) { {} }
  let(:s3) { fake_s3(objects) }
  let(:now) { Time.now.utc }
  let(:old_day) { (now - 33.days).to_date }
  let(:yesterday) { now.to_date - 1 }
  let(:day) { Date.new(2026, 10, 29) }
  let(:noon) { Time.utc(2026, 10, 29, 12) }

  before { allow(Aws::S3::Client).to(receive(:new).and_return(s3)) }

  def run(name = "prune_traces")
    task = Rake::Task[name]
    task.reenable
    task.invoke
  end

  def backfill(from, to)
    stub_const('ENV', ENV.to_h.merge('FROM' => from.iso8601, 'TO' => to.iso8601))
    expect { run("archive:backfill") }.to(output.to_stdout)
  end

  def trace(source, at, **attrs)
    Trace.create!(endpoint: "GET /stocks/AAPL/marketdata", status: 200, duration: 5.0, source: source,
                  created_at: at, updated_at: at, **attrs)
  end

  def sample(at)
    IngesterSample.create!(at: at, boot_id: SecureRandom.uuid, kind: 'tick', state: 'streaming', frames: 3)
  end

  def rows(table, on = day)
    gz = Zlib::GzipReader.new(StringIO.new(objects.fetch("#{table}/#{on.iso8601}.jsonl.gz")[:body]))
    gz.each_line.map { |line| JSON.parse(line) }
  end

  def noon_on(on)
    Time.utc(on.year, on.month, on.day, 12)
  end

  describe("the export") do
    it("writes one UTC day of every trace but load traces, and of ingester samples, as gzipped JSON lines") do
      canary = trace('canary', noon, spans: [{ name: 'StocksController#marketdata', category: 'app' }])
      user = trace('user', Time.utc(2026, 10, 29, 0, 0, 0))
      unknown = trace('unknown', Time.utc(2026, 10, 29, 23, 59, 59))
      trace('load', noon)
      trace('canary', Time.utc(2026, 10, 30))
      trace('canary', Time.utc(2026, 10, 28, 23, 59, 59))
      kept = sample(noon)
      sample(Time.utc(2026, 10, 30))

      backfill(day, day)

      expect(rows('traces').map { |r| r['id'] }).to(contain_exactly(canary.id, user.id, unknown.id))
      expect(rows('traces').find { |r| r['id'] == canary.id }['spans']).to(eq([{ 'name' => 'StocksController#marketdata', 'category' => 'app' }]))
      expect(rows('ingester_samples').map { |r| r['id'] }).to(eq([kept.id]))
      expect(objects.dig('traces/2026-10-29.jsonl.gz', :metadata)).to(eq('rows' => '3'))
    end

    it("pages through more rows than one batch, keeping rows that share a timestamp") do
      stub_const('ARCHIVE_BATCH', 2)
      ids = Array.new(5) { trace('canary', noon).id }

      backfill(day, day)

      expect(rows('traces').map { |r| r['id'] }).to(eq(ids))
    end

    it("writes an empty object for a day with no rows") do
      backfill(day, day)

      expect(rows('traces')).to(eq([]))
      expect(rows('ingester_samples')).to(eq([]))
    end

    it("fails when S3 doesn't hold what was written") do
      trace('canary', noon)
      s3.stub_responses(:head_object, { content_length: 1, metadata: { 'rows' => '1' } })
      stub_const('ENV', ENV.to_h.merge('FROM' => day.iso8601, 'TO' => day.iso8601))

      expect { run("archive:backfill") }.to(raise_error(RuntimeError, /S3 has 1/))
    end

    it("starts the backfill at the oldest day holding rows the prune would delete, ignoring load traces") do
      trace('load', Time.utc(2026, 9, 1))
      trace('canary', Time.utc(2026, 10, 29, 8))
      sample(Time.utc(2026, 10, 28, 23))
      stub_const('ENV', ENV.to_h.merge('TO' => day.iso8601))

      expect { run("archive:backfill") }.to(output(/\A2026-10-28 traces 0, ingester_samples 1\n2026-10-29 traces 1, ingester_samples 0\n\z/).to_stdout)
    end
  end

  describe("the prune") do
    it("archives each day older than 31 days before deleting it, keeps newer days and load traces, and archives yesterday") do
      old = trace('canary', noon_on(old_day))
      old_sample = sample(noon_on(old_day))
      load = trace('load', noon_on(old_day))
      recent = trace('user', now - 5.days)
      recent_sample = sample(now - 5.days)

      run

      expect(objects.keys).to(include("traces/#{old_day.iso8601}.jsonl.gz", "ingester_samples/#{old_day.iso8601}.jsonl.gz",
                                      "traces/#{yesterday.iso8601}.jsonl.gz"))
      expect(rows('traces', old_day).map { |r| r['id'] }).to(eq([old.id]))
      expect(Trace.where(id: old.id)).to(be_empty)
      expect(IngesterSample.where(id: old_sample.id)).to(be_empty)
      expect(Trace.where(id: [load.id, recent.id]).count).to(eq(2))
      expect(IngesterSample.where(id: recent_sample.id)).to(exist)
      expect(JobRun.last).to(have_attributes(name: "prune_traces", status: "succeeded"))
    end

    it("keeps the whole day that's 31 days old, so the 30d charts keep their oldest day") do
      edge_day = (now - 31.days).to_date
      edge = trace('canary', Time.utc(edge_day.year, edge_day.month, edge_day.day))

      run

      expect(Trace.where(id: edge.id)).to(exist)
    end

    it("deletes nothing and fails the run when the upload fails") do
      old = trace('canary', noon_on(old_day))
      s3.stub_responses(:put_object, 'ServiceUnavailable')

      expect { run }.to(raise_error(Aws::S3::Errors::ServiceUnavailable))

      expect(Trace.where(id: old.id)).to(exist)
      expect(JobRun.last).to(have_attributes(name: "prune_traces", status: "failed"))
    end
  end
end
