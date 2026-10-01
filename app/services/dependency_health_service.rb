class DependencyHealthService
  REGION = 'us-west-1'
  CLUSTER = 'steakneggs'
  SERVICES = {'rails' => 'steakneggs', 'ingester' => 'ingester'}.freeze
  DEPENDENCIES = %w[alb rails ingester postgres redis].freeze

  RANGES = {
    '1h'  => {window: 1.hour,   period: 60},
    '12h' => {window: 12.hours, period: 300},
    '24h' => {window: 24.hours, period: 300},
    '7d'  => {window: 7.days,   period: 3600},
    '14d' => {window: 14.days,  period: 3600},
    '30d' => {window: 30.days,  period: 3600}
  }.freeze
  STATUS_RANGE = '1h'
  RESOURCE_PERIODS = [60, 300, 900, 3600].freeze
  RESOURCE_MAX_POINTS = 500
  EMPTY_SERIES = {timestamps: [], values: []}.freeze
  CACHE_KEY = 'dependency_health'
  CACHE_SECONDS = 60

  CPU_WARN = 70
  CPU_CRITICAL = 90
  MEMORY_WARN = 80
  MEMORY_CRITICAL = 90
  CONNECTIONS_WARN = 80
  STORAGE_WARN_BYTES = 2 * 1024**3

  def self.current(range: STATUS_RANGE)
    range = STATUS_RANGE unless RANGES.key?(range)
    key = "#{CACHE_KEY}:#{range}"

    cached = RedisService.safe_get(key)
    return JSON.parse(cached) if cached

    health = build(range)
    RedisService.safe_setex(key, CACHE_SECONDS, health.to_json)
    health
  rescue => e
    Sentry.capture_exception(e)
    []
  end

  def self.build(range)
    specs = metric_specs
    recent = fetch(specs, **RANGES[STATUS_RANGE])
    history = range == STATUS_RANGE ? recent : fetch(specs, **RANGES[range])
    configured = configured_dependencies

    DEPENDENCIES.map do |dependency|
      own = specs.select { |spec| spec[:dependency] == dependency }
      latest = own.map { |spec| reading(spec, recent.fetch(spec[:id], EMPTY_SERIES)) }.index_by { |r| r[:key] }
      readings = own.map { |spec| reading(spec, history.fetch(spec[:id], EMPTY_SERIES)).merge(now: latest[spec[:key]][:now]) }
      has_data = latest.values.any? { |r| !r[:now].nil? }
      status = configured.include?(dependency) && has_data ? status_for(dependency, latest) : 'none'

      {id: dependency, configured: configured.include?(dependency), status: status, readings: readings}
    end
  end

  def self.configured_dependencies
    configured = %w[rails ingester]
    configured << 'alb' if ENV['ALB_METRIC_ID'].present? && ENV['TARGET_GROUP_METRIC_ID'].present?
    configured << 'postgres' if ENV['RDS_INSTANCE_ID'].present?
    configured << 'redis' if ENV['REDIS_NODE_ID'].present?
    configured
  end

  def self.metric_specs
    specs = []
    configured = configured_dependencies

    if configured.include?('alb')
      load_balancer = {name: 'LoadBalancer', value: ENV['ALB_METRIC_ID']}
      target_group = {name: 'TargetGroup', value: ENV['TARGET_GROUP_METRIC_ID']}

      specs << spec(dependency: 'alb', key: 'healthy', label: 'Healthy targets', unit: 'count', namespace: 'AWS/ApplicationELB', metric: 'HealthyHostCount', dimensions: [target_group, load_balancer], stat: 'Minimum')
      specs << spec(dependency: 'alb', key: 'unhealthy', label: 'Unhealthy targets', unit: 'count', namespace: 'AWS/ApplicationELB', metric: 'UnHealthyHostCount', dimensions: [target_group, load_balancer], stat: 'Maximum')
      specs << spec(dependency: 'alb', key: 'errors', label: 'ALB 5xx', unit: 'count', namespace: 'AWS/ApplicationELB', metric: 'HTTPCode_ELB_5XX_Count', dimensions: [load_balancer], stat: 'Sum')
    end

    SERVICES.each do |dependency, service|
      dimensions = [{name: 'ClusterName', value: CLUSTER}, {name: 'ServiceName', value: service}]

      specs << spec(dependency: dependency, key: 'cpu', label: 'CPU', unit: 'percent', namespace: 'AWS/ECS', metric: 'CPUUtilization', dimensions: dimensions, stat: 'Maximum')
      specs << spec(dependency: dependency, key: 'memory', label: 'Memory', unit: 'percent', namespace: 'AWS/ECS', metric: 'MemoryUtilization', dimensions: dimensions, stat: 'Maximum')
    end

    if configured.include?('postgres')
      dimensions = [{name: 'DBInstanceIdentifier', value: ENV['RDS_INSTANCE_ID']}]

      specs << spec(dependency: 'postgres', key: 'cpu', label: 'CPU', unit: 'percent', namespace: 'AWS/RDS', metric: 'CPUUtilization', dimensions: dimensions, stat: 'Maximum')
      specs << spec(dependency: 'postgres', key: 'connections', label: 'Connections', unit: 'count', namespace: 'AWS/RDS', metric: 'DatabaseConnections', dimensions: dimensions, stat: 'Maximum')
      specs << spec(dependency: 'postgres', key: 'storage', label: 'Free storage', unit: 'bytes', namespace: 'AWS/RDS', metric: 'FreeStorageSpace', dimensions: dimensions, stat: 'Minimum')
    end

    if configured.include?('redis')
      dimensions = [{name: 'CacheClusterId', value: ENV['REDIS_NODE_ID']}]

      specs << spec(dependency: 'redis', key: 'cpu', label: 'Engine CPU', unit: 'percent', namespace: 'AWS/ElastiCache', metric: 'EngineCPUUtilization', dimensions: dimensions, stat: 'Maximum')
      specs << spec(dependency: 'redis', key: 'memory', label: 'Memory used', unit: 'percent', namespace: 'AWS/ElastiCache', metric: 'DatabaseMemoryUsagePercentage', dimensions: dimensions, stat: 'Maximum')
      specs << spec(dependency: 'redis', key: 'evictions', label: 'Evictions', unit: 'count', namespace: 'AWS/ElastiCache', metric: 'Evictions', dimensions: dimensions, stat: 'Sum')
    end

    specs
  end

  def self.spec(dependency:, key:, label:, unit:, namespace:, metric:, dimensions:, stat:)
    metric_stat = {metric: {namespace: namespace, metric_name: metric, dimensions: dimensions}, stat: stat}

    {id: "#{dependency}_#{key}", dependency: dependency, key: key, label: label, unit: unit, counter: stat == 'Sum', metric_stat: metric_stat}
  end

  def self.fetch(specs, window:, period:)
    finish = Time.current
    queries = specs.map { |spec| {id: spec[:id], metric_stat: spec[:metric_stat].merge(period: period)} }
    result = client.get_metric_data(metric_data_queries: queries, start_time: finish - window, end_time: finish, scan_by: 'TimestampAscending')

    result.metric_data_results.to_h { |series| [series.id, {timestamps: series.timestamps, values: series.values}] }
  end

  def self.reading(spec, series)
    values = series[:values]
    points = spec[:unit] == 'percent' ? series[:timestamps].zip(values).map { |at, value| {at: at, value: value} } : []

    {key: spec[:key],
     label: spec[:label],
     unit: spec[:unit],
     now: values.last,
     peak: values.max,
     total: spec[:counter] ? values.sum : nil,
     points: points}
  end

  def self.status_for(dependency, readings)
    above = ->(key, field, limit) { (value = readings.dig(key, field)) && value > limit }

    case dependency
    when 'alb'
      return 'critical' if readings.dig('healthy', :now)&.zero?
      return 'warn' if above.('unhealthy', :now, 0) || above.('errors', :total, 0)
    when 'rails', 'ingester'
      return 'critical' if above.('cpu', :now, CPU_CRITICAL) || above.('memory', :now, MEMORY_CRITICAL)
      return 'warn' if above.('cpu', :peak, CPU_WARN) || above.('memory', :peak, MEMORY_WARN)
    when 'postgres'
      return 'critical' if above.('cpu', :now, CPU_CRITICAL)
      return 'warn' if above.('cpu', :peak, CPU_WARN) || above.('connections', :peak, CONNECTIONS_WARN)
      return 'warn' if (storage = readings.dig('storage', :now)) && storage < STORAGE_WARN_BYTES
    when 'redis'
      return 'critical' if above.('cpu', :now, CPU_CRITICAL) || above.('memory', :now, MEMORY_CRITICAL)
      return 'warn' if above.('cpu', :peak, CPU_WARN) || above.('memory', :peak, MEMORY_WARN) || above.('evictions', :total, 0)
    end

    'good'
  end

  def self.resources(dependency:, from:, to:)
    dimensions = [{name: 'ClusterName', value: CLUSTER}, {name: 'ServiceName', value: SERVICES.fetch(dependency)}]
    period = resource_period(from, to)

    queries = {'cpu' => 'CPUUtilization', 'memory' => 'MemoryUtilization'}.map do |id, metric|
      {id: id, metric_stat: {metric: {namespace: 'AWS/ECS', metric_name: metric, dimensions: dimensions}, period: period, stat: 'Maximum'}}
    end

    result = client.get_metric_data(metric_data_queries: queries, start_time: from, end_time: to, scan_by: 'TimestampAscending')
    series = result.metric_data_results.to_h { |s| [s.id, s.timestamps.zip(s.values).to_h] }

    series.values.flat_map(&:keys).uniq.sort.map do |at|
      {at: at, cpu: series.dig('cpu', at), memory: series.dig('memory', at)}
    end
  rescue => e
    Sentry.capture_exception(e)
    []
  end

  def self.resource_period(from, to)
    age = Time.current - from
    floor = if age > 63.days then 3600 elsif age > 15.days then 300 else 60 end

    RESOURCE_PERIODS.find { |p| p >= floor && (to - from) / p <= RESOURCE_MAX_POINTS } || RESOURCE_PERIODS.last
  end

  def self.client
    @client ||= Aws::CloudWatch::Client.new(region: REGION)
  end

  private_class_method :build, :configured_dependencies, :metric_specs, :spec, :fetch, :reading, :status_for, :resource_period, :client
end
