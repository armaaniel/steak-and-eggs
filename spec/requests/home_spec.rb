require 'rails_helper'

RSpec.describe("Home", type: :request) do
  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }

  describe "GET /search" do
    before do
      allow(RedisService).to(receive(:safe_get).and_return(nil))
      allow(RedisService).to(receive(:safe_setex))
    end

    it "returns matching tickers" do
      Ticker.create!(symbol: "TSLA", name: "Tesla, Inc.", ticker_type: "CS", exchange: "NASDAQ", currency: "USD")

      get "/search", params: { q: "TSL" }, headers: headers

      expect(response).to(have_http_status(200))

      body = JSON.parse(response.body)
      expect(body.length).to(eq(1))
      expect(body[0]["symbol"]).to(eq("TSLA"))
    end

    it "returns empty array on blank query" do
      allow(Sentry).to(receive(:capture_exception))

      get "/search", params: { q: "" }, headers: headers

      expect(response).to(have_http_status(503))
      expect(JSON.parse(response.body)).to(eq([]))
    end

    it "returns 503 with empty array on service error" do
      allow(Ticker).to(receive(:search).and_raise(StandardError))
      allow(Sentry).to(receive(:capture_exception))

      get "/search", params: { q: "TSLA" }, headers: headers

      expect(response).to(have_http_status(503))
      expect(JSON.parse(response.body)).to(eq([]))
    end

    it "returns 401 without auth token" do
      get "/search", params: { q: "TSLA" }

      expect(response).to(have_http_status(401))
    end
  end

  describe "GET /portfoliochart" do
    it "returns portfolio records" do
      cached = [{ date: "2024-01-01", value: 10000 }, { date: "2024-01-02", value: 10500 }].to_json
      allow(RedisService).to(receive(:safe_get).with("portfolio:#{user.id}").and_return(cached))

      get "/portfoliochart", headers: headers

      expect(response).to(have_http_status(200))

      body = JSON.parse(response.body)
      expect(body.length).to(eq(2))
    end

    it "returns fallback on service error" do
      allow(PositionService).to(receive(:portfolio_records).and_raise(StandardError))
      allow(Sentry).to(receive(:capture_exception))

      get "/portfoliochart", headers: headers

      expect(response).to(have_http_status(503))

      body = JSON.parse(response.body)
      expect(body.length).to(eq(2))
      expect(body[0]["value"]).to(eq(0.0))
    end

    it "returns 401 without auth token" do
      get "/portfoliochart"

      expect(response).to(have_http_status(401))
    end
  end

  describe "GET /portfoliodata" do
    it "returns aum and positions" do
      allow(RedisService).to(receive(:safe_get).and_return(nil))
      allow(RedisService).to(receive(:safe_setex))

      get "/portfoliodata", headers: headers

      expect(response).to(have_http_status(200))

      body = JSON.parse(response.body)
      expect(body["aum"]).to(be_present)
      expect(body["balance"]).to(be_present)
    end

    it "returns fallback on service error" do
      allow(PositionService).to(receive(:get_aum).and_raise(StandardError))
      allow(Sentry).to(receive(:capture_exception))

      get "/portfoliodata", headers: headers

      expect(response).to(have_http_status(503))

      body = JSON.parse(response.body)
      expect(body["aum"]).to(eq("N/A"))
      expect(body["balance"]).to(eq("N/A"))
    end

    it "returns 401 without auth token" do
      get "/portfoliodata"

      expect(response).to(have_http_status(401))
    end
  end

  describe "GET /activitydata" do
    it "returns transaction history" do
      cached = [{ id: 1, symbol: "TSLA", value: "1000.0" }].to_json
      allow(RedisService).to(receive(:safe_get).with("activity:#{user.id}").and_return(cached))

      get "/activitydata", headers: headers

      expect(response).to(have_http_status(200))
    end

    it "returns empty array on service error" do
      allow(Transaction).to(receive(:get).and_raise(StandardError))
      allow(Sentry).to(receive(:capture_exception))

      get "/activitydata", headers: headers

      expect(response).to(have_http_status(503))
      expect(JSON.parse(response.body)).to(eq([]))
    end

    it "returns 401 without auth token" do
      get "/activitydata"

      expect(response).to(have_http_status(401))
    end
  end
end
