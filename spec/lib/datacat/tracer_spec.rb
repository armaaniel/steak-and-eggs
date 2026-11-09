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

  describe("#close") do
    it("closes the innermost open span and returns it") do
      tracer = Datacat::Tracer.create

      tracer.open('StocksController#buy', 'app')
      tracer.open('MarketService.buy', 'app')

      expect(tracer.close[:name]).to(eq('MarketService.buy'))
      expect(tracer.close[:name]).to(eq('StocksController#buy'))
    end

    it("records start and duration in milliseconds from when the trace began") do
      allow(Process).to(receive(:clock_gettime).and_return(100.0, 100.001, 100.003, 100.006, 100.010))
      tracer = Datacat::Tracer.create

      tracer.open('StocksController#buy', 'app')
      tracer.open('MarketService.buy', 'app')
      tracer.close
      tracer.close

      expect(tracer.spans.map { |span| span.values_at(:start, :duration) }).to(eq([[1.0, 9.0], [3.0, 3.0]]))
    end
  end
end
