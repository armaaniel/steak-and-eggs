require 'rails_helper'

RSpec.describe(MarketService) do
  let(:user) { create(:user) }

  before do
    allow(RedisService).to(receive(:safe_get).with("price:TSLA").and_return("100"))
    allow(CacheService).to(receive(:invalidate_user))
  end

  describe("buy") do
    it("creates a position and deducts balance") do
      result = MarketService.buy(symbol: "TSLA", quantity: 10, user_id: user.id)

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
      Position.create!(user_id: user.id, symbol: "TSLA", shares: 10, average_price: 80)

      result = MarketService.buy(symbol: "TSLA", quantity: 10, user_id: user.id)

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
        MarketService.buy(symbol: "TSLA", quantity: 10, user_id: user.id)
      }.to(raise_error(MarketService::InsufficientFundsError))

      expect(user.reload.balance).to(eq(500))
      expect(Position.find_by(user_id: user.id, symbol: "TSLA")).to(be_nil)
      expect(Transaction.find_by(user_id: user.id, symbol: "TSLA")).to(be_nil)
    end

    it("raises when stock price is zero") do
      allow(RedisService).to(receive(:safe_get).with("price:TSLA").and_return("0"))

      expect {
        MarketService.buy(symbol: "TSLA", quantity: 10, user_id: user.id)
      }.to(raise_error(StandardError))
    end

    it("raises when stock price is nil") do
      allow(RedisService).to(receive(:safe_get).with("price:TSLA").and_return(nil))

      expect {
        MarketService.buy(symbol: "TSLA", quantity: 10, user_id: user.id)
      }.to(raise_error(StandardError))
    end

    it("invalidates cache") do
      expect(CacheService).to(receive(:invalidate_user).with(user_id: user.id))

      MarketService.buy(symbol: "TSLA", quantity: 10, user_id: user.id)
    end
  end
  
  describe("sell") do
    let!(:position) { Position.create!(user_id: user.id, symbol: "TSLA", shares: 20, average_price: 80) }

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

    it("invalidates cache") do
      expect(CacheService).to(receive(:invalidate_user).with(user_id: user.id))

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
      http = instance_double(Net::HTTP)
      allow(http).to(receive(:use_ssl=))
      allow(http).to(receive(:open_timeout=))
      allow(http).to(receive(:read_timeout=))
      allow(http).to(receive(:request).and_return(response))
      allow(Net::HTTP).to(receive(:new).and_return(http))

      result = MarketService.marketdata(symbol: "TSLA")

      expect(result).to(eq({ open: 95, high: 110, low: 90, volume: 50000 }))
      expect(RedisService).to(have_received(:safe_setex).with("market:TSLA", 300, anything))
    end

    it("raises ApiError on non-200 response") do
      allow(RedisService).to(receive(:safe_get).with("market:TSLA").and_return(nil))

      response = instance_double(Net::HTTPResponse, code: "500")
      http = instance_double(Net::HTTP)
      allow(http).to(receive(:use_ssl=))
      allow(http).to(receive(:open_timeout=))
      allow(http).to(receive(:read_timeout=))
      allow(http).to(receive(:request).and_return(response))
      allow(Net::HTTP).to(receive(:new).and_return(http))

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
      http = instance_double(Net::HTTP)
      allow(http).to(receive(:use_ssl=))
      allow(http).to(receive(:open_timeout=))
      allow(http).to(receive(:read_timeout=))
      allow(http).to(receive(:request).and_return(response))
      allow(Net::HTTP).to(receive(:new).and_return(http))

      result = MarketService.companydata(symbol: "TSLA")

      expect(result).to(eq({ market_cap: 800000000000, description: "Electric vehicles" }))
      expect(RedisService).to(have_received(:safe_setex).with("company:TSLA", 3.days.to_i, anything))
    end

    it("raises ApiError on non-200 response") do
      allow(RedisService).to(receive(:safe_get).with("company:TSLA").and_return(nil))

      response = instance_double(Net::HTTPResponse, code: "500")
      http = instance_double(Net::HTTP)
      allow(http).to(receive(:use_ssl=))
      allow(http).to(receive(:open_timeout=))
      allow(http).to(receive(:read_timeout=))
      allow(http).to(receive(:request).and_return(response))
      allow(Net::HTTP).to(receive(:new).and_return(http))

      expect {
        MarketService.companydata(symbol: "TSLA")
      }.to(raise_error(MarketService::ApiError))
    end
  end

  describe("chartdata") do
    let(:api_response_body) do
      { "results" => [
        { "t" => 1700000000000, "o" => 195, "c" => 200 },
        { "t" => 1700086400000, "o" => 201, "c" => 205 }
      ] }.to_json
    end

    let(:intraday_response_body) do
      { "results" => [
        { "t" => 1704205800000, "o" => 100, "c" => 101 },
        { "t" => 1704283200000, "o" => 150, "c" => 151 },
        { "t" => 1704292200000, "o" => 200, "c" => 201 },
        { "t" => 1704294000000, "o" => 202, "c" => 203 },
        { "t" => 1704315600000, "o" => 210, "c" => 215 }
      ] }.to_json
    end

    def stub_polygon(body)
      response = instance_double(Net::HTTPResponse, code: "200", body: body)
      http = instance_double(Net::HTTP)
      allow(http).to(receive(:use_ssl=))
      allow(http).to(receive(:open_timeout=))
      allow(http).to(receive(:read_timeout=))
      allow(http).to(receive(:request).and_return(response))
      allow(Net::HTTP).to(receive(:new).and_return(http))
    end

    it("returns cached data on cache hit") do
      cached = [{ date: "2023-11-14 09:30", value: 200 }].to_json
      allow(RedisService).to(receive(:safe_get).with("chart:TSLA:1D").and_return(cached))

      result = MarketService.chartdata(symbol: "TSLA")

      expect(result).to(eq(cached))
    end

    it("fetches from API on cache miss and caches result") do
      allow(RedisService).to(receive(:safe_get).with("chart:TSLA:3M").and_return(nil))
      allow(RedisService).to(receive(:safe_setex))
      stub_polygon(api_response_body)

      result = MarketService.chartdata(symbol: "TSLA", range: "3M")

      expect(result.length).to(eq(2))
      expect(result[1][:value]).to(eq(205))
      expect(RedisService).to(have_received(:safe_setex).with("chart:TSLA:3M", 1.hour.to_i, anything))
    end

    it("starts the series at the first bar's open rather than its close") do
      allow(RedisService).to(receive(:safe_get).with("chart:TSLA:3M").and_return(nil))
      allow(RedisService).to(receive(:safe_setex))
      stub_polygon(api_response_body)

      result = MarketService.chartdata(symbol: "TSLA", range: "3M")

      expect(result[0][:value]).to(eq(195))
    end

    it("keeps only the latest regular session for the 1D range") do
      allow(RedisService).to(receive(:safe_get).with("chart:TSLA:1D").and_return(nil))
      allow(RedisService).to(receive(:safe_setex))
      stub_polygon(intraday_response_body)

      result = MarketService.chartdata(symbol: "TSLA", range: "1D")

      expect(result).to(eq([
        { date: "2024-01-03 09:30", value: 200 },
        { date: "2024-01-03 10:00", value: 203 },
        { date: "2024-01-03 16:00", value: 210 }
      ]))
      expect(RedisService).to(have_received(:safe_setex).with("chart:TSLA:1D", 5.minutes.to_i, anything))
    end

    it("takes the closing auction from the 16:00 bar's open, not its close") do
      allow(RedisService).to(receive(:safe_get).with("chart:TSLA:1D").and_return(nil))
      allow(RedisService).to(receive(:safe_setex))
      stub_polygon(intraday_response_body)

      result = MarketService.chartdata(symbol: "TSLA", range: "1D")

      expect(result.last).to(eq({ date: "2024-01-03 16:00", value: 210 }))
    end

    it("drops premarket bars from intraday ranges") do
      allow(RedisService).to(receive(:safe_get).with("chart:TSLA:1W").and_return(nil))
      allow(RedisService).to(receive(:safe_setex))
      stub_polygon(intraday_response_body)

      result = MarketService.chartdata(symbol: "TSLA", range: "1W")

      expect(result.map { |point| point[:date] }).to_not(include("2024-01-03 07:00"))
    end

    it("returns an empty series when the API reports no bars") do
      allow(RedisService).to(receive(:safe_get).with("chart:TSLA:1D").and_return(nil))
      allow(RedisService).to(receive(:safe_setex))
      stub_polygon({ "resultsCount" => 0 }.to_json)

      expect(MarketService.chartdata(symbol: "TSLA", range: "1D")).to(eq([]))
    end

    it("raises KeyError on an unknown range") do
      expect {
        MarketService.chartdata(symbol: "TSLA", range: "2H")
      }.to(raise_error(KeyError))
    end

    it("raises ApiError on non-200 response") do
      allow(RedisService).to(receive(:safe_get).with("chart:TSLA:1D").and_return(nil))

      response = instance_double(Net::HTTPResponse, code: "500")
      http = instance_double(Net::HTTP)
      allow(http).to(receive(:use_ssl=))
      allow(http).to(receive(:open_timeout=))
      allow(http).to(receive(:read_timeout=))
      allow(http).to(receive(:request).and_return(response))
      allow(Net::HTTP).to(receive(:new).and_return(http))

      expect {
        MarketService.chartdata(symbol: "TSLA")
      }.to(raise_error(MarketService::ApiError))
    end
  end
  
end