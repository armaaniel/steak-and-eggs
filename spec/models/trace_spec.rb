require 'rails_helper'

RSpec.describe(Trace) do
  describe("the user and canary covering index") do
    let(:connection) { Trace.connection }

    before do
      connection.execute("DROP INDEX index_traces_on_source_and_created_at")
      %w[enable_seqscan enable_bitmapscan].each { |setting| connection.execute("SET LOCAL #{setting} = off") }
      connection.execute("SET LOCAL plan_cache_mode = force_generic_plan")
    end

    def last_traces_query(&block)
      events = []
      record = ->(*, payload) { events << payload if payload[:sql].match?(/FROM "?traces"?/) }
      ActiveSupport::Notifications.subscribed(record, 'sql.active_record', &block)
      events.last
    end

    def generic_plan(event)
      values = event[:type_casted_binds]
      values = values.call if values.respond_to?(:call)
      arguments = values.empty? ? '' : "(#{values.map { |value| connection.quote(value) }.join(', ')})"

      connection.execute("PREPARE traces_query AS #{event[:sql]}")
      connection.select_values("EXPLAIN EXECUTE traces_query#{arguments}").join("\n")
    ensure
      connection.execute("DEALLOCATE traces_query")
    end

    {
      'summary' => -> { Trace.summary(range: '30d') },
      'the service timeseries' => -> { Trace.service_timeseries(range: '30d') },
      'one route\'s timeseries with filters' => -> { Trace.service_timeseries(range: '30d', endpoint: 'GET /portfoliodata', status: 500, cache: 'cached') },
      'route stats' => -> { Trace.stats(endpoint: 'GET /portfoliodata', range: '30d', status: 200, cache: 'uncached') },
      'the scatter' => -> { Trace.scatter(endpoint: 'GET /portfoliodata', range: '30d') },
      'a route\'s list by duration' => -> { Trace.list(endpoint: 'GET /portfoliodata', range: '30d', sort: 'duration').load },
      'every route\'s list, oldest first, with filters' => -> { Trace.list(range: '7d', sort: 'created_at', direction: 'asc', status: 200, cache: 'cached').load }
    }.each do |name, query|
      it("reads #{name} from the index alone, even as a reused prepared statement") do
        plan = generic_plan(last_traces_query(&query))

        expect(plan).to(include('Index Only Scan using index_traces_on_created_at_user_canary'))
      end
    end
  end
end
