require 'rails_helper'

RSpec.describe(IngesterSample) do
  let(:boot_id) { SecureRandom.uuid }
  let(:connection_id) { SecureRandom.uuid }
  let(:noon) { Time.utc(2026, 9, 30, 12, 0) }

  def tick(at:, state: 'streaming', connection: connection_id, **counters)
    IngesterSample.create!(at: at, boot_id: boot_id, connection_id: connection, kind: 'tick', state: state, **counters)
  end

  describe(".spans") do
    def spans(from:, to:)
      IngesterSample.spans(from: from, to: to).map { |span| [span['state'], span['seconds'].to_f] }
    end

    it("merges back to back samples in the same state into one span") do
      tick(at: noon)
      tick(at: noon + 1.minute)
      tick(at: noon + 2.minutes)
      tick(at: noon + 3.minutes, state: 'reconnecting')
      tick(at: noon + 4.minutes)

      expect(spans(from: noon, to: noon + 5.minutes)).to(eq([['streaming', 180.0], ['reconnecting', 60.0], ['streaming', 60.0]]))
    end

    it("starts a new span when the connection changes, even in the same state") do
      tick(at: noon)
      tick(at: noon + 1.minute, connection: SecureRandom.uuid)

      expect(spans(from: noon, to: noon + 2.minutes)).to(eq([['streaming', 60.0], ['streaming', 60.0]]))
    end

    it("keeps a down span for a gap between samples") do
      tick(at: noon)
      tick(at: noon + 5.minutes)

      expect(spans(from: noon, to: noon + 6.minutes)).to(eq([['streaming', 90.0], ['down', 210.0], ['streaming', 60.0]]))
    end
  end

  describe(".rate") do
    it("keeps one point per sample on a short window") do
      tick(at: noon, events: 0)
      tick(at: noon + 1.minute, events: 600)
      tick(at: noon + 2.minutes, events: 1200)

      rate = IngesterSample.rate(from: noon, to: noon + 1.hour)

      expect(rate.map { |point| point['events_per_sec'].to_f }).to(eq([10.0, 10.0]))
    end

    it("averages a long window into buckets by total events over total seconds") do
      bucket_start = Time.at(840 * 2_100_000).utc
      tick(at: bucket_start, events: 0)
      tick(at: bucket_start + 1.minute, events: 600)
      tick(at: bucket_start + 2.minutes, events: 600)

      to = bucket_start + 1.hour
      rate = IngesterSample.rate(from: to - 7.days, to: to)

      expect(rate.length).to(eq(1))
      expect(rate.first['at']).to(eq(bucket_start))
      expect(rate.first['events_per_sec'].to_f).to(eq(5.0))
    end
  end

  describe(".lag") do
    it("weights each tick's lag by its sampled events within a bucket") do
      bucket_start = Time.at(840 * 2_100_000).utc
      tick(at: bucket_start, sampled_events: 1, sum_lag_ms: IngesterSample::BASE_LAG_MS + 100, symbols: 3)
      tick(at: bucket_start + 1.minute, sampled_events: 9, sum_lag_ms: 9 * (IngesterSample::BASE_LAG_MS + 10), symbols: 5)

      to = bucket_start + 1.hour
      lag = IngesterSample.lag(from: to - 7.days, to: to)

      expect(lag.length).to(eq(1))
      expect(lag.first['mean_excess_ms']).to(eq(19.0))
      expect(lag.first['sampled_events']).to(eq(10))
      expect(lag.first['symbols']).to(eq(5))
    end
  end
end
