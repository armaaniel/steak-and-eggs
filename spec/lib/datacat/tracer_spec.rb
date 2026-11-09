require 'rails_helper'

RSpec.describe(Datacat::Tracer) do
  after { Datacat::Tracer.clear }

  describe(".current") do
    it("returns the tracer created on this thread") do
      tracer = Datacat::Tracer.create

      expect(Datacat::Tracer.current).to(be(tracer))
    end

    it("is nil on another thread") do
      Datacat::Tracer.create

      expect(Thread.new { Datacat::Tracer.current }.value).to(be_nil)
    end

    it("is nil after clear") do
      Datacat::Tracer.create
      Datacat::Tracer.clear

      expect(Datacat::Tracer.current).to(be_nil)
    end

    it("returns the newer tracer when one is created over another") do
      Datacat::Tracer.create
      newer = Datacat::Tracer.create

      expect(Datacat::Tracer.current).to(be(newer))
    end
  end

  describe("#open") do
    it("gives the root no parent, and each span the position of the span it opened inside") do
      tracer = Datacat::Tracer.create

      tracer.open('StocksController#buy', 'app')
      tracer.open('MarketService.buy', 'app')
      tracer.open('User Load', 'sql')

      expect(tracer.spans.map { |span| span[:parent] }).to(eq([nil, 0, 1]))
    end

    it("gives a span opened after its sibling closed the same parent as the sibling") do
      tracer = Datacat::Tracer.create

      tracer.open('StocksController#buy', 'app')
      tracer.open('User Load', 'sql')
      tracer.close
      tracer.open('Position Load', 'sql')

      expect(tracer.spans.map { |span| span[:parent] }).to(eq([nil, 0, 0]))
    end
  end

  describe("#wrap_innermost") do
    it("puts the new span between the innermost open span and its parent, starting when that span started") do
      tracer = Datacat::Tracer.create

      tracer.open('MarketService.buy', 'app')
      tracer.open('User Load', 'sql')
      tracer.wrap_innermost('transaction', 'sql')

      expect(tracer.spans.map { |span| span.values_at(:name, :parent) }).to(eq([['MarketService.buy', nil], ['User Load', 2], ['transaction', 0]]))
      expect(tracer.spans[2][:start]).to(eq(tracer.spans[1][:start]))
    end

    it("leaves the stack nested, so the next span goes inside the new one and closes come out in order") do
      tracer = Datacat::Tracer.create

      tracer.open('MarketService.buy', 'app')
      tracer.open('User Load', 'sql')
      tracer.wrap_innermost('transaction', 'sql')

      expect(tracer.close[:name]).to(eq('User Load'))
      tracer.open('Position Load', 'sql')
      expect(tracer.spans.last[:parent]).to(eq(2))
      expect([tracer.close, tracer.close, tracer.close].map { |span| span[:name] }).to(eq(['Position Load', 'transaction', 'MarketService.buy']))
    end
  end

  describe("#innermost") do
    it("is the newest span still open, or nil when none is") do
      tracer = Datacat::Tracer.create

      expect(tracer.innermost).to(be_nil)
      tracer.open('MarketService.buy', 'app')
      tracer.open('User Load', 'sql')
      tracer.close

      expect(tracer.innermost[:name]).to(eq('MarketService.buy'))
    end
  end

  describe("#close") do
    it("closes the innermost open span and returns it") do
      tracer = Datacat::Tracer.create

      tracer.open('StocksController#buy', 'app')
      tracer.open('MarketService.buy', 'app')

      expect(tracer.close[:name]).to(eq('MarketService.buy'))
      expect(tracer.close[:name]).to(eq('StocksController#buy'))
    end

    it("adds the details from its block, worked out after the clock has stopped so they don't count toward the span") do
      allow(Datacat::Tracer).to(receive(:now).and_return(100.0, 100.0, 100.001, 100.005))
      tracer = Datacat::Tracer.create

      tracer.open('TRANSACTION', 'sql')
      tracer.close do
        Datacat::Tracer.now
        { name: 'COMMIT', cached: true }
      end

      expect(tracer.spans.first).to(include(name: 'COMMIT', cached: true, duration: 1.0))
    end

    it("records start and duration in milliseconds from when the trace began") do
      allow(Datacat::Tracer).to(receive(:now).and_return(100.0, 100.001, 100.003, 100.006, 100.010))
      tracer = Datacat::Tracer.create

      tracer.open('StocksController#buy', 'app')
      tracer.open('MarketService.buy', 'app')
      tracer.close
      tracer.close

      expect(tracer.spans.map { |span| span.values_at(:start, :duration) }).to(eq([[1.0, 9.0], [3.0, 3.0]]))
    end
  end

  describe("#self_times") do
    before do
      allow(Datacat::Tracer).to(receive(:now).and_return(100.0, 100.0, 100.001, 100.002, 100.003, 100.004, 100.0045, 100.005, 100.007, 100.0085, 100.0085, 100.0095, 100.010))
    end

    def buy
      tracer = Datacat::Tracer.create

      tracer.open('StocksController#buy', 'app')
      tracer.open('before_action', 'callbacks')
      tracer.open('GET user_?', 'redis')
      tracer.close
      tracer.close
      tracer.open('MarketService.buy', 'app')
      tracer.open('User Load', 'sql')
      tracer.close
      tracer.close
      tracer.open('render json', 'render')
      tracer.close
      tracer.close
      tracer
    end

    it("gives each category its spans' durations minus their direct children's") do
      expect(buy.self_times).to(eq('app' => 4.0, 'callbacks' => 2.0, 'redis' => 1.0, 'sql' => 2.0, 'render' => 1.0))
    end

    it("adds up to the root's duration, so every millisecond is counted once") do
      tracer = buy

      expect(tracer.self_times.values.sum).to(eq(tracer.spans.first[:duration]))
    end
  end

  describe("#self_times with a transaction") do
    before do
      allow(Datacat::Tracer).to(receive(:now).and_return(100.0, 100.0, 100.001, 100.002, 100.0025, 100.003, 100.004, 100.006, 100.010))
    end

    it("counts the transaction's own time as app, but the first query's own time as sql though BEGIN is inside it") do
      tracer = Datacat::Tracer.create

      tracer.open('MarketService.buy', 'app')
      tracer.open('transaction', 'sql')
      tracer.open('User Load', 'sql')
      tracer.open('BEGIN', 'sql')
      tracer.close
      tracer.close
      tracer.close
      tracer.close

      expect(tracer.self_times).to(eq('app' => 8.0, 'sql' => 2.0))
    end
  end
end
