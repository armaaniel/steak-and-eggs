module Datacat
  class Tracer
    STORED_SPANS = 500

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

    def self.now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def initialize
      @started = Tracer.now
      @spans = []
      @open = []
      @breakdown = {}
    end

    def open(name, category)
      span = { name: name, category: category, start: elapsed, parent: @open.last }
      @open.push(@spans.size)
      @spans.push(span)
    end

    def wrap_innermost(name, category)
      inner = @open.pop
      @spans.push({ name: name, category: category, start: @spans[inner][:start], parent: @spans[inner][:parent] })
      @spans[inner][:parent] = @spans.size - 1
      @open.push(@spans.size - 1, inner)
    end

    def innermost
      @spans[@open.last] if @open.any?
    end

    def close
      span = @spans[@open.pop]
      span[:duration] = (elapsed - span[:start]).round(2)
      span.merge!(yield) if block_given?
      span
    end

    def balanced?
      @open == [0]
    end

    def close_root
      close while @open.size > 1
      @open.clear
      root = @spans.first
      root[:duration] = (elapsed - root[:start]).round(2)
      root
    end

    def self_times
      children = Hash.new(0.0)
      @spans.each { |span| children[span[:parent]] += span[:duration] if span[:parent] }

      totals = Hash.new(0.0)
      @spans.each_with_index do |span, position|
        category = span[:name] == 'transaction' ? 'app' : span[:category]
        totals[category] += span[:duration] - children[position]
      end
      totals.transform_values { |ms| ms.round(2) }
    end

    def stored_spans
      return @spans if @spans.size <= STORED_SPANS

      kept = @spans.first(STORED_SPANS).map(&:dup)
      kept.each do |span|
        span[:parent] = @spans[span[:parent]][:parent] while span[:parent] && span[:parent] >= STORED_SPANS
      end
      kept.first[:dropped] = @spans.size - STORED_SPANS
      kept
    end

    def cache_counts(excluding:)
      lookups = @spans.reject { |span| span[:hit].nil? || inside?(span, excluding) }
      [lookups.count { |span| span[:hit] }, lookups.count { |span| !span[:hit] }]
    end

    private

    def elapsed
      ((Tracer.now - @started) * 1000).round(2)
    end

    def inside?(span, category)
      parent = span[:parent]

      while parent
        return true if @spans[parent][:category] == category
        parent = @spans[parent][:parent]
      end

      false
    end
  end
end
