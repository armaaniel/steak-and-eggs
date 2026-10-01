require 'rails_helper'

RSpec.describe(DependencyHealthService) do
  let(:client) { Aws::CloudWatch::Client.new(region: 'us-west-1', stub_responses: true) }
  let(:resource_ids) { {} }

  def series(id, values)
    {id: id, label: id, timestamps: values.each_index.map { |i| Time.current - (values.length - i).minutes }, values: values, status_code: 'Complete'}
  end

  def stub_series(*results)
    client.stub_responses(:get_metric_data, {metric_data_results: results})
  end

  def health_for(id)
    DependencyHealthService.current.find { |dependency| dependency[:id] == id }
  end

  before do
    allow(DependencyHealthService).to(receive(:client).and_return(client))
    allow(RedisService).to(receive(:safe_get).and_return(nil))
    allow(RedisService).to(receive(:safe_setex))
    allow(ENV).to(receive(:[]).and_call_original)
    %w[ALB_METRIC_ID TARGET_GROUP_METRIC_ID RDS_INSTANCE_ID REDIS_NODE_ID].each do |name|
      allow(ENV).to(receive(:[]).with(name).and_return(resource_ids[name]))
    end
  end

  describe "current" do
    it "marks the alb, postgres and redis as not configured when their ids are missing" do
      stub_series

      health = DependencyHealthService.current

      expect(health.map { |d| [d[:id], d[:configured]] }).to(eq([["alb", false], ["rails", true], ["ingester", true], ["postgres", false], ["redis", false]]))
      expect(health.select { |d| %w[alb postgres redis].include?(d[:id]) }.map { |d| d[:status] }.uniq).to(eq(["none"]))
    end

    it "reads the latest and peak values from each series" do
      stub_series(series("rails_cpu", [20.0, 45.0, 25.0]))

      cpu = health_for("rails")[:readings].find { |r| r[:key] == "cpu" }

      expect(cpu[:now]).to(eq(25.0))
      expect(cpu[:peak]).to(eq(45.0))
      expect(cpu[:total]).to(be_nil)
    end

    it("returns one-minute points for percentages but not for counts") do
      stub_series(series("rails_cpu", [20.0, 45.0, 25.0]))

      readings = health_for("rails")[:readings]

      expect(readings.find { |r| r[:key] == "cpu" }[:points].map { |p| p[:value] }).to(eq([20.0, 45.0, 25.0]))
    end

    it("leaves points empty for count readings") do
      allow(ENV).to(receive(:[]).with("ALB_METRIC_ID").and_return("app/steakneggs-alb/1"))
      allow(ENV).to(receive(:[]).with("TARGET_GROUP_METRIC_ID").and_return("targetgroup/steakneggs-tg/2"))
      stub_series(series("alb_healthy", [1.0, 1.0]))

      healthy = health_for("alb")[:readings].find { |r| r[:key] == "healthy" }

      expect(healthy[:points]).to(eq([]))
    end

    it "says a service with no datapoints has no status" do
      stub_series

      expect(health_for("rails")[:status]).to(eq("none"))
    end

    it "flags a cpu peak over the warning threshold and a current value over the critical one" do
      stub_series(series("rails_cpu", [20.0, 75.0, 30.0]), series("ingester_cpu", [20.0, 95.0]))

      expect(health_for("rails")[:status]).to(eq("warn"))
      expect(health_for("ingester")[:status]).to(eq("critical"))
    end

    it "asks for the maximum of cpu and memory so short spikes survive wider buckets" do
      stats = {}
      client.stub_responses(:get_metric_data, ->(context) do
        context.params[:metric_data_queries].each { |q| stats[q[:id]] = q[:metric_stat][:stat] }
        {metric_data_results: []}
      end)

      DependencyHealthService.current(range: "7d")

      expect(stats.values_at("rails_cpu", "rails_memory", "ingester_cpu", "ingester_memory").uniq).to(eq(["Maximum"]))
    end

    context "with every resource id set" do
      let(:resource_ids) do
        {"ALB_METRIC_ID" => "app/steakneggs-alb/1", "TARGET_GROUP_METRIC_ID" => "targetgroup/steakneggs-tg/2", "RDS_INSTANCE_ID" => "steakneggs-db", "REDIS_NODE_ID" => "steakneggs-redis-001"}
      end

      it "marks the alb down when it has no healthy targets" do
        stub_series(series("alb_healthy", [1.0, 0.0]))

        expect(health_for("alb")[:status]).to(eq("critical"))
      end

      it "flags any 5xx the alb returned itself" do
        stub_series(series("alb_healthy", [1.0, 1.0]), series("alb_errors", [0.0, 2.0, 0.0]))

        alb = health_for("alb")

        expect(alb[:status]).to(eq("warn"))
        expect(alb[:readings].find { |r| r[:key] == "errors" }[:total]).to(eq(2.0))
      end

      it "flags any redis evictions" do
        stub_series(series("redis_cpu", [3.0]), series("redis_evictions", [0.0, 3.0]))

        expect(health_for("redis")[:status]).to(eq("warn"))
      end

      it "flags postgres when free storage runs low" do
        stub_series(series("postgres_storage", [1.5 * 1024**3]))

        expect(health_for("postgres")[:status]).to(eq("warn"))
      end

      it "calls everything healthy when every value is under its threshold" do
        stub_series(series("alb_healthy", [1.0]), series("postgres_cpu", [12.0]), series("postgres_storage", [15.0 * 1024**3]))

        expect(health_for("alb")[:status]).to(eq("good"))
        expect(health_for("postgres")[:status]).to(eq("good"))
      end
    end

    context "with a range longer than the last hour" do
      def stub_by_period(recent, history)
        client.stub_responses(:get_metric_data, ->(context) do
          period = context.params[:metric_data_queries].first[:metric_stat][:period]
          {metric_data_results: [series("rails_cpu", period == 60 ? recent : history)]}
        end)
      end

      it "takes the status and the current value from the last hour and the peak and points from the range" do
        stub_by_period([20.0, 95.0], [30.0, 60.0, 40.0])

        rails = DependencyHealthService.current(range: "24h").find { |d| d[:id] == "rails" }
        cpu = rails[:readings].find { |r| r[:key] == "cpu" }

        expect(rails[:status]).to(eq("critical"))
        expect(cpu[:now]).to(eq(95.0))
        expect(cpu[:peak]).to(eq(60.0))
        expect(cpu[:points].map { |p| p[:value] }).to(eq([30.0, 60.0, 40.0]))
      end

      it "asks cloudwatch at the range's own resolution" do
        periods = []
        client.stub_responses(:get_metric_data, ->(context) do
          periods << context.params[:metric_data_queries].map { |q| q[:metric_stat][:period] }.uniq
          {metric_data_results: []}
        end)

        DependencyHealthService.current(range: "7d")

        expect(periods).to(eq([[60], [3600]]))
      end
    end

    it "asks cloudwatch once for the last hour and caches each range under its own key" do
      calls = 0
      client.stub_responses(:get_metric_data, ->(_context) do
        calls += 1
        {metric_data_results: []}
      end)

      DependencyHealthService.current(range: "1h")
      DependencyHealthService.current(range: "12h")

      expect(calls).to(eq(3))
      expect(RedisService).to(have_received(:safe_setex).with("dependency_health:1h", 60, anything))
      expect(RedisService).to(have_received(:safe_setex).with("dependency_health:12h", 60, anything))
    end

    it "falls back to the last hour for a range it does not know" do
      stub_series

      DependencyHealthService.current(range: "90d")

      expect(RedisService).to(have_received(:safe_setex).with("dependency_health:1h", 60, anything))
    end

    it "serves the cached result without calling cloudwatch" do
      allow(RedisService).to(receive(:safe_get).and_return([{id: "alb", configured: false, status: "none", readings: []}].to_json))
      expect(client).not_to(receive(:get_metric_data))

      expect(DependencyHealthService.current.first["id"]).to(eq("alb"))
    end

    it "returns an empty list and reports to sentry when cloudwatch fails" do
      client.stub_responses(:get_metric_data, "Throttling")
      allow(Sentry).to(receive(:capture_exception))

      expect(DependencyHealthService.current).to(eq([]))
      expect(Sentry).to(have_received(:capture_exception))
    end
  end

  describe "resources" do
    def queries_for(from, to)
      queries = nil
      client.stub_responses(:get_metric_data, ->(context) do
        queries = context.params[:metric_data_queries]
        {metric_data_results: []}
      end)
      DependencyHealthService.resources(dependency: "ingester", from: from, to: to)
      queries
    end

    it "lines cpu and memory up by timestamp, as maximums of the ingester service" do
      cpu = series("cpu", [20.0, 80.0])
      memory = series("memory", [41.0, 42.0]).merge(timestamps: cpu[:timestamps])
      client.stub_responses(:get_metric_data, {metric_data_results: [cpu, memory]})

      points = DependencyHealthService.resources(dependency: "ingester", from: 1.hour.ago, to: Time.current)

      expect(points.map { |p| [p[:cpu], p[:memory]] }).to(eq([[20.0, 41.0], [80.0, 42.0]]))
      expect(queries_for(1.hour.ago, Time.current).map { |q| q[:metric_stat][:stat] }.uniq).to(eq(["Maximum"]))
      expect(queries_for(1.hour.ago, Time.current).first[:metric_stat][:metric][:dimensions]).to(include({name: "ServiceName", value: "ingester"}))
    end

    it "sizes buckets to the window, from one minute up to an hour" do
      periods = {1.hour => 60, 24.hours => 300, 3.days => 900, 30.days => 3600}.to_h do |window, _|
        [window, queries_for(Time.current - window, Time.current).first[:metric_stat][:period]]
      end

      expect(periods.values).to(eq([60, 300, 900, 3600]))
    end

    it "never asks for one-minute data older than CloudWatch keeps it" do
      twenty_days_ago = queries_for(20.days.ago, 20.days.ago + 1.hour).first[:metric_stat][:period]
      seventy_days_ago = queries_for(70.days.ago, 70.days.ago + 1.hour).first[:metric_stat][:period]

      expect([twenty_days_ago, seventy_days_ago]).to(eq([300, 3600]))
    end

    it "returns no points and reports to sentry when cloudwatch fails" do
      client.stub_responses(:get_metric_data, "Throttling")
      allow(Sentry).to(receive(:capture_exception))

      expect(DependencyHealthService.resources(dependency: "ingester", from: 1.hour.ago, to: Time.current)).to(eq([]))
      expect(Sentry).to(have_received(:capture_exception))
    end
  end
end
