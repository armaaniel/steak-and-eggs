module Types
  class QueryType < Types::BaseObject
    INGESTER_MAX_WINDOW = 30.days

    field(:trace_summary, [Types::TraceSummaryType]) do
      description('fetch trace data by routes')
    end

    field(:trace_list, [Types::TraceType]) do
      argument(:endpoint, String)
      description('fetch trace list by route')
    end

    field(:trace_breakdown, Types::TraceBreakdownType) do
      argument(:endpoint, String)
      description('fetch trace list breakdown')
    end

    field(:latent_traces, [Types::TraceType]) do
      description('fetch most latent traces')
    end

    field(:connections, [Types::ConnectionsType], null:false) do
      description('fetch active connections')
    end

    field(:trace_stats, Types::TraceStatsType) do
      argument(:endpoint, String)
      description('fetch trace statistics')
    end
    
    field(:synthetic_buckets, [Types::SyntheticBucketType]) do
      argument(:range, String, required: false, default_value: '1h')
      description('probe runs per time bucket')
    end
    
    field(:synthetic_runs, [Types::SyntheticRunType]) do
      argument(:range, String, required: false, default_value: '1h')
      argument(:bucket, GraphQL::Types::ISO8601DateTime)
      description('get individual runs by time bucket')
    end
    
    field(:synthetic_run_traces, [Types::TraceType]) do
      argument(:run_id, ID)
      description('every request made by one run, in the order it made them')
    end
    
    field(:ingester_spans, [Types::IngesterSpanType], null: false) do
      argument(:from, GraphQL::Types::ISO8601DateTime)
      argument(:to, GraphQL::Types::ISO8601DateTime)
      description('ingester state timeline')
    end

    field(:ingester_boots, [Types::IngesterBootType], null: false) do
      argument(:from, GraphQL::Types::ISO8601DateTime)
      argument(:to, GraphQL::Types::ISO8601DateTime)
      description('one row per process lifetime')
    end

    field(:ingester_connections, [Types::IngesterConnectionType], null: false, connection: false) do
      argument(:from, GraphQL::Types::ISO8601DateTime)
      argument(:to, GraphQL::Types::ISO8601DateTime)
      description('one row per websocket connection')
    end

    field(:ingester_rate, [Types::IngesterRatePointType], null: false) do
      argument(:from, GraphQL::Types::ISO8601DateTime)
      argument(:to, GraphQL::Types::ISO8601DateTime)
      description('events and frames per second between consecutive samples')
    end

    field(:ingester_uptime, Types::IngesterUptimeType, null: false) do
      argument(:from, GraphQL::Types::ISO8601DateTime)
      argument(:to, GraphQL::Types::ISO8601DateTime)
      description('streaming / idle / down totals for the window')
    end

    field :ingester_lag, [Types::IngesterLagPointType], null: false do
      argument :from, GraphQL::Types::ISO8601DateTime
      argument :to, GraphQL::Types::ISO8601DateTime
    end
    
    field :ingester_transitions, [Types::IngesterTransitionType], null: false do
      argument :from, GraphQL::Types::ISO8601DateTime
      argument :to, GraphQL::Types::ISO8601DateTime
      description('boot, spawn and teardown events, with their detail payload')
    end

    field(:load_runs, [Types::LoadRunType], null: false) do
      argument(:limit, Integer, required: false, default_value: 25)
      description('load generator runs, newest first, one row per run and route')
    end

    field(:load_compare, [Types::LoadCompareRowType], null: false) do
      argument(:run_id, ID)
      argument(:route, String)
      argument(:step, Integer, required: false, default_value: 15)
      description('what the generator sent against what the app traced, per bucket')
    end

    field(:run_metrics, [Types::RunMetricType], null: false) do
      argument(:run_id, ID)
      argument(:metric, String, required: false, default_value: 'cpu')
      description('infrastructure metric over the window of one run')
    end
    
    def connections
      ActionCable.server.connections.map do |connection|
        {
          started_at: connection.instance_variable_get(:@started_at),
          connection_state: connection.instance_variable_get(:@websocket)&.alive?,
          subscriptions: connection.subscriptions.identifiers.map do |identifier|
            JSON.parse(identifier, symbolize_names: true)
          end
        }
      end
    end

    def trace_breakdown(endpoint:)
      Trace.breakdown(endpoint: endpoint)
    end

    def trace_list(endpoint:)
      Trace.list(endpoint: endpoint)
    end

    def trace_stats(endpoint:)
      Trace.stats(endpoint: endpoint)
    end

    def latent_traces
      Trace.latent
    end

    def trace_summary
      Trace.summary
    end

    def synthetic_buckets(range: '1h')
      Trace.synthetic_buckets(range: range)
    end

    def synthetic_runs(bucket:, range: '1h')
      Trace.synthetic_runs(bucket: bucket, range: range)
    end

    def synthetic_run_traces(run_id:)
      Trace.run_traces(run_id: run_id)
    end

    def ingester_spans(from:, to:)
      from, to = ingester_window(from, to)
      IngesterSample.spans(from: from, to: to)
    end

    def ingester_boots(from:, to:)
      from, to = ingester_window(from, to)
      IngesterSample.boots(from: from, to: to)
    end

    def ingester_connections(from:, to:)
      from, to = ingester_window(from, to)
      IngesterSample.connections(from: from, to: to)
    end

    def ingester_rate(from:, to:)
      from, to = ingester_window(from, to)
      IngesterSample.rate(from: from, to: to)
    end

    def ingester_uptime(from:, to:)
      from, to = ingester_window(from, to)
      IngesterSample.uptime(from: from, to: to)
    end

    def ingester_lag(from:, to:)
      from, to = ingester_window(from, to)
      IngesterSample.lag(from: from, to: to)
    end

    def ingester_transitions(from:, to:)
      from, to = ingester_window(from, to)
      IngesterSample.transitions(from: from, to: to)
    end

    def load_runs(limit:)
      LoadSample.runs(limit: limit.clamp(1, 200))
    end

    def load_compare(run_id:, route:, step:)
      LoadSample.compare(run_id: run_id, route: route, step: step.clamp(1, 300))
    end

    def run_metrics(run_id:, metric:)
      MetricService.for_run(run_id: run_id, metric: metric)
    end

    private
    
    def ingester_window(from, to)
      raise(GraphQL::ExecutionError, 'from must be earlier than to') if from >= to

      [[from, to - INGESTER_MAX_WINDOW].max, to]
    end
  end
end