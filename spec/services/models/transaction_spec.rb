require 'rails_helper'

RSpec.describe(Transaction) do
  let(:user) { create(:user) }

  describe("get") do
    it("returns cached data on cache hit") do
      cached = [{ id: 1, symbol: "TSLA", value: 1000 }].to_json
      allow(RedisService).to(receive(:safe_get).with("activity:#{user.id}").and_return(cached))

      result = Transaction.get(user_id: user.id)

      expect(result).to(eq(cached))
    end

    it("queries db and caches on cache miss") do
      allow(RedisService).to(receive(:safe_get).with("activity:#{user.id}").and_return(nil))
      allow(RedisService).to(receive(:safe_setex))

      Transaction.create!(user_id: user.id, symbol: "TSLA", quantity: 10, value: 1000,
        transaction_type: "Buy", market_price: 100)
      Transaction.create!(user_id: user.id, symbol: "USD", quantity: 1, value: 500,
        transaction_type: "Deposit", market_price: 1)

      result = Transaction.get(user_id: user.id)

      expect(result.length).to(eq(2))
      expect(RedisService).to(have_received(:safe_setex).with("activity:#{user.id}", 6.hours.to_i, anything))
    end

    it("returns transactions in descending order") do
      allow(RedisService).to(receive(:safe_get).with("activity:#{user.id}").and_return(nil))
      allow(RedisService).to(receive(:safe_setex))

      old = Transaction.create!(user_id: user.id, symbol: "TSLA", quantity: 5, value: 500,
        transaction_type: "Buy", market_price: 100, created_at: 2.days.ago)
      recent = Transaction.create!(user_id: user.id, symbol: "AAPL", quantity: 10, value: 1500,
        transaction_type: "Buy", market_price: 150, created_at: 1.hour.ago)

      result = Transaction.get(user_id: user.id)

      expect(result[0][:symbol]).to(eq("AAPL"))
      expect(result[1][:symbol]).to(eq("TSLA"))
    end
  end
end