require 'json'
require 'net/http'
require_relative 'cpu_log'

BATCH_SIZE = 1000
METRICS = { 'cpu_used' => :cpu, 'cpu_pressure' => :pressure, 'gc_time' => :gc_ms, 'gc_major' => :majors, 'yjit_compile' => :yjit_ms, 'memory_used' => :container_mb }.freeze

path, run_id = ARGV
uri = URI("#{ENV.fetch('API', 'https://www.steakneggs.art')}/run_metrics")
headers = { 'Content-Type' => 'application/json', 'Synthetic-Key' => ENV.fetch('SYNTHETIC_KEY') }

samples = CpuLog.read(path)[:seconds].flat_map do |second|
  at = (second[:at].to_f * 1000).round
  metrics = METRICS.filter_map do |metric, field|
    { metric: metric, at: at, value: second[field] } if second.key?(field)
  end

  metrics << { metric: "gc_major_#{second[:major_by]}", at: at, value: 1 } if second[:majors].to_i.positive? && second[:major_by]
  metrics
end

samples.each_slice(BATCH_SIZE) do |batch|
  response = Net::HTTP.post(uri, { run_id: run_id, samples: batch }.to_json, headers)
  raise "#{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)
end

puts("imported #{samples.size} run metrics into #{run_id}")
