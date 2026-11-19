require 'rails_helper'

RSpec.describe("Tracing", type: :request) do
  let(:user) { create(:user) }

  before do
    Ticker.create!(symbol: "TSLA", name: "Tesla, Inc.", ticker_type: "CS", exchange: "NASDAQ", currency: "USD")
    allow(RedisService).to(receive(:safe_get).with("price:TSLA").and_return("100"))
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
  end

  it("records the buy's transaction and its one cache delete inside MarketService.buy, with six queries inside the transaction") do
    spans = buy.sole[:spans]

    expect(children(spans, 'MarketService.buy')).to(eq(['transaction', 'DEL portfolio:? activity:? positions:?']))
    expect(children(spans, 'transaction')).to(eq(['User Load', 'Position Load', 'User Update', 'Position Exists?', 'Position Create', 'Transaction Create', 'RELEASE SAVEPOINT active_record_1']))
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

    expect(spans.filter_map { |span| span[:sql] }.size).to(be >= 8)
    expect(spans.to_json).not_to(include(user.username, 'TSLA'))
  end

  it("splits the duration into categories that add up to it") do
    row = buy.sole

    expect(row.values_at(:sql_ms, :callbacks_ms, :render_ms)).to(all(be > 0))
    expect(row.values_at(:app_ms, :sql_ms, :redis_ms, :http_ms, :callbacks_ms, :render_ms).sum(&:to_f)).to(be_within(0.03).of(row[:duration]))
  end

  it("puts verify_token's work inside a before_action span, and the response's JSON in a render span") do
    spans = buy.sole[:spans]

    expect(children(spans, 'StocksController#buy')).to(eq(['before_action', 'MarketService.buy', 'render json']))
    expect(children(spans, 'before_action')).to(eq(['Ticker Load', 'User Load']))
    expect(spans.select { |span| span[:name].in?(['before_action', 'render json']) }.map { |span| span[:category] }).to(eq(['callbacks', 'render']))
  end

  it("closes before_action when verify_token stops the request, with its 401 rendered inside it") do
    row = traced { post("/stocks/TSLA/buy", params: { quantity: 5 }) }.sole

    expect(row[:status]).to(eq(401))
    expect(children(row[:spans], 'StocksController#buy')).to(eq(['before_action']))
    expect(children(row[:spans], 'before_action')).to(eq(['Ticker Load', 'render json']))
  end

  it("records a symbol that isn't a ticker by its route, so whatever was typed into the url isn't stored") do
    allow(RedisService).to(receive(:safe_get).with(start_with("ticker:")).and_return(nil))

    rows = traced do
      get("/stocks/BRUHH/tickerdata")
      get("/stocks/BR%20UH/tickerdata")
    end

    expect(rows.map { |row| row[:endpoint] }).to(eq(['GET /stocks/:symbol/tickerdata', 'GET /stocks/:symbol/tickerdata']))
    expect(rows.to_json).not_to(include('BRUHH', 'BR%20UH', 'BR UH'))
  end

  it("answers a stockprice from the cache without asking postgres, and records an unknown symbol's by its route") do
    allow(RedisService).to(receive(:safe_mget).with("price:TSLA", "open:TSLA").and_return(["100", "95"]))
    allow(RedisService).to(receive(:safe_mget).with("price:BRUHH", "open:BRUHH").and_return([nil, nil]))

    known, unknown = traced do
      get("/stocks/TSLA/stockprice")
      get("/stocks/BRUHH/stockprice")
    end

    expect(known).to(include(status: 200, endpoint: 'GET /stocks/TSLA/stockprice', sql_ms: nil))
    expect(known[:spans].map { |span| span[:category] }).not_to(include('sql'))
    expect(unknown).to(include(status: 404, endpoint: 'GET /stocks/:symbol/stockprice'))
    expect(unknown.to_json).not_to(include('BRUHH'))
  end

  it("records the route when verify_token stops the request first") do
    row = traced { get("/stocks/BRUHH/userdata") }.sole

    expect(row[:status]).to(eq(401))
    expect(row[:endpoint]).to(eq('GET /stocks/:symbol/userdata'))
  end

  it("records the route when the ticker check fails") do
    lookups = 0
    allow(Ticker).to(receive(:find_by).and_wrap_original do |find_by, **conditions|
      lookups += 1
      raise ActiveRecord::ConnectionNotEstablished if lookups == 1

      find_by.call(**conditions)
    end)
    allow(Sentry).to(receive(:capture_exception))
    allow(RedisService).to(receive(:safe_get).with("ticker:TSLA").and_return(nil))

    row = traced { get("/stocks/TSLA/tickerdata") }.sole

    expect(row[:status]).to(eq(200))
    expect(row[:endpoint]).to(eq('GET /stocks/:symbol/tickerdata'))
  end

  it("records no before_action for a controller that has no before callbacks") do
    row = traced { post("/graphql", params: { query: '{ __typename }' }) }.sole

    expect(row[:spans].map { |span| span[:name] }).to(eq(['GraphqlController#execute', 'GraphQL.execute', 'render json']))
    expect(row[:callbacks_ms]).to(be_nil)
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
