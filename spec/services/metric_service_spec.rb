require 'rails_helper'

RSpec.describe(MetricService) do
  describe('.for_run with a per second metric') do
    let(:run_id) { SecureRandom.uuid }
    let(:start) { Time.utc(2026, 10, 12, 21, 0, 0) }

    before do
      rows = [[0, 100.0], [1, 200.0], [5, 50.0], [6, 70.0]].map do |offset, value|
        { run_id: run_id, metric: 'cpu_used', at: start + offset, minimum: value, maximum: value, average: value }
      end

      RunMetric.insert_all(rows)
    end

    it('returns every second when no step is given') do
      metrics = MetricService.for_run(run_id: run_id, kind: 'load', metric: 'cpu_used')

      expect(metrics.map(&:average)).to(eq([100.0, 200.0, 50.0, 70.0]))
    end

    it('averages the seconds in each step and keeps their range') do
      buckets = MetricService.for_run(run_id: run_id, kind: 'load', metric: 'cpu_used', step: 5)

      expect(buckets.map { |bucket| [bucket.at, bucket.minimum, bucket.maximum, bucket.average] }).to(eq([[start, 100.0, 200.0, 150.0], [start + 5, 50.0, 70.0, 60.0]]))
    end

    it('reads only saved rows and never asks cloudwatch') do
      expect(Aws::CloudWatch::Client).not_to(receive(:new))

      MetricService.for_run(run_id: run_id, kind: 'load', metric: 'cpu_used', step: 5).to_a
    end

    it('returns nothing for an unknown kind') do
      expect(MetricService.for_run(run_id: run_id, kind: 'nope', metric: 'cpu_used')).to(eq([]))
    end
  end
end
