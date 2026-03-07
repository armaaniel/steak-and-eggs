require 'rails_helper'

RSpec.describe(Ticker) do
  before do
    allow(RedisService).to(receive(:safe_get).and_return(nil))
    allow(RedisService).to(receive(:safe_setex))
  end

  describe("search") do
    it("returns matching tickers by symbol") do
      Ticker.create!(symbol: "TSLA", name: "Tesla, Inc.", ticker_type: "CS", exchange: "NASDAQ", currency: "USD")
      Ticker.create!(symbol: "AAPL", name: "Apple Inc.", ticker_type: "CS", exchange: "NASDAQ", currency: "USD")

      result = Ticker.search(term: "TSL")

      expect(result.length).to(eq(1))
      expect(result.first.symbol).to(eq("TSLA"))
    end

    it("returns matching tickers by name") do
      Ticker.create!(symbol: "TSLA", name: "Tesla, Inc.", ticker_type: "CS", exchange: "NASDAQ", currency: "USD")

      result = Ticker.search(term: "Tes")

      expect(result.length).to(eq(1))
      expect(result.first.name).to(eq("Tesla, Inc."))
    end

    it("is case insensitive") do
      Ticker.create!(symbol: "TSLA", name: "Tesla, Inc.", ticker_type: "CS", exchange: "NASDAQ", currency: "USD")

      result = Ticker.search(term: "tsla")

      expect(result.length).to(eq(1))
    end

    it("limits results to 15") do
      20.times do |i|
        Ticker.create!(symbol: "T#{i}", name: "Test #{i}", ticker_type: "CS", exchange: "NASDAQ", currency: "USD")
      end

      result = Ticker.search(term: "T")

      expect(result.length).to(eq(15))
    end

    it("returns cached data on cache hit") do
      cached = [{ symbol: "TSLA", name: "Tesla, Inc." }].to_json
      allow(RedisService).to(receive(:safe_get).with("search:TSL").and_return(cached))

      result = Ticker.search(term: "TSL")

      expect(result).to(eq(cached))
    end

    it("raises on blank term") do
      expect { Ticker.search(term: "") }.to(raise_error(StandardError))
      expect { Ticker.search(term: nil) }.to(raise_error(StandardError))
    end
  end

  describe("query") do
    it("returns ticker data when found") do
      Ticker.create!(symbol: "TSLA", name: "Tesla, Inc.", ticker_type: "CS", exchange: "NASDAQ", currency: "USD")

      result = Ticker.query(symbol: "TSLA")

      expect(result[:name]).to(eq("Tesla, Inc."))
      expect(result[:ticker_type]).to(eq("CS"))
      expect(result[:exchange]).to(eq("NASDAQ"))
    end

    it("caches result with one month TTL") do
      Ticker.create!(symbol: "TSLA", name: "Tesla, Inc.", ticker_type: "CS", exchange: "NASDAQ", currency: "USD")

      Ticker.query(symbol: "TSLA")

      expect(RedisService).to(have_received(:safe_setex).with("ticker:TSLA", 1.month.to_i, anything))
    end

    it("returns nil when ticker not found") do
      result = Ticker.query(symbol: "FAKE")

      expect(result).to(be_nil)
    end

    it("returns cached data on cache hit") do
      cached = { name: "Tesla, Inc.", ticker_type: "CS", exchange: "NASDAQ" }.to_json
      allow(RedisService).to(receive(:safe_get).with("ticker:TSLA").and_return(cached))

      result = Ticker.query(symbol: "TSLA")

      expect(result).to(eq(cached))
    end

    it("raises on blank symbol") do
      expect { Ticker.query(symbol: "") }.to(raise_error(StandardError))
      expect { Ticker.query(symbol: nil) }.to(raise_error(StandardError))
    end
  end
end