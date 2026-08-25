module Types
  class QueryType < Types::BaseObject

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
      argument(:user_id, ID)
      description('every request made by one run, in the order it made them')
    end
    
    field(:ingester_spans, [Types::IngesterSpanType], null: false) do
      argument(:hours, Integer, required: false, default_value: 24)
      description('ingester state timeline')
    end

    field(:ingester_boots, [Types::IngesterBootType], null: false) do
      argument(:hours, Integer, required: false, default_value: 24)
      description('one row per process lifetime')
    end

    field(:ingester_connections, [Types::IngesterConnectionType], null: false, connection: false) do
      argument(:hours, Integer, required: false, default_value: 24)
      description('one row per websocket connection')
    end

    field(:ingester_rate, [Types::IngesterRatePointType], null: false) do
      argument(:hours, Integer, required: false, default_value: 24)
      description('events and frames per second between consecutive samples')
    end

    field(:ingester_uptime, Types::IngesterUptimeType, null: false) do
      argument(:hours, Integer, required: false, default_value: 24)
      description('streaming / idle / down totals for the window')
    end

    field(:ingester_causes, [Types::IngesterCauseType], null: false) do
      argument(:hours, Integer, required: false, default_value: 24)
      description('reconnect counts grouped by terminal cause')
    end
    
    field :ingester_lag, [Types::IngesterLagPointType], null: false do
      argument :hours, Integer, required: false, default_value: 24
    end
    
    field :ingester_transitions, [Types::IngesterTransitionType], null: false do
      argument :hours, Integer, required: false, default_value: 24
      description('boot, spawn and teardown events, with their detail payload')
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

    def synthetic_run_traces(user_id:)
      Trace.run_traces(user_id: user_id)
    end

    def ingester_spans(hours:)
      from, to = ingester_window(hours)
      IngesterSample.spans(from: from, to: to)
    end

    def ingester_boots(hours:)
      from, to = ingester_window(hours)
      IngesterSample.boots(from: from, to: to)
    end

    def ingester_connections(hours:)
      from, to = ingester_window(hours)
      IngesterSample.connections(from: from, to: to)
    end

    def ingester_rate(hours:)
      from, to = ingester_window(hours)
      IngesterSample.rate(from: from, to: to)
    end

    def ingester_uptime(hours:)
      from, to = ingester_window(hours)
      IngesterSample.uptime(from: from, to: to)
    end

    def ingester_causes(hours:)
      from, to = ingester_window(hours)
      IngesterSample.reconnect_causes(from: from, to: to)
    end
    
    def ingester_lag(hours:)
      from, to = ingester_window(hours)
      IngesterSample.lag(from: from, to: to)
    end

    def ingester_transitions(hours:)
      from, to = ingester_window(hours)
      IngesterSample.transitions(from: from, to: to)
    end

    private
    
    def ingester_window(hours)
      to = Time.current
      [to - hours.clamp(1, 720).hours, to]
    end
  end
end