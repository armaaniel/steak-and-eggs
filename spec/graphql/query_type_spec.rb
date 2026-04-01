require 'rails_helper'

RSpec.describe(Types::QueryType) do
  describe("trace_summary") do
    let(:query) do
      <<~GQL
        {
          traceSummary {
            route
            cleanRoute
            totalRequests
            p99
            cacheHitRate
          }
        }
      GQL
    end

    def execute_query
      SteakAndEggsSchema.execute(query).to_h
    end

    it("returns an empty array when no traces exist") do
      result = execute_query
      expect(result.dig("data", "traceSummary")).to(eq([]))
    end

    it("returns aggregated trace summary for a single endpoint") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200)
      Trace.create!(endpoint: "GET /users", duration: 100.0, status: 200)
      Trace.create!(endpoint: "GET /users", duration: 150.0, status: 500)

      result = execute_query
      summary = result.dig("data", "traceSummary")

      expect(summary.length).to(eq(1))
      expect(summary[0]["route"]).to(eq("GET /users"))
      expect(summary[0]["cleanRoute"]).to(eq("get/users"))
      expect(summary[0]["totalRequests"]).to(eq(3))
      expect(summary[0]["p99"]).to(be_a(Float))
    end

    it("normalizes parameterized stock endpoints into grouped routes") do
      Trace.create!(endpoint: "GET /stocks/TSLA/marketdata", duration: 30.0, status: 200)
      Trace.create!(endpoint: "GET /stocks/AAPL/marketdata", duration: 40.0, status: 200)
      Trace.create!(endpoint: "GET /stocks/GOOG/companydata", duration: 50.0, status: 200)

      result = execute_query
      summary = result.dig("data", "traceSummary")
      routes = summary.map { |s| s["route"] }

      expect(routes).to(include("GET /stocks/:symbol/marketdata"))
      expect(routes).to(include("GET /stocks/:symbol/companydata"))
      expect(routes).not_to(include("GET /stocks/TSLA/marketdata"))
    end

    it("aggregates total_requests across parameterized routes") do
      3.times { Trace.create!(endpoint: "GET /stocks/TSLA/marketdata", duration: 30.0, status: 200) }
      2.times { Trace.create!(endpoint: "GET /stocks/AAPL/marketdata", duration: 40.0, status: 200) }

      result = execute_query
      summary = result.dig("data", "traceSummary")
      marketdata = summary.find { |s| s["route"] == "GET /stocks/:symbol/marketdata" }

      expect(marketdata["totalRequests"]).to(eq(5))
    end

    it("computes cache_hit_rate from breakdown data") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200,
        breakdown: { used_redis: true })
      Trace.create!(endpoint: "GET /users", duration: 60.0, status: 200,
        breakdown: { used_redis: false })

      result = execute_query
      summary = result.dig("data", "traceSummary")
      users = summary.find { |s| s["route"] == "GET /users" }

      expect(users["cacheHitRate"]).to(eq(50.0))
    end

    it("returns null cache_hit_rate when no breakdown data exists") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200)

      result = execute_query
      summary = result.dig("data", "traceSummary")
      users = summary.find { |s| s["route"] == "GET /users" }

      expect(users["cacheHitRate"]).to(be_nil)
    end

    it("orders results by total_requests descending") do
      5.times { Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200) }
      2.times { Trace.create!(endpoint: "GET /health", duration: 10.0, status: 200) }

      result = execute_query
      summary = result.dig("data", "traceSummary")

      expect(summary[0]["route"]).to(eq("GET /users"))
      expect(summary[1]["route"]).to(eq("GET /health"))
    end
  end

  describe("trace_list") do
    let(:query) do
      <<~GQL
        query($endpoint: String!) {
          traceList(endpoint: $endpoint) {
            id
            endpoint
            duration
            status
            createdAt
          }
        }
      GQL
    end

    def execute_query(endpoint:)
      SteakAndEggsSchema.execute(query, variables: { endpoint: endpoint }).to_h
    end

    it("returns traces matching the endpoint") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200)
      Trace.create!(endpoint: "GET /users", duration: 60.0, status: 200)
      Trace.create!(endpoint: "GET /health", duration: 10.0, status: 200)

      result = execute_query(endpoint: "GET /users")
      traces = result.dig("data", "traceList")

      expect(traces.length).to(eq(2))
      expect(traces.map { |t| t["endpoint"] }.uniq).to(eq(["GET /users"]))
    end

    it("normalizes parameterized stock endpoints") do
      Trace.create!(endpoint: "GET /stocks/TSLA/marketdata", duration: 30.0, status: 200)
      Trace.create!(endpoint: "GET /stocks/AAPL/marketdata", duration: 40.0, status: 200)

      result = execute_query(endpoint: "GET /stocks/symbol/marketdata")
      traces = result.dig("data", "traceList")

      expect(traces.length).to(eq(2))
    end

    it("returns traces ordered by created_at descending") do
      old = Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200, created_at: 2.days.ago)
      recent = Trace.create!(endpoint: "GET /users", duration: 60.0, status: 200, created_at: 1.hour.ago)

      result = execute_query(endpoint: "GET /users")
      traces = result.dig("data", "traceList")

      expect(traces[0]["id"].to_i).to(eq(recent.id))
      expect(traces[1]["id"].to_i).to(eq(old.id))
    end

    it("handles GET /stocks/symbol without matching sub-routes") do
      Trace.create!(endpoint: "GET /stocks/TSLA", duration: 30.0, status: 200)
      Trace.create!(endpoint: "GET /stocks/TSLA/marketdata", duration: 40.0, status: 200)

      result = execute_query(endpoint: "GET /stocks/symbol")
      traces = result.dig("data", "traceList")

      expect(traces.length).to(eq(1))
      expect(traces[0]["endpoint"]).to(eq("GET /stocks/TSLA"))
    end

    it("returns an empty array when no traces match") do
      result = execute_query(endpoint: "GET /nonexistent")
      traces = result.dig("data", "traceList")

      expect(traces).to(eq([]))
    end
  end

  describe("trace_breakdown") do
    let(:query) do
      <<~GQL
        query($endpoint: String!) {
          traceBreakdown(endpoint: $endpoint) {
            redisQuery {
              id
              endpoint
              breakdown
            }
            dbApiQuery {
              id
              endpoint
              breakdown
            }
          }
        }
      GQL
    end

    def execute_query(endpoint:)
      SteakAndEggsSchema.execute(query, variables: { endpoint: endpoint }).to_h
    end

    it("returns redis traces in redisQuery") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200,
        breakdown: { used_redis: true })
      Trace.create!(endpoint: "GET /users", duration: 60.0, status: 200,
        breakdown: { used_redis: false, used_db: true })

      result = execute_query(endpoint: "GET /users")
      redis = result.dig("data", "traceBreakdown", "redisQuery")

      expect(redis.length).to(eq(1))
    end

    it("returns db/api traces in dbApiQuery") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200,
        breakdown: { used_db: true })
      Trace.create!(endpoint: "GET /users", duration: 60.0, status: 200,
        breakdown: { used_api: true })
      Trace.create!(endpoint: "GET /users", duration: 70.0, status: 200,
        breakdown: { used_redis: true })

      result = execute_query(endpoint: "GET /users")
      db_api = result.dig("data", "traceBreakdown", "dbApiQuery")

      expect(db_api.length).to(eq(2))
    end

    it("excludes traces with empty or null breakdown") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200, breakdown: {})
      Trace.create!(endpoint: "GET /users", duration: 60.0, status: 200, breakdown: nil)
      Trace.create!(endpoint: "GET /users", duration: 70.0, status: 200,
        breakdown: { used_redis: true })

      result = execute_query(endpoint: "GET /users")
      redis = result.dig("data", "traceBreakdown", "redisQuery")
      db_api = result.dig("data", "traceBreakdown", "dbApiQuery")

      expect(redis.length).to(eq(1))
      expect(db_api).to(eq([]))
    end

    it("normalizes parameterized endpoints") do
      Trace.create!(endpoint: "GET /stocks/TSLA/marketdata", duration: 30.0, status: 200,
        breakdown: { used_redis: true })

      result = execute_query(endpoint: "GET /stocks/symbol/marketdata")
      redis = result.dig("data", "traceBreakdown", "redisQuery")

      expect(redis.length).to(eq(1))
    end
  end

  describe("trace_stats") do
    let(:query) do
      <<~GQL
        query($endpoint: String!) {
          traceStats(endpoint: $endpoint) {
            totalRequests
            p50
            p95
            p99
            errorRate
          }
        }
      GQL
    end

    def execute_query(endpoint:)
      SteakAndEggsSchema.execute(query, variables: { endpoint: endpoint }).to_h
    end

    it("returns stats for a given endpoint") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200)
      Trace.create!(endpoint: "GET /users", duration: 100.0, status: 200)
      Trace.create!(endpoint: "GET /users", duration: 150.0, status: 200)

      result = execute_query(endpoint: "GET /users")
      stats = result.dig("data", "traceStats")

      expect(stats["totalRequests"]).to(eq(3))
      expect(stats["p50"]).to(be_a(Float))
      expect(stats["p95"]).to(be_a(Float))
      expect(stats["p99"]).to(be_a(Float))
    end

    it("computes error_rate from status >= 400") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200)
      Trace.create!(endpoint: "GET /users", duration: 60.0, status: 500)
      Trace.create!(endpoint: "GET /users", duration: 70.0, status: 404)
      Trace.create!(endpoint: "GET /users", duration: 80.0, status: 200)

      result = execute_query(endpoint: "GET /users")
      stats = result.dig("data", "traceStats")

      expect(stats["errorRate"]).to(eq(50.0))
    end

    it("returns zero error_rate when all requests succeed") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200)
      Trace.create!(endpoint: "GET /users", duration: 60.0, status: 201)

      result = execute_query(endpoint: "GET /users")
      stats = result.dig("data", "traceStats")

      expect(stats["errorRate"]).to(eq(0.0))
    end

    it("returns zero values when no traces match") do
      result = execute_query(endpoint: "GET /nonexistent")
      stats = result.dig("data", "traceStats")

      expect(stats["totalRequests"]).to(eq(0))
      expect(stats["errorRate"]).to(eq(0.0))
    end

    it("normalizes parameterized stock endpoints") do
      Trace.create!(endpoint: "GET /stocks/TSLA/marketdata", duration: 30.0, status: 200)
      Trace.create!(endpoint: "GET /stocks/AAPL/marketdata", duration: 40.0, status: 200)

      result = execute_query(endpoint: "GET /stocks/symbol/marketdata")
      stats = result.dig("data", "traceStats")

      expect(stats["totalRequests"]).to(eq(2))
    end
  end

  describe("latent_traces") do
    let(:query) do
      <<~GQL
        {
          latentTraces {
            id
            endpoint
            duration
            status
          }
        }
      GQL
    end

    def execute_query
      SteakAndEggsSchema.execute(query).to_h
    end

    it("returns traces ordered by duration descending") do
      slow = Trace.create!(endpoint: "GET /users", duration: 500.0, status: 200)
      fast = Trace.create!(endpoint: "GET /health", duration: 10.0, status: 200)
      medium = Trace.create!(endpoint: "GET /stocks", duration: 100.0, status: 200)

      result = execute_query
      traces = result.dig("data", "latentTraces")

      expect(traces[0]["id"].to_i).to(eq(slow.id))
      expect(traces[1]["id"].to_i).to(eq(medium.id))
      expect(traces[2]["id"].to_i).to(eq(fast.id))
    end

    it("excludes POST /graphql and POST /record endpoints") do
      Trace.create!(endpoint: "POST /graphql", duration: 500.0, status: 200)
      Trace.create!(endpoint: "POST /record", duration: 400.0, status: 200)
      kept = Trace.create!(endpoint: "GET /users", duration: 100.0, status: 200)

      result = execute_query
      traces = result.dig("data", "latentTraces")

      expect(traces.length).to(eq(1))
      expect(traces[0]["id"].to_i).to(eq(kept.id))
    end

    it("limits results to 1000") do
      1001.times { |i| Trace.create!(endpoint: "GET /users", duration: i.to_f, status: 200) }

      result = execute_query
      traces = result.dig("data", "latentTraces")

      expect(traces.length).to(eq(1000))
    end
  end

  describe("connections") do
    let(:query) do
      <<~GQL
        {
          connections {
            startedAt
            connectionState
          }
        }
      GQL
    end

    def execute_query
      SteakAndEggsSchema.execute(query).to_h
    end

    it("returns an empty array when no connections exist") do
      allow(ActionCable.server).to(receive(:connections).and_return([]))

      result = execute_query
      connections = result.dig("data", "connections")

      expect(connections).to(eq([]))
    end

    it("returns connection details") do
      started = Time.current
      connection = double("connection")
      subscriptions = double("subscriptions", identifiers: [])
      allow(connection).to(receive(:instance_variable_get).with(:@started_at).and_return(started))
      allow(connection).to(receive(:instance_variable_get).with(:@websocket).and_return(double(alive?: true)))
      allow(connection).to(receive(:subscriptions).and_return(subscriptions))
      allow(ActionCable.server).to(receive(:connections).and_return([connection]))

      result = execute_query
      connections = result.dig("data", "connections")

      expect(connections.length).to(eq(1))
      expect(connections[0]["connectionState"]).to(eq("true"))
      expect(connections[0]["startedAt"]).to(be_present)
    end
  end
end
