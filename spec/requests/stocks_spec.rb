require 'rails_helper'

RSpec.describe("Stocks", type: :request) do
  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }

  describe "POST /stocks/:symbol/buy" do
    before do
      allow(RedisService).to(receive(:safe_get).with("price:TSLA").and_return("100"))
      allow(CacheService).to(receive(:invalidate_user))
    end

    it "returns 201 with trade data" do
      post "/stocks/TSLA/buy", params: { quantity: 5, name: "Tesla, Inc." }, headers: headers

      expect(response).to(have_http_status(201))

      body = JSON.parse(response.body)
      expect(body["symbol"]).to(eq("TSLA"))
      expect(body["quantity"]).to(eq(5))
      expect(body["value"].to_f).to(eq(500.0))
      expect(body["market_price"].to_f).to(eq(100.0))
    end

    it "returns 422 when quantity is zero" do
      post "/stocks/TSLA/buy", params: { quantity: 0, name: "Tesla" }, headers: headers

      expect(response).to(have_http_status(422))
      expect(JSON.parse(response.body)["error"]).to(eq("Invalid quantity"))
    end

    it "returns 422 when quantity is negative" do
      post "/stocks/TSLA/buy", params: { quantity: -5, name: "Tesla" }, headers: headers

      expect(response).to(have_http_status(422))
      expect(JSON.parse(response.body)["error"]).to(eq("Invalid quantity"))
    end

    it "returns 422 when quantity is blank" do
      post "/stocks/TSLA/buy", params: { name: "Tesla" }, headers: headers

      expect(response).to(have_http_status(422))
      expect(JSON.parse(response.body)["error"]).to(eq("Invalid quantity"))
    end

    it "returns 402 on insufficient funds" do
      user.update!(balance: 1)

      post "/stocks/TSLA/buy", params: { quantity: 5, name: "Tesla" }, headers: headers

      expect(response).to(have_http_status(402))
      expect(JSON.parse(response.body)["error"]).to(eq("Insufficient funds for this transaction"))
    end

    it "returns 503 on unexpected service error" do
      allow(RedisService).to(receive(:safe_get).with("price:TSLA").and_return(nil))

      post "/stocks/TSLA/buy", params: { quantity: 5, name: "Tesla" }, headers: headers

      expect(response).to(have_http_status(503))
      expect(JSON.parse(response.body)["error"]).to(eq("Service temporarily unavailable"))
    end

    it "returns 401 without auth token" do
      post "/stocks/TSLA/buy", params: { quantity: 5, name: "Tesla" }

      expect(response).to(have_http_status(401))
    end
  end

  describe "POST /stocks/:symbol/sell" do
    before do
      allow(RedisService).to(receive(:safe_get).with("price:TSLA").and_return("100"))
      allow(CacheService).to(receive(:invalidate_user))
      Position.create!(user_id: user.id, symbol: "TSLA", shares: 20, average_price: 80, name: "Tesla, Inc.")
    end

    it "returns 201 with trade data including realized pnl" do
      post "/stocks/TSLA/sell", params: { quantity: 10 }, headers: headers

      expect(response).to(have_http_status(201))

      body = JSON.parse(response.body)
      expect(body["symbol"]).to(eq("TSLA"))
      expect(body["quantity"]).to(eq(10))
      expect(body["realized_pnl"].to_f).to(eq(200.0))
    end

    it "returns 422 when quantity is zero" do
      post "/stocks/TSLA/sell", params: { quantity: 0 }, headers: headers

      expect(response).to(have_http_status(422))
      expect(JSON.parse(response.body)["error"]).to(eq("Invalid quantity"))
    end

    it "returns 422 when quantity is blank" do
      post "/stocks/TSLA/sell", params: {}, headers: headers

      expect(response).to(have_http_status(422))
      expect(JSON.parse(response.body)["error"]).to(eq("Invalid quantity"))
    end

    it "returns 402 on insufficient shares" do
      post "/stocks/TSLA/sell", params: { quantity: 100 }, headers: headers

      expect(response).to(have_http_status(402))
      expect(JSON.parse(response.body)["error"]).to(eq("Insufficient shares for this transaction"))
    end

    it "returns 503 on unexpected service error" do
      allow(RedisService).to(receive(:safe_get).with("price:TSLA").and_return(nil))

      post "/stocks/TSLA/sell", params: { quantity: 5 }, headers: headers

      expect(response).to(have_http_status(503))
      expect(JSON.parse(response.body)["error"]).to(eq("Service temporarily unavailable"))
    end

    it "returns 401 without auth token" do
      post "/stocks/TSLA/sell", params: { quantity: 5 }

      expect(response).to(have_http_status(401))
    end
  end

  describe "GET /stocks/:symbol/tickerdata" do
    it "returns ticker data when found" do
      Ticker.create!(symbol: "TSLA", name: "Tesla, Inc.", ticker_type: "CS", exchange: "NASDAQ", currency: "USD")
      allow(RedisService).to(receive(:safe_get).and_return(nil))
      allow(RedisService).to(receive(:safe_setex))

      get "/stocks/TSLA/tickerdata", headers: headers

      expect(response).to(have_http_status(200))

      body = JSON.parse(response.body)
      expect(body["name"]).to(eq("Tesla, Inc."))
    end

    it "returns 404 when ticker not found" do
      allow(RedisService).to(receive(:safe_get).and_return(nil))

      get "/stocks/FAKE/tickerdata", headers: headers

      expect(response).to(have_http_status(404))
    end

    it "returns 401 without auth token" do
      get "/stocks/TSLA/tickerdata"

      expect(response).to(have_http_status(401))
    end
  end

  describe "GET /stocks/:symbol/chartdata" do
    it "returns chart data from cache" do
      cached = [{ date: "2024-01-01", value: 200 }].to_json
      allow(RedisService).to(receive(:safe_get).with("daily:TSLA").and_return(cached))

      get "/stocks/TSLA/chartdata", headers: headers

      expect(response).to(have_http_status(200))
    end

    it "returns fallback data on service error" do
      allow(RedisService).to(receive(:safe_get).with("daily:TSLA").and_return(nil))
      allow(Net::HTTP).to(receive(:get_response).and_raise(StandardError))
      allow(Sentry).to(receive(:capture_exception))

      get "/stocks/TSLA/chartdata", headers: headers

      expect(response).to(have_http_status(503))

      body = JSON.parse(response.body)
      expect(body).to(be_an(Array))
      expect(body.length).to(eq(2))
    end
  end

  describe "GET /stocks/:symbol/companydata" do
    it "returns company data from cache" do
      cached = { market_cap: 800000000000, description: "Electric vehicles" }.to_json
      allow(RedisService).to(receive(:safe_get).with("company:TSLA").and_return(cached))

      get "/stocks/TSLA/companydata", headers: headers

      expect(response).to(have_http_status(200))
    end

    it "returns fallback data on service error" do
      allow(RedisService).to(receive(:safe_get).with("company:TSLA").and_return(nil))
      allow(Net::HTTP).to(receive(:get_response).and_raise(StandardError))
      allow(Sentry).to(receive(:capture_exception))

      get "/stocks/TSLA/companydata", headers: headers

      expect(response).to(have_http_status(503))

      body = JSON.parse(response.body)
      expect(body["market_cap"]).to(eq("N/A"))
      expect(body["description"]).to(eq("N/A"))
    end
  end

  describe "GET /stocks/:symbol/marketdata" do
    it "returns market data from cache" do
      cached = { open: 95, high: 110, low: 90, volume: 50000 }.to_json
      allow(RedisService).to(receive(:safe_get).with("market:TSLA").and_return(cached))

      get "/stocks/TSLA/marketdata", headers: headers

      expect(response).to(have_http_status(200))
    end

    it "returns fallback data on service error" do
      allow(RedisService).to(receive(:safe_get).with("market:TSLA").and_return(nil))
      allow(Net::HTTP).to(receive(:get_response).and_raise(StandardError))
      allow(Sentry).to(receive(:capture_exception))

      get "/stocks/TSLA/marketdata", headers: headers

      expect(response).to(have_http_status(503))

      body = JSON.parse(response.body)
      expect(body["open"]).to(eq("N/A"))
      expect(body["high"]).to(eq("N/A"))
      expect(body["low"]).to(eq("N/A"))
      expect(body["volume"]).to(eq("N/A"))
    end
  end

  describe "GET /stocks/:symbol/stockprice" do
    it "returns price and open from cache" do
      allow(RedisService).to(receive(:safe_get).with("price:TSLA").and_return("100"))
      allow(RedisService).to(receive(:safe_get).with("open:TSLA").and_return("95"))

      get "/stocks/TSLA/stockprice", headers: headers

      expect(response).to(have_http_status(200))

      body = JSON.parse(response.body)
      expect(body["price"]).to(eq("100"))
      expect(body["open"]).to(eq("95"))
    end

    it "returns fallback data when price not cached" do
      allow(RedisService).to(receive(:safe_get).and_return(nil))
      allow(Sentry).to(receive(:capture_exception))

      get "/stocks/TSLA/stockprice", headers: headers

      expect(response).to(have_http_status(503))

      body = JSON.parse(response.body)
      expect(body["price"]).to(eq("N/A"))
      expect(body["open"]).to(eq("N/A"))
    end
  end

  describe "GET /stocks/:symbol/userdata" do
    it "returns position and balance when position exists" do
      Position.create!(user_id: user.id, symbol: "TSLA", shares: 10, average_price: 100, name: "Tesla, Inc.")

      get "/stocks/TSLA/userdata", headers: headers

      expect(response).to(have_http_status(200))

      body = JSON.parse(response.body)
      expect(body["position"]["shares"]).to(eq(10))
      expect(body["balance"].to_f).to(eq(10000.0))
    end

    it "returns only balance when no position exists" do
      get "/stocks/TSLA/userdata", headers: headers

      expect(response).to(have_http_status(200))

      body = JSON.parse(response.body)
      expect(body["position"]).to(be_nil)
      expect(body["balance"].to_f).to(eq(10000.0))
    end

    it "returns fallback on service error" do
      allow(PositionService).to(receive(:find_position).and_raise(StandardError))
      allow(Sentry).to(receive(:capture_exception))

      get "/stocks/TSLA/userdata", headers: headers

      expect(response).to(have_http_status(503))

      body = JSON.parse(response.body)
      expect(body["balance"]).to(eq("N/A"))
    end
  end
end
