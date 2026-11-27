require 'rails_helper'
require 'rake'

RSpec.describe("prune_traces") do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("prune_traces") }

  let(:keys) { [] }
  let(:s3) do
    Aws::S3::Client.new(stub_responses: true).tap do |client|
      sizes = {}
      client.stub_responses(:put_object, lambda { |context|
        body = context.params[:body]
        body.rewind
        sizes[context.params[:key]] = [body.read.bytesize, context.params[:metadata]]
        keys << context.params[:key]
        {}
      })
      client.stub_responses(:head_object, lambda { |context|
        size, metadata = sizes.fetch(context.params[:key])
        { content_length: size, metadata: metadata }
      })
    end
  end
  let(:now) { Time.now.utc }
  let(:old_day) { (now - 33.days).to_date }
  let(:yesterday) { now.to_date - 1 }

  before { ArchiveService.client = s3 }
  after { ArchiveService.client = nil }

  def run
    task = Rake::Task["prune_traces"]
    task.reenable
    task.invoke
  end

  def trace(source, at)
    Trace.create!(endpoint: "GET /portfoliodata", status: 200, duration: 5.0, source: source, created_at: at, updated_at: at)
  end

  def sample(at)
    IngesterSample.create!(at: at, boot_id: SecureRandom.uuid, kind: 'tick', state: 'streaming')
  end

  def noon(day)
    Time.utc(day.year, day.month, day.day, 12)
  end

  it("archives each day older than 31 days before deleting it, keeps newer days and load traces, and archives yesterday") do
    old = trace('canary', noon(old_day))
    old_sample = sample(noon(old_day))
    load = trace('load', noon(old_day))
    recent = trace('user', now - 5.days)
    recent_sample = sample(now - 5.days)

    run

    expect(keys).to(include("traces/#{old_day.iso8601}.jsonl.gz", "ingester_samples/#{old_day.iso8601}.jsonl.gz",
                            "traces/#{yesterday.iso8601}.jsonl.gz"))
    expect(Trace.where(id: old.id)).to(be_empty)
    expect(IngesterSample.where(id: old_sample.id)).to(be_empty)
    expect(Trace.where(id: [load.id, recent.id]).count).to(eq(2))
    expect(IngesterSample.where(id: recent_sample.id)).to(exist)
    expect(JobRun.last).to(have_attributes(name: "prune_traces", status: "succeeded"))
  end

  it("keeps the whole day that's 31 days old, so the 30d charts keep their oldest day") do
    edge = trace('canary', Time.utc((now - 31.days).year, (now - 31.days).month, (now - 31.days).day))

    run

    expect(Trace.where(id: edge.id)).to(exist)
  end

  it("deletes nothing and fails the run when the upload fails") do
    old = trace('canary', noon(old_day))
    s3.stub_responses(:put_object, 'ServiceUnavailable')

    expect { run }.to(raise_error(Aws::S3::Errors::ServiceUnavailable))

    expect(Trace.where(id: old.id)).to(exist)
    expect(JobRun.last).to(have_attributes(name: "prune_traces", status: "failed"))
  end
end
