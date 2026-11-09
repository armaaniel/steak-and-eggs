require 'rails_helper'

RSpec.describe(Datacat::TracingListener) do
  let(:listener) { Datacat::TracingListener.new }
  let(:root) { 'process_action.action_controller' }
  let(:service) { 'MarketService.marketprice.datacat' }
  let(:payload) { { controller: 'StocksController', action: 'get_stock_price', method: 'GET', path: '/stocks/AAPL/stockprice' } }

  before { allow(Sentry).to(receive(:capture_exception)) }

  after do
    Datacat::Tracer.clear
    Datacat::TRACE_QUEUE.clear
  end

  def rows
    Array.new(Datacat::TRACE_QUEUE.size) { Datacat::TRACE_QUEUE.pop }
  end

  def request(payload, finished: { status: 200, db_runtime: 0.0, source: 'user' })
    listener.start(root, 'id', payload)
    yield if block_given?
    payload.merge!(finished)
    listener.finish(root, 'id', payload)
  end

  def call_service(payload = {})
    listener.start(service, 'id', payload)
    payload[:used_redis] = true
    yield if block_given?
    listener.finish(service, 'id', payload)
  end

  def run_query(name, sql, **extra)
    query_payload = { name: name, sql: sql, **extra }
    listener.start('sql.active_record', 'id', query_payload)
    yield if block_given?
    listener.finish('sql.active_record', 'id', query_payload)
  end

  def parents(spans)
    spans.map { |span| [span[:name], span[:parent] && spans[span[:parent]][:name]] }
  end

  describe("a tracked request") do
    it("queues one row with today's fields, plus the root and its service as spans") do
      request(payload) { call_service(symbol: 'AAPL') }

      row = rows.sole
      expect(row).to(include(endpoint: 'GET /stocks/AAPL/stockprice', status: 200, db_runtime: 0.0, controller: 'StocksController', action: 'get_stock_price', source: 'user'))
      expect(row[:spans].map { |span| span.values_at(:name, :category, :parent) }).to(eq([['StocksController#get_stock_price', 'app', nil], ['MarketService.marketprice', 'app', 0]]))
      expect(row[:duration]).to(eq(row[:spans].first[:duration]))
    end

    it("keeps the breakdown as today, with the service's payload and duration, and no exception objects") do
      request(payload) { call_service(symbol: 'AAPL', exception: ['ArgumentError', 'boom'], exception_object: ArgumentError.new) }

      entry = rows.sole[:breakdown]['MarketService.marketprice']
      expect(entry).to(include(symbol: 'AAPL', used_redis: true, duration: be_a(Float)))
      expect(entry.keys).not_to(include(:exception, :exception_object))
    end

    it("stores the time spent in app code as app_ms, all of the duration while every span is app") do
      request(payload) { call_service(symbol: 'AAPL') }

      row = rows.sole
      expect(row[:app_ms]).to(eq(row[:duration]))
    end

    it("strips the query string from the endpoint") do
      request(payload.merge(path: '/search?term=apple'))

      expect(rows.sole[:endpoint]).to(eq('GET /search'))
    end

    it("takes the error class from the exception when the action raised") do
      request(payload, finished: { status: 500, exception: ['ArgumentError', 'boom'] })

      expect(rows.sole[:error_class]).to(eq('ArgumentError'))
      expect(Datacat::Tracer.current).to(be_nil)
    end

    it("clears the tracer when the request finishes") do
      request(payload) { expect(Datacat::Tracer.current).to(be_present) }

      expect(Datacat::Tracer.current).to(be_nil)
    end
  end

  describe("a request that isn't traced") do
    it("records nothing for an untracked route") do
      request(payload.merge(path: '/', controller: 'SystemController', action: 'health')) { call_service }

      expect(rows).to(be_empty)
    end

    it("records nothing for the not found action, even under a tracked prefix") do
      request(payload.merge(path: '/stocks/AAPL/nope', controller: 'SystemController', action: 'not_found'))

      expect(rows).to(be_empty)
    end

    it("clears a tracer left on the thread, so its events don't land in an old trace") do
      left_behind = Datacat::Tracer.create
      left_behind.open('StocksController#buy', 'app')

      request(payload.merge(path: '/')) { call_service }

      expect(Datacat::Tracer.current).to(be_nil)
      expect(left_behind.spans.size).to(eq(1))
    end
  end

  describe("queries") do
    it("records a query as a sql span named by Rails, with its values replaced") do
      request(payload) { call_service { run_query('User Load', 'SELECT "users".* FROM "users" WHERE "users"."id" = 42 LIMIT 1') } }

      span = rows.sole[:spans].last
      expect(span).to(include(name: 'User Load', category: 'sql', parent: 1, sql: 'SELECT "users".* FROM "users" WHERE "users"."id" = ? LIMIT ?'))
    end

    it("marks a query the query cache answered") do
      request(payload) { run_query('User Load', 'SELECT "users".* FROM "users" WHERE "users"."id" = 42 LIMIT 1', cached: true) }

      expect(rows.sole[:spans].last).to(include(cached: true))
    end

    it("keeps the span but drops the statement when it can't be shaped") do
      request(payload) { run_query('User Load', %q(SELECT 1 FROM "users" WHERE "username" = 'armaan)) }

      span = rows.sole[:spans].last
      expect(span[:name]).to(eq('User Load'))
      expect(span).not_to(have_key(:sql))
    end

    it("names BEGIN and COMMIT by their statement, without the query log comment") do
      request(payload) do
        run_query('TRANSACTION', "BEGIN /*application='SteakAndEggs',action='buy'*/")
        run_query('TRANSACTION', "COMMIT /*application='SteakAndEggs',action='buy'*/")
      end

      expect(rows.sole[:spans].drop(1).map { |span| span.slice(:name, :sql) }).to(eq([{ name: 'BEGIN' }, { name: 'COMMIT' }]))
    end

    it("records Rails' SCHEMA lookups as sql spans like any other query") do
      request(payload) do
        call_service do
          run_query('SCHEMA', %q(SELECT a.attname FROM pg_attribute a WHERE a.attrelid = '"users"'::regclass))
          run_query('User Load', 'SELECT "users".* FROM "users" WHERE "users"."id" = 42 LIMIT 1')
        end
      end

      spans = rows.sole[:spans]
      expect(parents(spans).drop(2)).to(eq([['SCHEMA', 'MarketService.marketprice'], ['User Load', 'MarketService.marketprice']]))
      expect(spans[2]).to(include(category: 'sql', sql: 'SELECT a.attname FROM pg_attribute a WHERE a.attrelid = ?::regclass'))
    end

    it("stores query time as sql_ms, with app_ms and sql_ms adding up to the duration") do
      request(payload) { call_service { run_query('User Load', 'SELECT "users".* FROM "users" WHERE "users"."id" = 42 LIMIT 1') { sleep(0.002) } } }

      row = rows.sole
      expect(row[:sql_ms]).to(be >= 2.0)
      expect(row[:app_ms] + row[:sql_ms]).to(be_within(0.02).of(row[:duration]))
    end
  end

  describe("redis") do
    def run_redis(*command, reply: 'OK', exception: nil)
      redis_payload = { command: command }
      listener.start('command.redis', 'id', redis_payload)
      exception ? redis_payload[:exception] = exception : redis_payload[:reply] = reply
      listener.finish('command.redis', 'id', redis_payload)
    end

    it("records a command as a redis span named by its key's prefix") do
      request(payload) { call_service { run_redis('set', 'user:8675309', 'secret', 'PX', 86_400_000) } }

      spans = rows.sole[:spans]
      expect(spans.last).to(include(name: 'SET user:?', category: 'redis', parent: 1))
      expect(spans.to_json).not_to(include('secret', '8675309'))
    end

    it("marks a GET by whether it found a value, and an MGET as a hit only when every key came back") do
      request(payload) do
        run_redis('get', 'price:AAPL', reply: '246.91')
        run_redis('get', 'company:AAPL', reply: nil)
        run_redis('mget', 'price:AAPL', 'open:AAPL', reply: ['246.91', '244.10'])
        run_redis('mget', 'price:AAPL', 'open:AAPL', reply: ['246.91', nil])
        run_redis('del', 'portfolio:42', reply: 1)
      end

      expect(rows.sole[:spans].drop(1).map { |span| span[:hit] }).to(eq([true, false, true, false, nil]))
    end

    it("gives a command that raised no hit, and keeps the next span's parent right") do
      request(payload) do
        run_redis('get', 'price:AAPL', exception: ['RedisClient::ConnectionError', 'down'])
        run_redis('get', 'open:AAPL', reply: '244.10')
      end

      expect(rows.sole[:spans].drop(1).map { |span| span.slice(:name, :parent, :hit) }).to(eq([{ name: 'GET price:?', parent: 0 }, { name: 'GET open:?', parent: 0, hit: true }]))
    end

    it("stores redis time as redis_ms and counts the cache hits and misses") do
      request(payload) do
        call_service do
          run_redis('mget', 'price:AAPL', 'open:AAPL', reply: ['246.91', '244.10'])
          run_redis('get', 'company:AAPL', reply: nil)
        end
      end

      row = rows.sole
      expect(parents(row[:spans]).drop(2)).to(eq([['MGET price:? open:?', 'MarketService.marketprice'], ['GET company:?', 'MarketService.marketprice']]))
      expect(row).to(include(cache_hits: 1, cache_misses: 1, redis_ms: be_a(Float)))
      expect(row[:app_ms] + row[:redis_ms]).to(be_within(0.02).of(row[:duration]))
    end

    it("gets its events from the redis-client middleware, and never breaks a command when the tracer does") do
      redis = Class.new(RedisClient::BasicMiddleware) { include Datacat::RedisEvents }.new(nil)
      replies = []

      ActiveSupport::Notifications.subscribed(listener, Datacat::TracingListener::PATTERN) do
        ActiveSupport::Notifications.instrument(root, payload) do |event_payload|
          replies << redis.call(['get', 'price:AAPL'], nil) { '246.91' }
          event_payload[:status] = 200
        end

        allow(Datacat::Tracer).to(receive(:current).and_raise(NoMethodError))
        replies << redis.call(['get', 'open:AAPL'], nil) { '244.10' }
      end

      expect(replies).to(eq(['246.91', '244.10']))
      expect(rows.sole[:spans].last).to(include(name: 'GET price:?', hit: true))
      expect(Sentry).to(have_received(:capture_exception).with(be_a(NoMethodError)).twice)
    end

    it("stores zero hits and misses for a request that looked nothing up") do
      request(payload)

      expect(rows.sole).to(include(cache_hits: 0, cache_misses: 0, redis_ms: nil))
    end
  end

  describe("http") do
    it("records a request as an http span named by its method and host, and stores the time as http_ms") do
      request(payload) do
        call_service do
          http_payload = { method: 'GET', host: 'api.polygon.io' }
          listener.start('request.http', 'id', http_payload)
          listener.finish('request.http', 'id', http_payload)
        end
      end

      row = rows.sole
      expect(row[:spans].last).to(include(name: 'GET api.polygon.io', category: 'http', parent: 1))
      expect(row[:http_ms]).to(be_a(Float))
    end
  end

  describe("PATTERN") do
    it("matches every event the listener handles, and nothing that only looks like one") do
      handled = ['process_action.action_controller', 'sql.active_record', 'transaction.active_record', 'command.redis', 'request.http', 'before_action.action_controller', 'render.action_controller', 'MarketService.buy.datacat']
      lookalikes = ['start_processing.action_controller', 'sql.active_record.extra', 'instantiation.active_record', 'xcommand.redis', 'request.http2', 'render_template.action_view', 'datacat']

      expect(handled).to(all(match(Datacat::TracingListener::PATTERN)))
      expect(lookalikes).to(all(satisfy { |name| !name.match?(Datacat::TracingListener::PATTERN) }))
    end
  end

  describe("transactions") do
    let(:transaction) { 'transaction.active_record' }

    it("slots a transaction that starts inside its first query between that query and its parent, as Rails' lazy BEGIN does") do
      transaction_payload = {}

      request(payload) do
        call_service do
          run_query('User Load', 'SELECT "users".* FROM "users" WHERE "users"."id" = 42 LIMIT 1 FOR UPDATE') do
            run_query('TRANSACTION', 'BEGIN')
            listener.start(transaction, 'id', transaction_payload)
          end
          run_query('Position Load', 'SELECT "positions".* FROM "positions" WHERE "positions"."user_id" = 42 LIMIT 1')
          run_query('TRANSACTION', 'COMMIT')
          listener.finish(transaction, 'id', transaction_payload)
        end
      end

      expect(parents(rows.sole[:spans])).to(eq([
        ['StocksController#get_stock_price', nil],
        ['MarketService.marketprice', 'StocksController#get_stock_price'],
        ['User Load', 'transaction'],
        ['BEGIN', 'User Load'],
        ['transaction', 'MarketService.marketprice'],
        ['Position Load', 'transaction'],
        ['COMMIT', 'transaction']
      ]))
    end

    it("opens a transaction that starts outside any query as a plain child") do
      transaction_payload = {}

      request(payload) do
        call_service do
          listener.start(transaction, 'id', transaction_payload)
          run_query('User Load', 'SELECT "users".* FROM "users" WHERE "users"."id" = 42 LIMIT 1')
          listener.finish(transaction, 'id', transaction_payload)
        end
      end

      expect(parents(rows.sole[:spans]).drop(2)).to(eq([['transaction', 'MarketService.marketprice'], ['User Load', 'transaction']]))
    end

    it("opens a transaction that starts directly inside another one as its child, not around it") do
      outer = {}
      inner = {}

      request(payload) do
        listener.start(transaction, 'id', outer)
        listener.start(transaction, 'id', inner)
        listener.finish(transaction, 'id', inner)
        listener.finish(transaction, 'id', outer)
      end

      expect(rows.sole[:spans].map { |span| span[:parent] }).to(eq([nil, 0, 1]))
    end
  end

  describe("an event with no trace open") do
    it("is ignored") do
      call_service

      expect(rows).to(be_empty)
      expect(Sentry).not_to(have_received(:capture_exception))
    end

    it("is ignored for a query too, like the flush thread's insert") do
      run_query('Trace Insert', 'INSERT INTO "traces" ("endpoint") VALUES (\'GET /search\')')

      expect(rows).to(be_empty)
      expect(Datacat::Tracer.current).to(be_nil)
      expect(Sentry).not_to(have_received(:capture_exception))
    end
  end

  describe("its own errors") do
    it("reports them to Sentry instead of raising, and still clears the tracer") do
      allow(Datacat::TRACE_QUEUE).to(receive(:push).and_raise(ThreadError))

      expect { request(payload) }.not_to(raise_error)
      expect(Sentry).to(have_received(:capture_exception).with(be_a(ThreadError)))
      expect(Datacat::Tracer.current).to(be_nil)
    end
  end

  describe("subscribed to ActiveSupport::Notifications") do
    it("is called at the start and finish of each event, so a nested event gets the root as its parent") do
      ActiveSupport::Notifications.subscribed(listener, Datacat::TracingListener::PATTERN) do
        ActiveSupport::Notifications.instrument(root, payload) do |event_payload|
          ActiveSupport::Notifications.instrument(service, symbol: 'AAPL') { }
          event_payload[:status] = 200
        end
      end

      row = rows.sole
      expect(row[:status]).to(eq(200))
      expect(row[:spans].map { |span| span.values_at(:name, :parent) }).to(eq([['StocksController#get_stock_price', nil], ['MarketService.marketprice', 0]]))
    end
  end
end
