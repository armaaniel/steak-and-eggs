module Datacat
  class Tracer
    attr_reader :spans, :breakdown

    def self.current
      ActiveSupport::IsolatedExecutionState[:datacat_tracer]
    end

    def self.create
      ActiveSupport::IsolatedExecutionState[:datacat_tracer] = new
    end

    def self.clear
      ActiveSupport::IsolatedExecutionState.delete(:datacat_tracer)
    end

    def initialize
      @started = now
      @spans = []
      @open = []
      @breakdown = {}
    end

    def open(name, category)
      span = { name: name, category: category, start: elapsed, parent: @open.last }
      @open.push(@spans.size)
      @spans.push(span)
    end

    def close
      span = @spans[@open.pop]
      span[:duration] = (elapsed - span[:start]).round(2)
      span
    end

    def self_times
      children = Hash.new(0.0)
      @spans.each { |span| children[span[:parent]] += span[:duration] if span[:parent] }

      totals = Hash.new(0.0)
      @spans.each_with_index { |span, position| totals[span[:category]] += span[:duration] - children[position] }
      totals.transform_values { |ms| ms.round(2) }
    end

    private

    def elapsed
      ((now - @started) * 1000).round(2)
    end

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
