class MetricService
  REGION = 'us-west-1'
  NAMESPACE = 'AWS/ECS'
  CLUSTER = 'steakneggs'
  SERVICE = 'steakneggs'
  PERIOD = 60
  PAD = 120

  METRICS = {'cpu' => 'CPUUtilization', 'memory' => 'MemoryUtilization'}.freeze
  STATS = {'minimum' => 'Minimum', 'maximum' => 'Maximum', 'average' => 'Average'}.freeze
  SAMPLES = {'load' => LoadSample, 'cable' => CableSample}.freeze
  SAMPLED = %w[cpu_used cpu_pressure gc_time gc_major yjit_compile].freeze

  def self.for_run(run_id:, kind:, metric: 'cpu', step: nil)
    return [] unless SAMPLES.key?(kind)
    return sampled(run_id: run_id, metric: metric, step: step) if SAMPLED.include?(metric)
    return [] unless METRICS.key?(metric)

    samples = SAMPLES.fetch(kind).where(run_id: run_id)
    start, finish = samples.pick(Arel.sql('MIN(at)'), Arel.sql('MAX(at)'))
    return [] unless start

    saved = RunMetric.get(run_id: run_id, metric: metric).to_a
    last_saved = saved.last&.at
    last_available = Time.at(((finish + PAD).to_i / PERIOD - 1) * PERIOD).utc
    fully_saved = last_saved && last_saved >= last_available
    return saved if fully_saved

    fetch_and_save(run_id: run_id, metric: metric, from: start - PAD, to: finish + PAD)

    RunMetric.get(run_id: run_id, metric: metric)
  end

  def self.sampled(run_id:, metric:, step:)
    return RunMetric.get(run_id: run_id, metric: metric) unless step

    bucket = "to_timestamp(floor(extract(epoch FROM at) / #{step.to_i}) * #{step.to_i})"

    RunMetric.where(run_id: run_id, metric: metric)
             .group(Arel.sql(bucket))
             .order(Arel.sql(bucket))
             .select(Arel.sql("#{bucket} AS at, MIN(minimum) AS minimum, MAX(maximum) AS maximum, AVG(average) AS average"))
  end

  def self.fetch_and_save(run_id:, metric:, from:, to:)
    cloudwatch_metric = {
      namespace: NAMESPACE,
      metric_name: METRICS.fetch(metric),
      dimensions: [
        {name: 'ClusterName', value: CLUSTER},
        {name: 'ServiceName', value: SERVICE}
      ]
    }

    queries = STATS.map do |id, stat|
      {id: id, metric_stat: {metric: cloudwatch_metric, period: PERIOD, stat: stat}}
    end

    result = client.get_metric_data(metric_data_queries: queries, start_time: from, end_time: to)

    rows = {}
    result.metric_data_results.each do |series|
      series.timestamps.zip(series.values).each do |at, value|
        rows[at.utc] ||= {run_id: run_id, metric: metric, at: at.utc, minimum: nil, maximum: nil, average: nil}
        rows[at.utc][series.id.to_sym] = value
      end
    end

    RunMetric.upsert_all(rows.values, unique_by: %i[run_id metric at]) if rows.any?
  rescue => e
    Sentry.capture_exception(e)
  end

  def self.client
    @client ||= Aws::CloudWatch::Client.new(region: REGION)
  end

  private_class_method :sampled, :fetch_and_save, :client
end
