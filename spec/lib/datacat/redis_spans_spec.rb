require 'rails_helper'

RSpec.describe(Datacat::RedisSpans) do
  let(:middleware) { Class.new(RedisClient::BasicMiddleware) { include Datacat::RedisSpans }.new(nil) }

  before { allow(Sentry).to(receive(:capture_exception)) }
  after { Datacat::Tracer.clear }

  def run(*command, reply: 'OK')
    middleware.call(command, nil) { reply }
  end

  def traced
    tracer = Datacat::Tracer.create
    tracer.open('StocksController#get_stock_price', 'app')
    yield
    tracer.spans.drop(1)
  end

  describe(".name") do
    it("is the command and its key's prefix, never the rest of the key or any value") do
      expect(Datacat::RedisSpans.name(['get', 'price:AAPL'])).to(eq('GET price:?'))
      expect(Datacat::RedisSpans.name(['set', 'user:42', "\x04\bo:\tUser", 'PX', 86_400_000])).to(eq('SET user:?'))
      expect(Datacat::RedisSpans.name(['setex', 'search:apple', 300, '[]'])).to(eq('SETEX search:?'))
    end

    it("lists each distinct key prefix for commands that take several keys") do
      expect(Datacat::RedisSpans.name(['mget', 'price:AAPL', 'open:AAPL'])).to(eq('MGET price:? open:?'))
      expect(Datacat::RedisSpans.name(['del', 'portfolio:42', 'activity:42', 'portfolio:43'])).to(eq('DEL portfolio:? activity:?'))
    end

    it("hides a key with no colon completely") do
      expect(Datacat::RedisSpans.name(['get', 'user_42'])).to(eq('GET ?'))
    end

    it("names a keyless command by itself") do
      expect(Datacat::RedisSpans.name(['scan', '0', 'MATCH', 'chart:AAPL:*', 'COUNT', 1000])).to(eq('SCAN'))
    end
  end

  describe("#call") do
    it("records the command as a redis span inside the open span, and returns its reply") do
      reply = nil

      spans = traced { reply = run('get', 'price:AAPL', reply: '246.91') }

      expect(reply).to(eq('246.91'))
      expect(spans.sole).to(include(name: 'GET price:?', category: 'redis', parent: 0, hit: true))
    end

    it("marks a GET that came back empty as a miss") do
      expect(traced { run('get', 'price:AAPL', reply: nil) }.sole[:hit]).to(be(false))
    end

    it("counts an MGET as a hit only when every key came back") do
      spans = traced do
        run('mget', 'price:AAPL', 'open:AAPL', reply: ['246.91', '244.10'])
        run('mget', 'price:AAPL', 'open:AAPL', reply: ['246.91', nil])
      end

      expect(spans.map { |span| span[:hit] }).to(eq([true, false]))
    end

    it("gives other commands no hit") do
      expect(traced { run('del', 'portfolio:42', reply: 1) }.sole).not_to(have_key(:hit))
    end

    it("just runs the command when no trace is open") do
      expect(run('get', 'price:AAPL', reply: '246.91')).to(eq('246.91'))
      expect(Datacat::Tracer.current).to(be_nil)
    end

    it("closes the span without a hit when the command raises, and lets the error reach the caller") do
      spans = traced do
        expect { middleware.call(['get', 'price:AAPL'], nil) { raise(RedisClient::ConnectionError, 'down') } }.to(raise_error(RedisClient::ConnectionError))
        run('get', 'open:AAPL', reply: '244.10')
      end

      expect(spans.map { |span| span.slice(:name, :parent, :hit) }).to(eq([{ name: 'GET price:?', parent: 0 }, { name: 'GET open:?', parent: 0, hit: true }]))
    end

    it("still runs the command, and reports to Sentry, when the tracer breaks") do
      allow(Datacat::Tracer).to(receive(:current).and_raise(NoMethodError))

      expect(run('get', 'price:AAPL', reply: '246.91')).to(eq('246.91'))
      expect(Sentry).to(have_received(:capture_exception).with(be_a(NoMethodError)))
    end
  end
end
