require 'rails_helper'

RSpec.describe(PositionService) do
  let(:user) { create(:user) }

  describe("find_position") do
    it("returns position data when position exists") do
      Position.create!(user_id: user.id, symbol: "TSLA", shares: 10, average_price: 100, name: "Tesla, Inc.")

      result = PositionService.find_position(symbol: "TSLA", user_id: user.id)

      expect(result[:symbol]).to(eq("TSLA"))
      expect(result[:shares]).to(eq(10))
      expect(result[:average_price]).to(eq(100))
    end

    it("returns nil when position does not exist") do
      result = PositionService.find_position(symbol: "TSLA", user_id: user.id)

      expect(result).to(be_nil)
    end
  end

  describe("get_aum") do
    it("returns just balance when no positions exist") do
      allow(RedisService).to(receive(:safe_get).with("positions:#{user.id}").and_return(nil))
      allow(RedisService).to(receive(:safe_setex))

      result = PositionService.get_aum(user_id: user.id, balance: 10000)

      expect(result[:aum]).to(eq(10000))
      expect(result[:balance]).to(eq(10000))
    end

    it("calculates aum across multiple positions") do
      positions = [
        { symbol: "TSLA", shares: 10, name: "Tesla, Inc.", average_price: 80 },
        { symbol: "AAPL", shares: 5, name: "Apple Inc.", average_price: 150 }
      ]
      allow(RedisService).to(receive(:safe_get).with("positions:#{user.id}").and_return(positions.to_json))
      allow(RedisService).to(receive(:safe_mget).with("open:TSLA", "open:AAPL").and_return(["95", "148"]))
      allow(RedisService).to(receive(:safe_mget).with("price:TSLA", "price:AAPL").and_return(["100", "155"]))

      result = PositionService.get_aum(user_id: user.id, balance: 5000)

      # 5000 + (10 * 100) + (5 * 155) = 5000 + 1000 + 775 = 6775
      expect(result[:aum]).to(eq(6775))
      expect(result[:balance]).to(eq(5000))
      expect(result[:positions].length).to(eq(2))
    end

    it("treats nil prices as zero") do
      positions = [{ symbol: "TSLA", shares: 10, name: "Tesla, Inc.", average_price: 80 }]
      allow(RedisService).to(receive(:safe_get).with("positions:#{user.id}").and_return(positions.to_json))
      allow(RedisService).to(receive(:safe_mget).with("open:TSLA").and_return([nil]))
      allow(RedisService).to(receive(:safe_mget).with("price:TSLA").and_return([nil]))

      result = PositionService.get_aum(user_id: user.id, balance: 5000)

      expect(result[:aum]).to(eq(5000))
    end
  end

  describe("portfolio_records") do
    it("returns cached data on cache hit") do
      cached = [{ date: "2024-01-01", value: 10000 }].to_json
      allow(RedisService).to(receive(:safe_get).with("portfolio:#{user.id}").and_return(cached))

      result = PositionService.portfolio_records(user_id: user.id)

      expect(result).to(eq(cached))
    end

    it("queries db and caches on cache miss") do
      allow(RedisService).to(receive(:safe_get).with("portfolio:#{user.id}").and_return(nil))
      allow(RedisService).to(receive(:safe_setex))

      PortfolioRecord.create!(user_id: user.id, date: Date.new(2024, 1, 1), portfolio_value: 10000)
      PortfolioRecord.create!(user_id: user.id, date: Date.new(2024, 1, 2), portfolio_value: 10500)

      result = PositionService.portfolio_records(user_id: user.id)

      expect(result.length).to(eq(2))
      expect(result[0][:value]).to(eq(10000.0))
      expect(result[1][:value]).to(eq(10500.0))
      expect(RedisService).to(have_received(:safe_setex).with("portfolio:#{user.id}", 6.hours.to_i, anything))
    end

    it("pads data when fewer than 2 records exist") do
      allow(RedisService).to(receive(:safe_get).with("portfolio:#{user.id}").and_return(nil))
      allow(RedisService).to(receive(:safe_setex))

      PortfolioRecord.create!(user_id: user.id, date: Date.current, portfolio_value: 8000)

      result = PositionService.portfolio_records(user_id: user.id)

      expect(result.length).to(eq(2))
      expect(result[0][:value]).to(eq(0.0))
      expect(result[1][:value]).to(eq(8000.0))
    end
  end

  describe("find_positions") do
    it("returns cached positions on cache hit") do
      positions = [{ symbol: "TSLA", shares: 10, name: "Tesla, Inc.", average_price: 80 }]
      allow(RedisService).to(receive(:safe_get).with("positions:#{user.id}").and_return(positions.to_json))

      result = PositionService.send(:find_positions, user_id: user.id)

      expect(result.length).to(eq(1))
      expect(result[0][:symbol]).to(eq("TSLA"))
    end

    it("queries db and caches on cache miss") do
      allow(RedisService).to(receive(:safe_get).with("positions:#{user.id}").and_return(nil))
      allow(RedisService).to(receive(:safe_setex))

      Position.create!(user_id: user.id, symbol: "TSLA", shares: 10, average_price: 100, name: "Tesla, Inc.")

      result = PositionService.send(:find_positions, user_id: user.id)

      expect(result.length).to(eq(1))
      expect(result[0][:symbol]).to(eq("TSLA"))
      expect(RedisService).to(have_received(:safe_setex).with("positions:#{user.id}", 24.hours.to_i, anything))
    end

    it("returns empty array on error") do
      allow(RedisService).to(receive(:safe_get).and_raise(StandardError))
      allow(Sentry).to(receive(:capture_exception))

      result = PositionService.send(:find_positions, user_id: user.id)

      expect(result).to(eq([]))
      expect(Sentry).to(have_received(:capture_exception))
    end
  end
end