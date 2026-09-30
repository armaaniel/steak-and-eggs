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

    it "says a service with no datapoints has no status" do
      stub_series

      expect(health_for("rails")[:status]).to(eq("none"))
    end

    it "flags a cpu peak over the warning threshold and a current value over the critical one" do
      stub_series(series("rails_cpu", [20.0, 75.0, 30.0]), series("ingester_cpu", [20.0, 95.0]))

      expect(health_for("rails")[:status]).to(eq("warn"))
      expect(health_for("ingester")[:status]).to(eq("critical"))
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
end
