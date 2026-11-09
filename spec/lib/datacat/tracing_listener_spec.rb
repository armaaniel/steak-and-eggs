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
    listener.finish(service, 'id', payload)
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

  describe("an event with no trace open") do
    it("is ignored") do
      call_service

      expect(rows).to(be_empty)
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
