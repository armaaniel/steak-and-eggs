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

    it("only returns traces inside the bucket when one is given, ignoring the range") do
      Trace.create!(endpoint: "GET /users", duration: 100.0, status: 200, created_at: Time.utc(2026, 9, 30, 10, 59, 59))
      Trace.create!(endpoint: "GET /users", duration: 200.0, status: 200, created_at: Time.utc(2026, 9, 30, 11, 0))
      Trace.create!(endpoint: "GET /users", duration: 300.0, status: 200, created_at: Time.utc(2026, 9, 30, 11, 59, 59))
      Trace.create!(endpoint: "GET /users", duration: 400.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 0))

      result = SteakAndEggsSchema.execute('{ traceList(endpoint: "GET /users", range: "1h", bucket: "2026-09-30T11:00:00Z", bucketEnd: "2026-09-30T12:00:00Z") { duration } }').to_h

      expect(result.dig("data", "traceList").map { |t| t["duration"] }).to(eq([300.0, 200.0]))
    end

    it("limits results to 1000") do
      1001.times { Trace.create!(endpoint: "GET /users", duration: 10.0, status: 200) }

      expect(execute_query(endpoint: "GET /users").dig("data", "traceList").length).to(eq(1000))
    end

    it("returns the newest traces first across every route when no endpoint is given") do
      oldest = Trace.create!(endpoint: "GET /users", duration: 500.0, status: 200, created_at: 3.minutes.ago)
      newest = Trace.create!(endpoint: "GET /health", duration: 10.0, status: 200, created_at: 1.minute.ago)
      middle = Trace.create!(endpoint: "GET /stocks", duration: 100.0, status: 200, created_at: 2.minutes.ago)

      result = SteakAndEggsSchema.execute('{ traceList { id } }').to_h

      expect(result.dig("data", "traceList").map { |t| t["id"].to_i }).to(eq([newest.id, middle.id, oldest.id]))
    end

    it("returns every route but POST /graphql when no endpoint is given") do
      Trace.create!(endpoint: "GET /users", duration: 10.0, status: 200)
      Trace.create!(endpoint: "GET /health", duration: 20.0, status: 200)
      Trace.create!(endpoint: "POST /graphql", duration: 30.0, status: 200)

      result = SteakAndEggsSchema.execute('{ traceList { endpoint } }').to_h

      expect(result.dig("data", "traceList").map { |t| t["endpoint"] }).to(contain_exactly("GET /users", "GET /health"))
    end

    it("only returns traces with the status when one is given") do
      Trace.create!(endpoint: "GET /users", duration: 10.0, status: 200)
      Trace.create!(endpoint: "GET /users", duration: 20.0, status: 500)

      result = SteakAndEggsSchema.execute('{ traceList(endpoint: "GET /users", status: 500) { duration } }').to_h

      expect(result.dig("data", "traceList").map { |t| t["duration"] }).to(eq([20.0]))
    end

    it("sorts by duration in either direction") do
      Trace.create!(endpoint: "GET /users", duration: 20.0, status: 200)
      Trace.create!(endpoint: "GET /users", duration: 30.0, status: 200)
      Trace.create!(endpoint: "GET /users", duration: 10.0, status: 200)

      slowest = SteakAndEggsSchema.execute('{ traceList(endpoint: "GET /users", sort: DURATION, direction: DESC) { duration } }').to_h
      fastest = SteakAndEggsSchema.execute('{ traceList(endpoint: "GET /users", sort: DURATION, direction: ASC) { duration } }').to_h

      expect(slowest.dig("data", "traceList").map { |t| t["duration"] }).to(eq([30.0, 20.0, 10.0]))
      expect(fastest.dig("data", "traceList").map { |t| t["duration"] }).to(eq([10.0, 20.0, 30.0]))
    end

    it("returns the oldest first when sorted by created_at ascending") do
      newest = Trace.create!(endpoint: "GET /users", duration: 10.0, status: 200, created_at: 1.hour.ago)
      oldest = Trace.create!(endpoint: "GET /users", duration: 10.0, status: 200, created_at: 2.days.ago)

      result = SteakAndEggsSchema.execute('{ traceList(endpoint: "GET /users", sort: CREATED_AT, direction: ASC) { id } }').to_h

      expect(result.dig("data", "traceList").map { |t| t["id"].to_i }).to(eq([oldest.id, newest.id]))
    end

    it("sorts before it limits, so the slowest trace is found even when 1000 newer ones exist") do
      slowest = Trace.create!(endpoint: "GET /users", duration: 900.0, status: 200, created_at: 2.days.ago)
      now = Time.current
      Trace.insert_all(Array.new(1000) { { endpoint: "GET /users", duration: 10.0, status: 200, source: "user", created_at: now, updated_at: now } })

      result = SteakAndEggsSchema.execute('{ traceList(endpoint: "GET /users", sort: DURATION, direction: DESC) { id } }').to_h

      expect(result.dig("data", "traceList").first["id"].to_i).to(eq(slowest.id))
    end

    it("keeps only cached or only uncached traces when cache is given") do
      Trace.create!(endpoint: "GET /users", duration: 10.0, status: 200, breakdown: { "Ticker.search" => { "used_redis" => true, "duration" => 1.0 } })
      Trace.create!(endpoint: "GET /users", duration: 20.0, status: 200, breakdown: { "Ticker.search" => { "used_redis" => false, "used_db" => true, "duration" => 2.0 } })
      Trace.create!(endpoint: "GET /users", duration: 30.0, status: 200, breakdown: { "MarketService.marketdata" => { "used_api" => true, "duration" => 3.0 } })
      Trace.create!(endpoint: "GET /users", duration: 40.0, status: 401, breakdown: {})
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200, breakdown: nil)

      cached = SteakAndEggsSchema.execute('{ traceList(endpoint: "GET /users", cache: CACHED) { duration } }').to_h
      uncached = SteakAndEggsSchema.execute('{ traceList(endpoint: "GET /users", cache: UNCACHED) { duration } }').to_h

      expect(cached.dig("data", "traceList").map { |t| t["duration"] }).to(eq([10.0]))
      expect(uncached.dig("data", "traceList").map { |t| t["duration"] }).to(contain_exactly(20.0, 30.0))
    end

    it("rejects a sort column it doesn't know") do
      result = SteakAndEggsSchema.execute('{ traceList(endpoint: "GET /users", sort: ENDPOINT) { id } }').to_h

      expect(result["errors"]).to(be_present)
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

    it("expects two runs over the ten minute status window") do
      slo = SteakAndEggsSchema.execute('{ canarySlo(range: "10m") { good expected } }').to_h.dig("data", "canarySlo")

      expect(slo).to(eq({"good" => 0, "expected" => 2}))
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

  describe("polygon_calls") do
    let(:query) { '{ polygonCalls(range: "1h") { calls failures p50 p99 lastSuccessAt } }' }

    def execute_query
      SteakAndEggsSchema.execute(query).to_h.dig("data", "polygonCalls")
    end

    def polygon_call(duration:, failed: false, at: 10.minutes.ago, source: "user")
      span = {symbol: "AAPL", used_redis: false, used_api: true, duration: duration}
      span[:exception] = ["MarketService::ApiError", "MarketService::ApiError"] if failed
      Trace.create!(endpoint: "GET /stocks/AAPL/marketdata", duration: duration + 5, status: failed ? 500 : 200, source: source, breakdown: {"MarketService.marketdata" => span}, created_at: at)
    end

    it("returns no calls and no last success when nothing called polygon") do
      expect(execute_query).to(eq({"calls" => 0, "failures" => 0, "p50" => nil, "p99" => nil, "lastSuccessAt" => nil}))
    end

    it("counts user and canary calls and failures and times the api span, not the request") do
      polygon_call(duration: 100.0, at: 30.minutes.ago)
      polygon_call(duration: 300.0, at: 20.minutes.ago)
      polygon_call(duration: 2000.0, failed: true, at: 10.minutes.ago, source: "canary")

      calls = execute_query

      expect(calls["calls"]).to(eq(3))
      expect(calls["failures"]).to(eq(1))
      expect(calls["p50"]).to(eq(300.0))
      expect(calls["p99"]).to(eq(2000.0))
      expect(Time.zone.parse(calls["lastSuccessAt"])).to(be_within(1.second).of(20.minutes.ago))
    end

    it("counts a 404 as a call polygon answered, not a failure") do
      Trace.create!(endpoint: "GET /stocks/TSE/companydata", duration: 210.0, status: 404, created_at: 5.minutes.ago,
        breakdown: {"MarketService.companydata" => {symbol: "TSE", used_redis: false, used_api: true, duration: 200.0, exception: ["MarketService::NotFoundError", "MarketService::NotFoundError"]}})

      calls = execute_query

      expect(calls["calls"]).to(eq(1))
      expect(calls["failures"]).to(eq(0))
      expect(Time.zone.parse(calls["lastSuccessAt"])).to(be_within(1.second).of(5.minutes.ago))
    end

    it("leaves out load test calls") do
      polygon_call(duration: 100.0, at: 10.minutes.ago, source: "load")
      polygon_call(duration: 100.0, failed: true, at: 5.minutes.ago, source: "load")

      calls = execute_query

      expect(calls["calls"]).to(eq(0))
      expect(calls["lastSuccessAt"]).to(be_nil)
    end

    it("ignores cache hits") do
      Trace.create!(endpoint: "GET /stocks/AAPL/marketdata", duration: 3.0, status: 200, breakdown: {"MarketService.marketdata" => {used_redis: true, used_api: false, duration: 1.0}}, created_at: 10.minutes.ago)

      expect(execute_query["calls"]).to(eq(0))
    end

    it("finds the last success from earlier in the day when nothing called polygon this hour") do
      polygon_call(duration: 150.0, at: 5.hours.ago)
      polygon_call(duration: 150.0, at: 2.days.ago)

      calls = execute_query

      expect(calls["calls"]).to(eq(0))
      expect(Time.zone.parse(calls["lastSuccessAt"])).to(be_within(1.second).of(5.hours.ago))
    end
  end

  describe("service_timeseries") do
    let(:query) do
      <<~GQL
        {
          serviceTimeseries(range: "1h") {
            bucket
            bucketEnd
            requests
            errors
            p50
            p95
            p99
          }
        }
      GQL
    end

    include ActiveSupport::Testing::TimeHelpers

    before { travel_to(Time.utc(2026, 9, 30, 12, 7, 30)) }
    after { travel_back }

    def execute_query
      SteakAndEggsSchema.execute(query).to_h.dig("data", "serviceTimeseries")
    end

    it("returns one bucket per step up to the last finished one, with no percentiles for empty ones") do
      buckets = execute_query

      expect(buckets.length).to(eq(12))
      expect(buckets.first["bucket"]).to(eq("2026-09-30T11:05:00Z"))
      expect(buckets.last["bucket"]).to(eq("2026-09-30T12:00:00Z"))
      expect(buckets.last["bucketEnd"]).to(eq("2026-09-30T12:05:00Z"))
      expect(buckets.map { |b| b["requests"] }.uniq).to(eq([0]))
      expect(buckets.map { |b| b["p99"] }.uniq).to(eq([nil]))
    end

    it("covers the last two finished buckets for the ten minute status window") do
      buckets = SteakAndEggsSchema.execute('{ serviceTimeseries(range: "10m") { bucket } }').to_h.dig("data", "serviceTimeseries")

      expect(buckets.map { |b| b["bucket"] }).to(eq(["2026-09-30T11:55:00Z", "2026-09-30T12:00:00Z"]))
    end

    it("counts requests and errors in the bucket they happened in") do
      Trace.create!(endpoint: "GET /users", duration: 10.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 2))
      Trace.create!(endpoint: "GET /users", duration: 30.0, status: 500, created_at: Time.utc(2026, 9, 30, 12, 4))

      last = execute_query.last

      expect(last["requests"]).to(eq(2))
      expect(last["errors"]).to(eq(1))
      expect(last["p50"]).to(eq(10.0))
      expect(last["p99"]).to(eq(30.0))
    end

    it("only counts requests with the status when one is given") do
      Trace.create!(endpoint: "GET /users", duration: 10.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 2))
      Trace.create!(endpoint: "GET /users", duration: 30.0, status: 500, created_at: Time.utc(2026, 9, 30, 12, 4))

      last = SteakAndEggsSchema.execute('{ serviceTimeseries(range: "1h", status: 500) { requests errors } }').to_h.dig("data", "serviceTimeseries").last

      expect(last).to(eq({ "requests" => 1, "errors" => 1 }))
    end

    it("only counts cached or uncached requests when cache is given") do
      Trace.create!(endpoint: "GET /users", duration: 10.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 2), breakdown: { "Ticker.search" => { "used_redis" => true } })
      Trace.create!(endpoint: "GET /users", duration: 30.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 3), breakdown: { "Ticker.search" => { "used_db" => true } })
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 401, created_at: Time.utc(2026, 9, 30, 12, 4), breakdown: {})

      cached = SteakAndEggsSchema.execute('{ serviceTimeseries(range: "1h", cache: CACHED) { requests p50 } }').to_h.dig("data", "serviceTimeseries").last
      uncached = SteakAndEggsSchema.execute('{ serviceTimeseries(range: "1h", cache: UNCACHED) { requests p50 } }').to_h.dig("data", "serviceTimeseries").last

      expect(cached).to(eq({ "requests" => 1, "p50" => 10.0 }))
      expect(uncached).to(eq({ "requests" => 1, "p50" => 30.0 }))
    end

    it("leaves out the bucket still in progress so it never reads as a drop") do
      Trace.create!(endpoint: "GET /users", duration: 10.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 6))

      expect(execute_query.sum { |b| b["requests"] }).to(eq(0))
    end

    it("leaves out DataCat's own queries and load tests") do
      Trace.create!(endpoint: "POST /graphql", duration: 10.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 2))
      Trace.create!(endpoint: "GET /users", duration: 10.0, status: 200, source: "load", created_at: Time.utc(2026, 9, 30, 12, 2))

      expect(execute_query.sum { |b| b["requests"] }).to(eq(0))
    end

    it("narrows to one route when an endpoint is given") do
      Trace.create!(endpoint: "GET /stocks/AAPL/chartdata", duration: 10.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 2))
      Trace.create!(endpoint: "GET /stocks/TSLA/chartdata?range=1y", duration: 10.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 3))
      Trace.create!(endpoint: "GET /stocks/AAPL/marketdata", duration: 10.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 3))

      buckets = SteakAndEggsSchema.execute('{ serviceTimeseries(range: "1h", endpoint: "GET /stocks/symbol/chartdata") { requests } }').to_h.dig("data", "serviceTimeseries")

      expect(buckets.sum { |b| b["requests"] }).to(eq(2))
    end

    it("appends the bucket still in progress, marked partial, only when asked") do
      Trace.create!(endpoint: "GET /users", duration: 10.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 6))

      buckets = SteakAndEggsSchema.execute('{ serviceTimeseries(range: "1h", includePartial: true) { bucket bucketEnd partial requests } }').to_h.dig("data", "serviceTimeseries")

      expect(buckets.length).to(eq(13))
      expect(buckets.last).to(eq("bucket" => "2026-09-30T12:05:00Z", "bucketEnd" => "2026-09-30T12:10:00Z", "partial" => true, "requests" => 1))
      expect(buckets.first(12).map { |b| b["partial"] }.uniq).to(eq([false]))
    end
  end

  describe("trace_scatter") do
    include ActiveSupport::Testing::TimeHelpers

    before { travel_to(Time.utc(2026, 9, 30, 12, 7, 30)) }
    after { travel_back }

    def scatter(arguments = 'endpoint: "GET /users", range: "1h"')
      SteakAndEggsSchema.execute("{ traceScatter(#{arguments}) { id at status duration count } }").to_h.dig("data", "traceScatter")
    end

    it("folds requests that land on the same spot into one point that opens the slowest of them") do
      Trace.create!(endpoint: "GET /users", duration: 100.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 0))
      slowest = Trace.create!(endpoint: "GET /users", duration: 105.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 0))

      points = scatter

      expect(points.length).to(eq(1))
      expect(points.first).to(include("id" => slowest.id.to_s, "duration" => 105.0, "count" => 2))
    end

    it("keeps requests far apart in duration as separate points") do
      Trace.create!(endpoint: "GET /users", duration: 2.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 0))
      Trace.create!(endpoint: "GET /users", duration: 400.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 0))

      expect(scatter.map { |point| point["duration"] }).to(contain_exactly(2.0, 400.0))
    end

    it("never lets an error share a point with a success") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 0))
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 503, created_at: Time.utc(2026, 9, 30, 12, 0))

      expect(scatter.map { |point| point["status"] }).to(contain_exactly(200, 503))
    end

    it("plots up to now, including the bucket still in progress") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 6))

      expect(scatter.map { |point| point["at"] }).to(eq(["2026-09-30T12:06:00Z"]))
    end

    it("keeps only cached or only uncached requests when cache is given") do
      Trace.create!(endpoint: "GET /users", duration: 2.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 0), breakdown: { "Ticker.search" => { "used_redis" => true } })
      Trace.create!(endpoint: "GET /users", duration: 400.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 0), breakdown: { "Ticker.search" => { "used_db" => true } })

      expect(scatter('endpoint: "GET /users", range: "1h", cache: CACHED').map { |point| point["duration"] }).to(eq([2.0]))
      expect(scatter('endpoint: "GET /users", range: "1h", cache: UNCACHED').map { |point| point["duration"] }).to(eq([400.0]))
    end

    it("only covers the endpoint's route, from user and canary traffic") do
      Trace.create!(endpoint: "GET /stocks/AAPL/chartdata", duration: 50.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 0))
      Trace.create!(endpoint: "GET /stocks/AAPL/chartdata", duration: 50.0, status: 200, source: "load", created_at: Time.utc(2026, 9, 30, 12, 0))
      Trace.create!(endpoint: "GET /stocks/AAPL/marketdata", duration: 50.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 0))

      expect(scatter('endpoint: "GET /stocks/symbol/chartdata", range: "1h"').sum { |point| point["count"] }).to(eq(1))
    end

    it("narrows to one status when asked") do
      Trace.create!(endpoint: "GET /users", duration: 50.0, status: 200, created_at: Time.utc(2026, 9, 30, 12, 0))
      Trace.create!(endpoint: "GET /users", duration: 900.0, status: 503, created_at: Time.utc(2026, 9, 30, 12, 1))

      expect(scatter('endpoint: "GET /users", range: "1h", status: 503').map { |point| point["status"] }).to(eq([503]))
    end
  end

  describe("trace") do
    it("returns one trace by id, or nothing for an unknown one") do
      trace = Trace.create!(endpoint: "GET /users", duration: 12.0, status: 200)

      expect(SteakAndEggsSchema.execute("{ trace(id: #{trace.id}) { endpoint duration } }").to_h.dig("data", "trace")).to(eq("endpoint" => "GET /users", "duration" => 12.0))
      expect(SteakAndEggsSchema.execute("{ trace(id: #{trace.id + 1}) { endpoint } }").to_h.dig("data", "trace")).to(be_nil)
    end
  end

  describe("ingester_resources") do
    it("returns the ingester's cpu and memory for the window, capped like the other ingester fields") do
      allow(DependencyHealthService).to(receive(:resources).and_return([{at: Time.utc(2026, 9, 30, 12, 0), cpu: 80.7, memory: 41.0}]))

      result = SteakAndEggsSchema.execute('{ ingesterResources(from: "2026-07-01T00:00:00Z", to: "2026-09-30T12:00:00Z") { at cpu memory } }').to_h

      expect(result.dig("data", "ingesterResources")).to(eq([{"at" => "2026-09-30T12:00:00Z", "cpu" => 80.7, "memory" => 41.0}]))
      expect(DependencyHealthService).to(have_received(:resources).with(dependency: "ingester", from: Time.utc(2026, 8, 31, 12, 0), to: Time.utc(2026, 9, 30, 12, 0)))
    end
  end

  describe("dependency_health") do
    let(:query) { '{ dependencyHealth { id configured status readings { key label unit now peak total points { at value } } } }' }

    it("resolves fresh and cached results the same way") do
      fresh = [{id: "rails", configured: true, status: "good", readings: [{key: "cpu", label: "CPU", unit: "percent", now: 12.0, peak: 30.0, total: nil, points: [{at: Time.utc(2026, 9, 29, 12, 0), value: 12.0}]}]}]
      cached = JSON.parse(fresh.to_json)

      results = [fresh, cached].map do |health|
        allow(DependencyHealthService).to(receive(:current).and_return(health))
        SteakAndEggsSchema.execute(query).to_h.dig("data", "dependencyHealth")
      end

      expect(results[0]).to(eq(results[1]))
      expect(results[0][0]["readings"][0]["peak"]).to(eq(30.0))
      expect(results[0][0]["readings"][0]["points"]).to(eq([{"at" => "2026-09-29T12:00:00Z", "value" => 12.0}]))
    end
  end
end
