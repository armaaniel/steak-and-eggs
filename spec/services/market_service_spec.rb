require 'rails_helper'

RSpec.describe(MarketService) do
  let(:user) { create(:user) }

  before do
    allow(RedisService).to(receive(:safe_get).with("price:TSLA").and_return("100"))
    allow(RedisService).to(receive(:safe_del))
  end

  describe("buy") do
    it("creates a position and deducts balance") do
      result = MarketService.buy(symbol: "TSLA", quantity: 10, user_id: user.id, name: "Tesla, Inc.")

      expect(user.reload.balance).to(eq(9000))

      position = Position.find_by(user_id: user.id, symbol: "TSLA")
      expect(position.shares).to(eq(10))
      expect(position.average_price).to(eq(100))

      transaction = Transaction.find_by(symbol: "TSLA", user_id: user.id)
      expect(transaction.quantity).to(eq(10))
      expect(transaction.value).to(eq(1000))
      expect(transaction.market_price).to(eq(100))
      expect(transaction.transaction_type).to(eq("Buy"))

      expect(result[:symbol]).to(eq("TSLA"))
      expect(result[:quantity]).to(eq(10))
      expect(result[:value]).to(eq(1000))
      expect(result[:market_price]).to(eq(100))
    end

    it("averages into an existing position") do
      Position.create!(user_id: user.id, symbol: "TSLA", shares: 10, average_price: 80, name: "Tesla, Inc.")

      result = MarketService.buy(symbol: "TSLA", quantity: 10, user_id: user.id, name: "Tesla, Inc.")

      position = Position.find_by(user_id: user.id, symbol: "TSLA")
      expect(position.shares).to(eq(20))
      expect(position.average_price).to(eq(90))

      expect(user.reload.balance).to(eq(9000))
      expect(result[:quantity]).to(eq(10))
      expect(result[:value]).to(eq(1000))
    end

    it("raises InsufficientFundsError when balance is too low") do
      user.update!(balance: 500)

      expect {
        MarketService.buy(symbol: "TSLA", quantity: 10, user_id: user.id, name: "Tesla, Inc.")
      }.to(raise_error(MarketService::InsufficientFundsError))

      expect(user.reload.balance).to(eq(500))
      expect(Position.find_by(user_id: user.id, symbol: "TSLA")).to(be_nil)
      expect(Transaction.find_by(user_id: user.id, symbol: "TSLA")).to(be_nil)
    end

    it("raises when stock price is zero") do
      allow(RedisService).to(receive(:safe_get).with("price:TSLA").and_return("0"))

      expect {
        MarketService.buy(symbol: "TSLA", quantity: 10, user_id: user.id, name: "Tesla, Inc.")
      }.to(raise_error(StandardError))
    end

    it("raises when stock price is nil") do
      allow(RedisService).to(receive(:safe_get).with("price:TSLA").and_return(nil))

      expect {
        MarketService.buy(symbol: "TSLA", quantity: 10, user_id: user.id, name: "Tesla, Inc.")
      }.to(raise_error(StandardError))
    end

    it("invalidates the correct redis cache keys") do
      expect(RedisService).to(receive(:safe_del).with("positions:#{user.id}"))
      expect(RedisService).to(receive(:safe_del).with("activity:#{user.id}"))

      MarketService.buy(symbol: "TSLA", quantity: 10, user_id: user.id, name: "Tesla, Inc.")
    end
  end
  
  describe("sell") do
    let!(:position) { Position.create!(user_id: user.id, symbol: "TSLA", shares: 20, average_price: 80, name: "Tesla, Inc.") }

    it("sells partial shares and credits balance") do
      result = MarketService.sell(symbol: "TSLA", quantity: 10, user_id: user.id)

      expect(user.reload.balance).to(eq(11000))

      position.reload
      expect(position.shares).to(eq(10))
      expect(position.average_price).to(eq(80))

      transaction = Transaction.find_by(symbol: "TSLA", user_id: user.id)
      expect(transaction.quantity).to(eq(10))
      expect(transaction.value).to(eq(1000))
      expect(transaction.market_price).to(eq(100))
      expect(transaction.transaction_type).to(eq("Sell"))
      expect(transaction.realized_pnl).to(eq(200))

      expect(result[:symbol]).to(eq("TSLA"))
      expect(result[:quantity]).to(eq(10))
      expect(result[:value]).to(eq(1000))
      expect(result[:realized_pnl]).to(eq(200))
      expect(result[:market_price]).to(eq(100))
    end

    it("destroys position when selling all shares") do
      MarketService.sell(symbol: "TSLA", quantity: 20, user_id: user.id)

      expect(user.reload.balance).to(eq(12000))
      expect(Position.find_by(user_id: user.id, symbol: "TSLA")).to(be_nil)
    end

    it("calculates negative realized pnl when selling at a loss") do
      allow(RedisService).to(receive(:safe_get).with("price:TSLA").and_return("60"))

      result = MarketService.sell(symbol: "TSLA", quantity: 10, user_id: user.id)

      expect(result[:realized_pnl]).to(eq(-200))
    end

    it("raises InsufficientSharesError when selling more than owned") do
      expect {
        MarketService.sell(symbol: "TSLA", quantity: 25, user_id: user.id)
      }.to(raise_error(MarketService::InsufficientSharesError))

      expect(user.reload.balance).to(eq(10000))
      expect(position.reload.shares).to(eq(20))
      expect(Transaction.find_by(user_id: user.id, symbol: "TSLA")).to(be_nil)
    end

    it("raises InsufficientSharesError when no position exists") do
      allow(RedisService).to(receive(:safe_get).with("price:AAPL").and_return("100"))

      expect {
        MarketService.sell(symbol: "AAPL", quantity: 5, user_id: user.id)
      }.to(raise_error(MarketService::InsufficientSharesError))
    end

    it("raises when stock price is zero") do
      allow(RedisService).to(receive(:safe_get).with("price:TSLA").and_return("0"))

      expect {
        MarketService.sell(symbol: "TSLA", quantity: 10, user_id: user.id)
      }.to(raise_error(StandardError))
    end

    it("raises when stock price is nil") do
      allow(RedisService).to(receive(:safe_get).with("price:TSLA").and_return(nil))

      expect {
        MarketService.sell(symbol: "TSLA", quantity: 10, user_id: user.id)
      }.to(raise_error(StandardError))
    end

    it("invalidates the correct redis cache keys") do
      expect(RedisService).to(receive(:safe_del).with("positions:#{user.id}"))
      expect(RedisService).to(receive(:safe_del).with("activity:#{user.id}"))

      MarketService.sell(symbol: "TSLA", quantity: 10, user_id: user.id)
    end
  end
  
  describe("marketprice") do
    it("returns price and open from cache") do
      allow(RedisService).to(receive(:safe_get).with("price:TSLA").and_return("100"))
      allow(RedisService).to(receive(:safe_get).with("open:TSLA").and_return("95"))

      result = MarketService.marketprice(symbol: "TSLA")

      expect(result[:price]).to(eq("100"))
      expect(result[:open]).to(eq("95"))
    end

    it("raises ApiError when price is not cached") do
      allow(RedisService).to(receive(:safe_get).with("price:TSLA").and_return(nil))
      allow(RedisService).to(receive(:safe_get).with("open:TSLA").and_return(nil))

      expect {
        MarketService.marketprice(symbol: "TSLA")
      }.to(raise_error(MarketService::ApiError))
    end
  end

  describe("marketdata") do
    let(:api_response_body) do
      { "results" => [{ "session" => { "open" => 95, "high" => 110, "low" => 90, "volume" => 50000 } }] }.to_json
    end

    it("returns cached data on cache hit") do
      cached = { open: 95, high: 110, low: 90, volume: 50000 }.to_json
      allow(RedisService).to(receive(:safe_get).with("market:TSLA").and_return(cached))

      result = MarketService.marketdata(symbol: "TSLA")

      expect(result).to(eq(cached))
    end

    it("fetches from API on cache miss and caches result") do
      allow(RedisService).to(receive(:safe_get).with("market:TSLA").and_return(nil))
      allow(RedisService).to(receive(:safe_setex))

      response = instance_double(Net::HTTPResponse, code: "200", body: api_response_body)
      allow(Net::HTTP).to(receive(:get_response).and_return(response))

      result = MarketService.marketdata(symbol: "TSLA")

      expect(result).to(eq({ open: 95, high: 110, low: 90, volume: 50000 }))
      expect(RedisService).to(have_received(:safe_setex).with("market:TSLA", 300, anything))
    end

    it("raises ApiError on non-200 response") do
      allow(RedisService).to(receive(:safe_get).with("market:TSLA").and_return(nil))

      response = instance_double(Net::HTTPResponse, code: "500")
      allow(Net::HTTP).to(receive(:get_response).and_return(response))

      expect {
        MarketService.marketdata(symbol: "TSLA")
      }.to(raise_error(MarketService::ApiError))
    end
  end

  describe("companydata") do
    let(:api_response_body) do
      { "results" => { "market_cap" => 800000000000, "description" => "Electric vehicles" } }.to_json
    end

    it("returns cached data on cache hit") do
      cached = { market_cap: 800000000000, description: "Electric vehicles" }.to_json
      allow(RedisService).to(receive(:safe_get).with("company:TSLA").and_return(cached))

      result = MarketService.companydata(symbol: "TSLA")

      expect(result).to(eq(cached))
    end

    it("fetches from API on cache miss and caches result") do
      allow(RedisService).to(receive(:safe_get).with("company:TSLA").and_return(nil))
      allow(RedisService).to(receive(:safe_setex))

      response = instance_double(Net::HTTPResponse, code: "200", body: api_response_body)
      allow(Net::HTTP).to(receive(:get_response).and_return(response))

      result = MarketService.companydata(symbol: "TSLA")

      expect(result).to(eq({ market_cap: 800000000000, description: "Electric vehicles" }))
      expect(RedisService).to(have_received(:safe_setex).with("company:TSLA", 3.days.to_i, anything))
    end

    it("raises ApiError on non-200 response") do
      allow(RedisService).to(receive(:safe_get).with("company:TSLA").and_return(nil))

      response = instance_double(Net::HTTPResponse, code: "500")
      allow(Net::HTTP).to(receive(:get_response).and_return(response))

      expect {
        MarketService.companydata(symbol: "TSLA")
      }.to(raise_error(MarketService::ApiError))
    end
  end

  describe("chartdata") do
    let(:api_response_body) do
      { "results" => [
        { "t" => 1700000000000, "c" => 200 },
        { "t" => 1700086400000, "c" => 205 }
      ] }.to_json
    end

    it("returns cached data on cache hit") do
      cached = [{ date: "2023-11-14", value: 200 }].to_json
      allow(RedisService).to(receive(:safe_get).with("daily:TSLA").and_return(cached))

      result = MarketService.chartdata(symbol: "TSLA")

      expect(result).to(eq(cached))
    end

    it("fetches from API on cache miss and caches result") do
      allow(RedisService).to(receive(:safe_get).with("daily:TSLA").and_return(nil))
      allow(RedisService).to(receive(:safe_setex))

      response = instance_double(Net::HTTPResponse, code: "200", body: api_response_body)
      allow(Net::HTTP).to(receive(:get_response).and_return(response))

      result = MarketService.chartdata(symbol: "TSLA")

      expect(result.length).to(eq(2))
      expect(result[0][:value]).to(eq(200))
      expect(result[1][:value]).to(eq(205))
      expect(RedisService).to(have_received(:safe_setex).with("daily:TSLA", 24.hours.to_i, anything))
    end

    it("raises ApiError on non-200 response") do
      allow(RedisService).to(receive(:safe_get).with("daily:TSLA").and_return(nil))

      response = instance_double(Net::HTTPResponse, code: "500")
      allow(Net::HTTP).to(receive(:get_response).and_return(response))

      expect {
        MarketService.chartdata(symbol: "TSLA")
      }.to(raise_error(MarketService::ApiError))
    end
  end
  
end