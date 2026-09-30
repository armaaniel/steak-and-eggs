class DependencyHealthService
  REGION = 'us-west-1'
  CLUSTER = 'steakneggs'
  SERVICES = {'rails' => 'steakneggs', 'ingester' => 'ingester'}.freeze
  DEPENDENCIES = %w[alb rails ingester postgres redis].freeze

  WINDOW = 1.hour
  PERIOD = 60
  CACHE_KEY = 'dependency_health'
  CACHE_SECONDS = 60

  CPU_WARN = 70
  CPU_CRITICAL = 90
  MEMORY_WARN = 80
  MEMORY_CRITICAL = 90
  CONNECTIONS_WARN = 80
  STORAGE_WARN_BYTES = 2 * 1024**3

  def self.current
    cached = RedisService.safe_get(CACHE_KEY)
    return JSON.parse(cached) if cached

    health = build
    RedisService.safe_setex(CACHE_KEY, CACHE_SECONDS, health.to_json)
    health
  rescue => e
    Sentry.capture_exception(e)
    []
  end

  def self.build
    specs = metric_specs
    series = fetch(specs)
    configured = configured_dependencies

    DEPENDENCIES.map do |dependency|
      readings = specs.select { |spec| spec[:dependency] == dependency }.map { |spec| reading(spec, series[spec[:id]] || []) }
      by_key = readings.index_by { |r| r[:key] }
      has_data = readings.any? { |r| !r[:now].nil? }
      status = configured.include?(dependency) && has_data ? status_for(dependency, by_key) : 'none'

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

      specs << spec(dependency: dependency, key: 'cpu', label: 'CPU', unit: 'percent', namespace: 'AWS/ECS', metric: 'CPUUtilization', dimensions: dimensions, stat: 'Average')
      specs << spec(dependency: dependency, key: 'memory', label: 'Memory', unit: 'percent', namespace: 'AWS/ECS', metric: 'MemoryUtilization', dimensions: dimensions, stat: 'Average')
    end

    if configured.include?('postgres')
      dimensions = [{name: 'DBInstanceIdentifier', value: ENV['RDS_INSTANCE_ID']}]

      specs << spec(dependency: 'postgres', key: 'cpu', label: 'CPU', unit: 'percent', namespace: 'AWS/RDS', metric: 'CPUUtilization', dimensions: dimensions, stat: 'Average')
      specs << spec(dependency: 'postgres', key: 'connections', label: 'Connections', unit: 'count', namespace: 'AWS/RDS', metric: 'DatabaseConnections', dimensions: dimensions, stat: 'Average')
      specs << spec(dependency: 'postgres', key: 'storage', label: 'Free storage', unit: 'bytes', namespace: 'AWS/RDS', metric: 'FreeStorageSpace', dimensions: dimensions, stat: 'Minimum')
    end

    if configured.include?('redis')
      dimensions = [{name: 'CacheClusterId', value: ENV['REDIS_NODE_ID']}]

      specs << spec(dependency: 'redis', key: 'cpu', label: 'Engine CPU', unit: 'percent', namespace: 'AWS/ElastiCache', metric: 'EngineCPUUtilization', dimensions: dimensions, stat: 'Average')
      specs << spec(dependency: 'redis', key: 'memory', label: 'Memory used', unit: 'percent', namespace: 'AWS/ElastiCache', metric: 'DatabaseMemoryUsagePercentage', dimensions: dimensions, stat: 'Average')
      specs << spec(dependency: 'redis', key: 'evictions', label: 'Evictions', unit: 'count', namespace: 'AWS/ElastiCache', metric: 'Evictions', dimensions: dimensions, stat: 'Sum')
    end

    specs
  end

  def self.spec(dependency:, key:, label:, unit:, namespace:, metric:, dimensions:, stat:)
    id = "#{dependency}_#{key}"
    query = {id: id, metric_stat: {metric: {namespace: namespace, metric_name: metric, dimensions: dimensions}, period: PERIOD, stat: stat}}

    {id: id, dependency: dependency, key: key, label: label, unit: unit, counter: stat == 'Sum', query: query}
  end

  def self.fetch(specs)
    finish = Time.current
    result = client.get_metric_data(metric_data_queries: specs.map { |spec| spec[:query] }, start_time: finish - WINDOW, end_time: finish, scan_by: 'TimestampAscending')

    result.metric_data_results.to_h { |series| [series.id, series.values] }
  end

  def self.reading(spec, values)
    {key: spec[:key],
     label: spec[:label],
     unit: spec[:unit],
     now: values.last,
     peak: values.max,
     total: spec[:counter] ? values.sum : nil}
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

  def self.client
    @client ||= Aws::CloudWatch::Client.new(region: REGION)
  end

  private_class_method :build, :configured_dependencies, :metric_specs, :spec, :fetch, :reading, :status_for, :client
end
