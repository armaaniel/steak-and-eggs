require 'rails_helper'

RSpec.describe("Tracing", type: :request) do
  let(:user) { create(:user) }

  before do
    Ticker.create!(symbol: "TSLA", name: "Tesla, Inc.", ticker_type: "CS", exchange: "NASDAQ", currency: "USD")
    allow(RedisService).to(receive(:safe_get).with("price:TSLA").and_return("100"))
    allow(CacheService).to(receive(:invalidate_user))
  end

  after { Datacat::TRACE_QUEUE.clear }

  def traced
    ActiveSupport::Notifications.subscribed(Datacat::TracingListener.new, Datacat::TracingListener::PATTERN) { yield }
    Array.new(Datacat::TRACE_QUEUE.size) { Datacat::TRACE_QUEUE.pop }
  end

  it("queues a buy's row with the controller action as the root and MarketService.buy inside it") do
    rows = traced { post("/stocks/TSLA/buy", params: { quantity: 5 }, headers: auth_headers(user)) }

    row = rows.sole
    expect(row).to(include(endpoint: 'POST /stocks/TSLA/buy', status: 201, controller: 'StocksController', action: 'buy', user_id: user.id, source: 'user'))
    expect(row[:spans].map { |span| span.values_at(:name, :parent) }).to(eq([['StocksController#buy', nil], ['MarketService.buy', 0]]))
    expect(row[:db_runtime]).to(be > 0)
    expect(row[:app_ms]).to(eq(row[:duration]))
    expect(row[:breakdown].keys).to(eq(['MarketService.buy']))
  end

  it("stores the row, spans and app_ms included, with the flush thread's insert") do
    rows = traced { post("/stocks/TSLA/buy", params: { quantity: 5 }, headers: auth_headers(user)) }

    Trace.insert_all(rows)

    expect(Trace.last.spans.map { |span| span['name'] }).to(eq(['StocksController#buy', 'MarketService.buy']))
    expect(Trace.last.app_ms).to(eq(rows.sole[:app_ms]))
  end

  it("queues nothing for the health check") do
    expect(traced { get("/") }).to(be_empty)
  end
end
