require 'rails_helper'

RSpec.describe('Samples', type: :request) do
  let(:run_id) { SecureRandom.uuid }
  let(:headers) { { 'Synthetic-Key' => 'test-key', 'CONTENT_TYPE' => 'application/json' } }
  let(:at) { 1_791_838_800_000 }

  before do
    allow(ENV).to(receive(:[]).and_call_original)
    allow(ENV).to(receive(:[]).with('SYNTHETIC_KEY').and_return('test-key'))
  end

  def post_metrics(samples, request_headers = headers)
    post('/run_metrics', params: { run_id: run_id, samples: samples }.to_json, headers: request_headers)
  end

  describe('POST /run_metrics') do
    it('stores each sample as a one second run metric') do
      post_metrics([{ metric: 'cpu_used', at: at, value: 182.5 }])

      expect(response).to(have_http_status(201))
      metric = RunMetric.find_by(run_id: run_id, metric: 'cpu_used')
      expect([metric.at, metric.minimum, metric.maximum, metric.average]).to(eq([Time.at(at / 1000).utc, 182.5, 182.5, 182.5]))
    end

    it('overwrites a second that is imported twice') do
      post_metrics([{ metric: 'cpu_pressure', at: at, value: 40 }])
      post_metrics([{ metric: 'cpu_pressure', at: at, value: 900 }])

      expect(RunMetric.where(run_id: run_id, metric: 'cpu_pressure').pluck(:average)).to(eq([900.0]))
    end

    it('rejects a batch with a metric that is not sampled per second') do
      post_metrics([{ metric: 'cpu_used', at: at, value: 1 }, { metric: 'cpu', at: at, value: 1 }])

      expect(response).to(have_http_status(422))
      expect(RunMetric.where(run_id: run_id).count).to(eq(0))
    end

    it('rejects requests without the synthetic key') do
      post_metrics([{ metric: 'cpu_used', at: at, value: 1 }], { 'CONTENT_TYPE' => 'application/json' })

      expect(response).to(have_http_status(403))
    end
  end
end
