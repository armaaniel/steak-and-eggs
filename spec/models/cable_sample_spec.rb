require 'rails_helper'

RSpec.describe(CableSample) do
  let(:run_id) { SecureRandom.uuid }
  let(:noon) { Time.utc(2026, 10, 12, 12, 0) }

  before do
    allow(RedisService).to(receive(:safe_get).and_return(nil))
    allow(RedisService).to(receive(:safe_set))
  end

  def publish(at:, frames:)
    CableSample.create!(run_id: run_id, at: at, source: 'publisher', frames: frames)
  end

  def receive_frames(at:, vu:, frames:, lags:)
    CableSample.create!(run_id: run_id, at: at, source: 'client', vu: vu, frames: frames, lags: lags)
  end

  describe(".compare") do
    before do
      [0, 5, 10].each_with_index do |offset, index|
        at = noon + offset.seconds
        publish(at: at, frames: 10)
        receive_frames(at: at, vu: 1, frames: 10, lags: [index + 1])
        receive_frames(at: at, vu: 2, frames: 9, lags: [index + 10])
      end
    end

    it("keeps one row per five second sample at a five second step") do
      rows = CableSample.compare(run_id: run_id, step: 5)

      expect(rows.map { |row| row['at'] }).to(eq([noon, noon + 5.seconds, noon + 10.seconds]))
      expect(rows.map { |row| row['received'] }).to(eq([19, 19, 19]))
    end

    it("folds the samples into wider buckets and takes the lag percentiles across them") do
      rows = CableSample.compare(run_id: run_id, step: 15)

      expect(rows.size).to(eq(1))
      expect(rows.first).to(include('at' => noon, 'published' => 30, 'received' => 57, 'clients' => 2, 'expected' => 60, 'p50_lag_ms' => 3, 'p99_lag_ms' => 12))
    end

    it("caches each step under its own key") do
      CableSample.compare(run_id: run_id, step: 15)

      expect(RedisService).to(have_received(:safe_set).with("cable_compare:v1:#{run_id}:15", anything))
    end
  end
end
