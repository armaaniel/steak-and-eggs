CABLE_SYMBOLS = %w[LOAD_01 LOAD_02 LOAD_03 LOAD_04 LOAD_05 LOAD_06 LOAD_07 LOAD_08 LOAD_09 LOAD_10]

CABLE_BUCKET = 5

CABLE_STAGES = [
  [2000, 60],
  [1000, 60]
]

CABLE_STAGESS = [
  [4000, 120],
  [2000, 120],
  [1000, 180],
  [500,  180],
  [333,  180],
  [250,  180],
  [167,  180]
]

CABLE_PLAN = CABLE_STAGES.each_with_object([]) do |(interval_ms, hold_seconds), plan|
  starts_at = plan.empty? ? 0 : plan.last[:ends_at]
  plan.push(
    interval: interval_ms / 1000.0,
    starts_at: starts_at,
    ends_at: starts_at + hold_seconds
  )
end.freeze

CABLE_TOTAL = CABLE_PLAN.last[:ends_at]
CABLE_SHORTEST_INTERVAL = CABLE_PLAN.map { |s| s[:interval] }.min

task cable_publish: :environment do
  redis_url = ENV.fetch('REDIS_URL')
  run_id = ENV.fetch('RUN_ID') { SecureRandom.uuid }
  counts = Hash.new(0)
  lock   = Mutex.new
  done   = false

  bucket_of = lambda do |time|
    epoch = time.to_i
    Time.at(epoch - (epoch % CABLE_BUCKET)).utc
  end
  
  puts JSON.generate(event: 'start', run_id: run_id, symbols: CABLE_SYMBOLS.size, 
  stages: CABLE_STAGES.size, seconds: CABLE_TOTAL)
  
  flusher = Thread.new do
    until done
      closed = {}
      begin
        sleep CABLE_BUCKET
        cutoff = bucket_of.call(Time.now.utc)

        closed = lock.synchronize do
          counts.select { |at, _frames| at < cutoff }
                .each_key { |at| counts.delete(at) }
        end
        next if closed.empty?

        CableSample.insert_all(
          closed.map { |at, frames| { run_id: run_id, at: at, source: 'publisher', frames: frames } }
        )
      rescue => e
        lock.synchronize do
          closed.each { |at, frames| counts[at] += frames }
        end
        Sentry.capture_exception(e)
      end
    end
  end

  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  threads = CABLE_SYMBOLS.each_with_index.map do |symbol, index|
    Thread.new do
      redis = Redis.new(
        url: redis_url,
        ssl: true,
        connect_timeout: 5,
        read_timeout: 2,
        write_timeout: 2
      )

      sleep(index * (CABLE_SHORTEST_INTERVAL / CABLE_SYMBOLS.size))

      loop do
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        stage = CABLE_PLAN.find do |plan| 
          elapsed < plan[:ends_at]
        end
        break unless stage

        payload = JSON.generate(t: (Time.now.to_f * 1000).round)
        redis.publish("price_channel:#{symbol}", payload)
        
        bucket = bucket_of.call(Time.now.utc)
        lock.synchronize do 
          counts[bucket] += 1
        end

        sleep(stage[:interval])
      end
    rescue => e
      Sentry.capture_exception(e)
      warn("publisher #{symbol} died: #{e.class}: #{e.message}")
    ensure
      begin
        redis&.close
      rescue StandardError
        nil
      end
    end
  end

  threads.each { |thread| thread.join }
  done = true
  flusher.join

  remaining = lock.synchronize do
    counts.map { |at, frames| { run_id: run_id, at: at, source: 'publisher', frames: frames } }
  end
  CableSample.insert_all(remaining) if remaining.any?

  total = CableSample.where(run_id: run_id, source: 'publisher').sum(:frames)
  puts JSON.generate(event: 'done', run_id: run_id, final_rows: remaining.size, published: total)
end
