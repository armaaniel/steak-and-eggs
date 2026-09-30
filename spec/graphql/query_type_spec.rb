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

    it("leaves out DataCat's own queries") do
      Trace.create!(endpoint: "POST /graphql", duration: 500.0, status: 200)

      result = execute_query

      expect(result.dig("data", "traceSummary")).to(eq([]))
    end

    it("only counts traces inside the range when one is given") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200, created_at: 3.hours.ago)
      Trace.create!(endpoint: "GET /users", duration: 60.0, status: 200)

      result = SteakAndEggsSchema.execute('{ traceSummary(range: "1h") { route totalRequests } }').to_h

      expect(result.dig("data", "traceSummary", 0, "totalRequests")).to(eq(1))
    end

    it("counts user and canary traffic but not load tests") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200, source: "user")
      Trace.create!(endpoint: "GET /users", duration: 60.0, status: 200, source: "canary")
      Trace.create!(endpoint: "GET /users", duration: 70.0, status: 200, source: "load")
      Trace.create!(endpoint: "GET /users", duration: 80.0, status: 200, source: "unknown")

      result = execute_query
      summary = result.dig("data", "traceSummary")

      expect(summary[0]["totalRequests"]).to(eq(2))
    end

    it("normalizes parameterized stock endpoints into grouped routes") do
      Trace.create!(endpoint: "GET /stocks/TSLA/marketdata", duration: 30.0, status: 200)
      Trace.create!(endpoint: "GET /stocks/AAPL/marketdata", duration: 40.0, status: 200)
      Trace.create!(endpoint: "GET /stocks/GOOG/companydata", duration: 50.0, status: 200)

      result = execute_query
      summary = result.dig("data", "traceSummary")
      routes = summary.map { |s| s["route"] }

      expect(routes).to(include("GET /stocks/symbol/marketdata"))
      expect(routes).to(include("GET /stocks/symbol/companydata"))
      expect(routes).not_to(include("GET /stocks/TSLA/marketdata"))
    end

    it("aggregates total_requests across parameterized routes") do
      3.times { Trace.create!(endpoint: "GET /stocks/TSLA/marketdata", duration: 30.0, status: 200) }
      2.times { Trace.create!(endpoint: "GET /stocks/AAPL/marketdata", duration: 40.0, status: 200) }

      result = execute_query
      summary = result.dig("data", "traceSummary")
      marketdata = summary.find { |s| s["route"] == "GET /stocks/symbol/marketdata" }

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

    it("only returns traces inside the range when one is given") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200, created_at: 3.hours.ago)
      Trace.create!(endpoint: "GET /users", duration: 60.0, status: 200)

      result = SteakAndEggsSchema.execute('{ traceList(endpoint: "GET /users", range: "1h") { duration } }').to_h

      expect(result.dig("data", "traceList").map { |t| t["duration"] }).to(eq([60.0]))
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

    it("includes user and canary traffic but not load tests") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200, source: "user")
      Trace.create!(endpoint: "GET /users", duration: 60.0, status: 200, source: "canary")
      Trace.create!(endpoint: "GET /users", duration: 70.0, status: 200, source: "load")

      result = execute_query(endpoint: "GET /users")
      traces = result.dig("data", "traceList")

      expect(traces.map { |t| t["duration"] }).to(contain_exactly(50.0, 60.0))
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

    it("returns an empty array when no traces match") do
      result = execute_query(endpoint: "GET /nonexistent")
      traces = result.dig("data", "traceList")

      expect(traces).to(eq([]))
    end
  end

  describe("cache_split") do
    let(:query) do
      <<~GQL
        query($endpoint: String!) {
          cacheSplit(endpoint: $endpoint) {
            cached {
              id
              endpoint
              breakdown
            }
            uncached {
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

    it("only splits traces inside the range when one is given") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200, breakdown: { "Ticker.query" => { "used_redis" => true } }, created_at: 3.hours.ago)
      Trace.create!(endpoint: "GET /users", duration: 60.0, status: 200, breakdown: { "Ticker.query" => { "used_redis" => true } })

      result = SteakAndEggsSchema.execute('{ cacheSplit(endpoint: "GET /users", range: "1h") { cached { duration } } }').to_h

      expect(result.dig("data", "cacheSplit", "cached").map { |t| t["duration"] }).to(eq([60.0]))
    end

    it("returns cache hits in cached") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200,
        breakdown: { used_redis: true })
      Trace.create!(endpoint: "GET /users", duration: 60.0, status: 200,
        breakdown: { used_redis: false, used_db: true })

      result = execute_query(endpoint: "GET /users")
      redis = result.dig("data", "cacheSplit", "cached")

      expect(redis.length).to(eq(1))
    end

    it("returns cache misses in uncached") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200,
        breakdown: { used_db: true })
      Trace.create!(endpoint: "GET /users", duration: 60.0, status: 200,
        breakdown: { used_api: true })
      Trace.create!(endpoint: "GET /users", duration: 70.0, status: 200,
        breakdown: { used_redis: true })

      result = execute_query(endpoint: "GET /users")
      db_api = result.dig("data", "cacheSplit", "uncached")

      expect(db_api.length).to(eq(2))
    end

    it("excludes traces with empty or null breakdown") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200, breakdown: {})
      Trace.create!(endpoint: "GET /users", duration: 60.0, status: 200, breakdown: nil)
      Trace.create!(endpoint: "GET /users", duration: 70.0, status: 200,
        breakdown: { used_redis: true })

      result = execute_query(endpoint: "GET /users")
      redis = result.dig("data", "cacheSplit", "cached")
      db_api = result.dig("data", "cacheSplit", "uncached")

      expect(redis.length).to(eq(1))
      expect(db_api).to(eq([]))
    end

    it("normalizes parameterized endpoints") do
      Trace.create!(endpoint: "GET /stocks/TSLA/marketdata", duration: 30.0, status: 200,
        breakdown: { used_redis: true })

      result = execute_query(endpoint: "GET /stocks/symbol/marketdata")
      redis = result.dig("data", "cacheSplit", "cached")

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
            usedRedis
            usedApi
          }
        }
      GQL
    end

    def execute_query(endpoint:)
      SteakAndEggsSchema.execute(query, variables: { endpoint: endpoint }).to_h
    end

    it("only counts traces inside the range when one is given") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200, created_at: 3.hours.ago)
      Trace.create!(endpoint: "GET /users", duration: 60.0, status: 200)

      result = SteakAndEggsSchema.execute('{ traceStats(endpoint: "GET /users", range: "1h") { totalRequests p99 } }').to_h

      expect(result.dig("data", "traceStats", "totalRequests")).to(eq(1))
      expect(result.dig("data", "traceStats", "p99")).to(eq(60.0))
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

    it("computes error_rate from status >= 500") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200)
      Trace.create!(endpoint: "GET /users", duration: 60.0, status: 500)
      Trace.create!(endpoint: "GET /users", duration: 70.0, status: 404)
      Trace.create!(endpoint: "GET /users", duration: 80.0, status: 200)

      result = execute_query(endpoint: "GET /users")
      stats = result.dig("data", "traceStats")

      expect(stats["errorRate"]).to(eq(25.0))
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

    it("flags used_redis when a nested breakdown records the key") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200,
        breakdown: { "PositionService#find_positions" => { used_redis: false, used_db: true } })

      result = execute_query(endpoint: "GET /users")
      stats = result.dig("data", "traceStats")

      expect(stats["usedRedis"]).to(be(true))
      expect(stats["usedApi"]).to(be(false))
    end

    it("flags used_api when a nested breakdown records the key") do
      Trace.create!(endpoint: "GET /stocks/TSLA/marketdata", duration: 30.0, status: 200,
        breakdown: { "MarketService#quote" => { used_redis: true, used_api: false } })

      result = execute_query(endpoint: "GET /stocks/symbol/marketdata")
      stats = result.dig("data", "traceStats")

      expect(stats["usedRedis"]).to(be(true))
      expect(stats["usedApi"]).to(be(true))
    end

    it("does not flag used_redis for a route with no cache instrumentation") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200,
        breakdown: { "UserService#index" => { used_db: true } })

      result = execute_query(endpoint: "GET /users")
      stats = result.dig("data", "traceStats")

      expect(stats["usedRedis"]).to(be(false))
      expect(stats["usedApi"]).to(be(false))
    end

    it("flags used_redis when any trace on the route records the key") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200)
      Trace.create!(endpoint: "GET /users", duration: 60.0, status: 200,
        breakdown: { "PositionService#find_positions" => { used_redis: true } })

      result = execute_query(endpoint: "GET /users")
      stats = result.dig("data", "traceStats")

      expect(stats["usedRedis"]).to(be(true))
    end

    it("returns false flags when no traces match") do
      result = execute_query(endpoint: "GET /nonexistent")
      stats = result.dig("data", "traceStats")

      expect(stats["usedRedis"]).to(be(false))
      expect(stats["usedApi"]).to(be(false))
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

    it("only returns traces inside the range when one is given") do
      Trace.create!(endpoint: "POST /signup", duration: 900.0, status: 200, created_at: 3.hours.ago)
      Trace.create!(endpoint: "POST /signup", duration: 300.0, status: 200)

      result = SteakAndEggsSchema.execute('{ latentTraces(range: "1h") { duration } }').to_h

      expect(result.dig("data", "latentTraces").map { |t| t["duration"] }).to(eq([300.0]))
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

    it("excludes POST /graphql endpoints") do
      Trace.create!(endpoint: "POST /graphql", duration: 500.0, status: 200)
      recorded = Trace.create!(endpoint: "POST /record", duration: 400.0, status: 200)
      kept = Trace.create!(endpoint: "GET /users", duration: 100.0, status: 200)

      result = execute_query
      traces = result.dig("data", "latentTraces")

      expect(traces.length).to(eq(2))
      expect(traces[0]["id"].to_i).to(eq(recorded.id))
      expect(traces[1]["id"].to_i).to(eq(kept.id))
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

  describe("canary_slo") do
    let(:query) do
      <<~GQL
        {
          canarySlo(range: "1h") {
            target
            good
            expected
            periodGood
            periodExpected
            budgetAllowed
            budgetUsed
          }
        }
      GQL
    end

    def execute_query
      SteakAndEggsSchema.execute(query).to_h.dig("data", "canarySlo")
    end

    def canary_run(result:, status: 200, at: 20.minutes.ago)
      run_id = SecureRandom.uuid
      Trace.create!(endpoint: "GET /stocks/AAPL/stockprice", duration: 10.0, status: status, source: "canary", run_id: run_id, created_at: at)
      Trace.create!(endpoint: "POST /record", duration: 5.0, status: 200, source: "canary", run_id: run_id, result: result, created_at: at) if result
    end

    it("counts every expected run as bad when no canary runs exist") do
      slo = execute_query

      expect(slo["target"]).to(eq(0.995))
      expect(slo["good"]).to(eq(0))
      expect(slo["expected"]).to(eq(12))
      expect(slo["periodGood"]).to(eq(0))
      expect(slo["periodExpected"]).to(eq(8640))
      expect(slo["budgetAllowed"]).to(eq(43))
      expect(slo["budgetUsed"]).to(eq(8640))
    end

    it("counts a passing run as good in both the range and the budget") do
      canary_run(result: "pass")

      slo = execute_query

      expect(slo["good"]).to(eq(1))
      expect(slo["budgetUsed"]).to(eq(8639))
    end

    it("does not count failed, errored or unfinished runs as good") do
      canary_run(result: "fail")
      canary_run(result: "pass", status: 503)
      canary_run(result: nil)

      slo = execute_query

      expect(slo["good"]).to(eq(0))
      expect(slo["budgetUsed"]).to(eq(8640))
    end

    it("counts a run outside the range toward the budget but not the SLI") do
      canary_run(result: "pass", at: 3.hours.ago)

      slo = execute_query

      expect(slo["good"]).to(eq(0))
      expect(slo["periodGood"]).to(eq(1))
      expect(slo["budgetUsed"]).to(eq(8639))
    end

    it("ignores traces that are not from the canary") do
      Trace.create!(endpoint: "GET /stocks/AAPL/stockprice", duration: 10.0, status: 200, source: "user", run_id: SecureRandom.uuid, result: "pass", created_at: 20.minutes.ago)

      slo = execute_query

      expect(slo["good"]).to(eq(0))
    end
  end

  describe("service_timeseries") do
    let(:query) do
      <<~GQL
        {
          serviceTimeseries(range: "1h") {
            bucket
            requests
            errors
            p50
            p95
            p99
          }
        }
      GQL
    end

    def execute_query
      SteakAndEggsSchema.execute(query).to_h.dig("data", "serviceTimeseries")
    end

    it("returns one bucket per step across the range, with no percentiles for empty ones") do
      buckets = execute_query

      expect(buckets.length).to(eq(12))
      expect(buckets.map { |b| b["requests"] }.uniq).to(eq([0]))
      expect(buckets.map { |b| b["p99"] }.uniq).to(eq([nil]))
    end

    it("counts requests and errors in the bucket they happened in") do
      Trace.create!(endpoint: "GET /users", duration: 10.0, status: 200, created_at: Time.current)
      Trace.create!(endpoint: "GET /users", duration: 30.0, status: 500, created_at: Time.current)

      current = execute_query.last

      expect(current["requests"]).to(eq(2))
      expect(current["errors"]).to(eq(1))
      expect(current["p50"]).to(eq(10.0))
      expect(current["p99"]).to(eq(30.0))
    end

    it("leaves out DataCat's own queries and load tests") do
      Trace.create!(endpoint: "POST /graphql", duration: 10.0, status: 200, created_at: Time.current)
      Trace.create!(endpoint: "GET /users", duration: 10.0, status: 200, source: "load", created_at: Time.current)

      expect(execute_query.sum { |b| b["requests"] }).to(eq(0))
    end
  end

  describe("dependency_health") do
    let(:query) { '{ dependencyHealth { id configured status readings { key label unit now peak total } } }' }

    it("resolves fresh and cached results the same way") do
      fresh = [{id: "rails", configured: true, status: "good", readings: [{key: "cpu", label: "CPU", unit: "percent", now: 12.0, peak: 30.0, total: nil}]}]
      cached = JSON.parse(fresh.to_json)

      results = [fresh, cached].map do |health|
        allow(DependencyHealthService).to(receive(:current).and_return(health))
        SteakAndEggsSchema.execute(query).to_h.dig("data", "dependencyHealth")
      end

      expect(results[0]).to(eq(results[1]))
      expect(results[0][0]["readings"][0]["peak"]).to(eq(30.0))
    end
  end
end
