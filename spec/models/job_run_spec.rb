require 'rails_helper'
require 'rake'

RSpec.describe(JobRun) do
  include ActiveSupport::Testing::TimeHelpers

  after { travel_back }

  describe(".track") do
    it("records when a run started and when it finished") do
      travel_to(Time.utc(2026, 11, 3, 5, 0, 30))

      JobRun.track('record') { travel(40.seconds) }

      expect(JobRun.last).to(have_attributes(name: 'record', started_at: Time.utc(2026, 11, 3, 5, 0, 30), finished_at: Time.utc(2026, 11, 3, 5, 1, 10), error_class: nil))
      expect(JobRun.last.status).to(eq('succeeded'))
    end

    it("records the error and its sentry event, then raises it again") do
      allow(Sentry).to(receive(:capture_exception).and_return(double(event_id: 'abc123')))

      expect { JobRun.track('prune_traces') { raise(ArgumentError, 'boom') } }.to(raise_error(ArgumentError, 'boom'))

      expect(JobRun.last).to(have_attributes(error_class: 'ArgumentError', sentry_event_id: 'abc123'))
      expect(JobRun.last.finished_at).to(be_present)
      expect(JobRun.last.status).to(eq('failed'))
    end
  end

  describe("#status") do
    it("is running until an hour passes without a finish, then failed") do
      run = JobRun.create!(name: 'record', started_at: Time.current)

      expect(run.status).to(eq('running'))

      travel(61.minutes)

      expect(run.status).to(eq('failed'))
    end
  end

  describe(".buckets") do
    before { travel_to(Time.utc(2026, 11, 10, 5, 30)) }

    def day(name, date)
      JobRun.buckets.find { |bucket| bucket[:name] == name && bucket[:bucket] == date }
    end

    it("returns 30 days for every scheduled job, and expects nothing before the first run is tracked") do
      buckets = JobRun.buckets

      expect(buckets.length).to(eq(90))
      expect(buckets.map { |bucket| bucket[:expected] }.uniq).to(eq([0]))
    end

    it("expects one run a day from the day tracking began, once the scheduled hour plus an hour has passed") do
      JobRun.create!(name: 'tickers:sync', started_at: Time.utc(2026, 11, 8, 4, 1), finished_at: Time.utc(2026, 11, 8, 4, 1, 20))

      expect(day('record', Time.utc(2026, 11, 7))).to(include(expected: 0))
      expect(day('tickers:sync', Time.utc(2026, 11, 8))).to(include(expected: 1, started: 1, completed: 1, failures: 0))
      expect(day('record', Time.utc(2026, 11, 9))).to(include(expected: 1, started: 0))
      expect(day('tickers:sync', Time.utc(2026, 11, 10))).to(include(expected: 1, started: 0))
      expect(day('record', Time.utc(2026, 11, 10))).to(include(expected: 0))
    end

    it("counts a run that raised, or never finished within an hour, as a failure, and one still inside the hour as neither") do
      JobRun.create!(name: 'record', started_at: Time.utc(2026, 11, 9, 5, 1), finished_at: Time.utc(2026, 11, 9, 5, 1, 5), error_class: 'PG::ConnectionBad')
      JobRun.create!(name: 'prune_traces', started_at: Time.utc(2026, 11, 9, 6, 1))
      JobRun.create!(name: 'tickers:sync', started_at: Time.utc(2026, 11, 10, 5, 0))

      expect(day('record', Time.utc(2026, 11, 9))).to(include(started: 1, completed: 0, failures: 1))
      expect(day('prune_traces', Time.utc(2026, 11, 9))).to(include(started: 1, completed: 0, failures: 1))
      expect(day('tickers:sync', Time.utc(2026, 11, 10))).to(include(started: 1, completed: 0, failures: 0))
    end
  end

  describe("scheduled rake tasks") do
    before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("prune_traces") }

    it("has a rake task for every scheduled job") do
      JobRun::SCHEDULE.each_key { |name| expect(Rake::Task.task_defined?(name)).to(be(true)) }
    end

    it("records a run when prune_traces runs") do
      task = Rake::Task["prune_traces"]
      task.reenable
      task.invoke

      expect(JobRun.last).to(have_attributes(name: 'prune_traces', error_class: nil))
      expect(JobRun.last.status).to(eq('succeeded'))
    end
  end
end
