require 'rails_helper'

RSpec.describe("Tracing", type: :request) do
  let(:user) { create(:user) }

  before do
    Ticker.create!(symbol: "TSLA", name: "Tesla, Inc.", ticker_type: "CS", exchange: "NASDAQ", currency: "USD")
    allow(RedisService).to(receive(:safe_get).with("price:TSLA").and_return("100"))
    allow(CacheService).to(receive(:invalidate_user))
    [User, Ticker, Position, Transaction].each { |model| [model.table_exists?, model.columns_hash, model.primary_key] }
  end

  after { Datacat::TRACE_QUEUE.clear }

  def traced
    ActiveSupport::Notifications.subscribed(Datacat::TracingListener.new, Datacat::TracingListener::PATTERN) { yield }
    Array.new(Datacat::TRACE_QUEUE.size) { Datacat::TRACE_QUEUE.pop }
  end

  def children(spans, name)
    position = spans.index { |span| span[:name] == name }
    spans.select { |span| span[:parent] == position }.map { |span| span[:name] }
  end

  def buy
    traced { post("/stocks/TSLA/buy", params: { quantity: 5 }, headers: auth_headers(user)) }
  end

  it("queues a buy's row with the controller action as the root and MarketService.buy inside it") do
    row = buy.sole

    expect(row).to(include(endpoint: 'POST /stocks/TSLA/buy', status: 201, controller: 'StocksController', action: 'buy', user_id: user.id, source: 'user'))
    expect(row[:spans].first.values_at(:name, :parent)).to(eq(['StocksController#buy', nil]))
    expect(children(row[:spans], 'StocksController#buy')).to(include('MarketService.buy'))
    expect(row[:db_runtime]).to(be > 0)
    expect(row[:breakdown].keys).to(eq(['MarketService.buy']))
  end

  it("records the buy's queries, with the ten inside MarketService.buy and nine of them inside its transaction") do
    spans = buy.sole[:spans]

    expect(children(spans, 'MarketService.buy')).to(eq(['Ticker Exists?', 'transaction']))
    expect(children(spans, 'transaction')).to(eq(['User Load', 'Position Load', 'User Exists?', 'User Update', 'User Load', 'Position Exists?', 'Position Create', 'User Load', 'Transaction Create', 'RELEASE SAVEPOINT active_record_1']))
  end

  it("records the schema lookups a process makes the first time it touches a table") do
    Position.reset_column_information
    Position.connection.schema_cache.clear_data_source_cache!('positions')

    spans = buy.sole[:spans]

    lookups = spans.select { |span| span[:name] == 'SCHEMA' }
    expect(lookups).not_to(be_empty)
    expect(lookups.map { |span| span[:sql] }).to(all(include('?')))
  end

  it("keeps the user's values out of every statement") do
    spans = buy.sole[:spans]

    expect(spans.filter_map { |span| span[:sql] }.size).to(be >= 11)
    expect(spans.to_json).not_to(include(user.username, 'TSLA'))
  end

  it("splits the duration into app_ms and sql_ms") do
    row = buy.sole

    expect(row[:sql_ms]).to(be > 0)
    expect(row[:app_ms] + row[:sql_ms]).to(be_within(0.02).of(row[:duration]))
  end

  it("stores the row, spans and summary columns included, with the flush thread's insert") do
    rows = buy

    Trace.insert_all(rows)

    expect(Trace.last.spans.first['name']).to(eq('StocksController#buy'))
    expect(Trace.last.attributes.slice('app_ms', 'sql_ms')).to(eq(rows.sole.slice(:app_ms, :sql_ms).stringify_keys))
  end

  it("queues nothing for the health check") do
    expect(traced { get("/") }).to(be_empty)
  end
end
