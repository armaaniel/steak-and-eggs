require 'csv'
require 'json'
require 'net/http'
require 'zlib'

BATCH_SIZE = 1000
METRICS = { 'http_req_waiting' => :waiting, 'http_req_duration' => :duration }.freeze

path, run_id = ARGV
uri = URI("#{ENV.fetch('API', 'https://www.steakneggs.art')}/load_samples")
headers = { 'Content-Type' => 'application/json', 'Synthetic-Key' => ENV.fetch('SYNTHETIC_KEY') }
pending = {}
batch = []
sent = 0

post = lambda do
  response = Net::HTTP.post(uri, { run_id: run_id, samples: batch }.to_json, headers)
  raise "#{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)
  sent += batch.size
  batch.clear
end

Zlib::GzipReader.open(path) do |file|
  CSV.new(file, headers: true).each do |row|
    field = METRICS[row['metric_name']]
    next unless field

    meta = URI.decode_www_form(row['metadata'].to_s).to_h
    request_id = meta['request_id']
    next unless request_id

    sample = pending[request_id] ||= { request_id: request_id, at: meta['sent_at'].to_i, route: meta['route'], status: row['status'].to_i }
    sample[field] = row['metric_value'].to_f.round
    next unless sample[:waiting] && sample[:duration]

    batch << pending.delete(request_id)
    post.call if batch.size == BATCH_SIZE
  end
end

post.call if batch.any?
puts "imported #{sent} samples into #{run_id}, #{pending.size} incomplete"
