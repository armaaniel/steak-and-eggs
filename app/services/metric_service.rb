class MetricService
  REGION = 'us-west-1'
  NAMESPACE = 'AWS/ECS'
  CLUSTER = 'steakneggs'
  SERVICE = 'steakneggs'
  PERIOD = 60
  PAD = 120

  METRICS = {'cpu' => 'CPUUtilization', 'memory' => 'MemoryUtilization'}.freeze
  STATS = {'minimum' => 'Minimum', 'maximum' => 'Maximum', 'average' => 'Average'}.freeze

  def self.for_run(run_id:, metric: 'cpu')
    from, to = LoadSample.where(run_id: run_id).pluck(Arel.sql('MIN(at)'), Arel.sql('MAX(at)')).first

    refresh(run_id: run_id, metric: metric, from: from - PAD, to: to + PAD) if from && METRICS.key?(metric)

    RunMetric.for_run(run_id: run_id, metric: metric)
  end

  def self.refresh(run_id:, metric:, from:, to:)
    rows = fetch(metric: metric, from: from, to: to).map do |at, values|
      {
        run_id: run_id,
        metric: metric,
        at: at,
        minimum: values['minimum'],
        maximum: values['maximum'],
        average: values['average']
      }
    end

    RunMetric.upsert_all(rows, unique_by: %i[run_id metric at]) if rows.any?
  rescue => e
    Sentry.capture_exception(e)
  end

  def self.fetch(metric:, from:, to:)
    queries = STATS.map do |id, stat|
      {
        id: id,
        metric_stat: {
          metric: {
            namespace: NAMESPACE,
            metric_name: METRICS.fetch(metric),
            dimensions: [
              {name: 'ClusterName', value: CLUSTER},
              {name: 'ServiceName', value: SERVICE}
            ]
          },
          period: PERIOD,
          stat: stat
        }
      }
    end

    result = client.get_metric_data(metric_data_queries: queries, start_time: from, end_time: to)

    points = Hash.new { |hash, key| hash[key] = {} }

    result.metric_data_results.each do |series|
      series.timestamps.each_with_index do |at, index|
        points[at.utc][series.id] = series.values[index]
      end
    end

    points
  end

  def self.client
    @client ||= Aws::CloudWatch::Client.new(region: REGION)
  end
end
