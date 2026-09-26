module CableLoad
  SYMBOLS = %w[LOAD_01 LOAD_02 LOAD_03 LOAD_04 LOAD_05 LOAD_06 LOAD_07 LOAD_08 LOAD_09 LOAD_10]
  BUCKET_SECONDS = 5

  STAGES = [
    [500, 60],
    [286, 120],
    [250, 120],
    [235, 120],
    [222, 120],
    [211, 120],
    [200, 120]
  ]

  plan = []
  starts_at = 0

  STAGES.each do |interval_ms, hold_seconds|
    plan << { interval: interval_ms / 1000.0, starts_at: starts_at, ends_at: starts_at + hold_seconds }
    starts_at += hold_seconds
  end

  PLAN = plan.freeze

  SHORTEST_INTERVAL = PLAN.map { |stage| stage[:interval] }.min
  
  def self.bucket_start(time)
    seconds = time.to_i
    Time.at((seconds / BUCKET_SECONDS) * BUCKET_SECONDS).utc
  end
end

task cable_publish: :environment do
  
  redis_url = ENV.fetch('REDIS_URL')
  run_id = ENV.fetch('RUN_ID') { SecureRandom.uuid }
  published = Hash.new(0)
  lock   = Mutex.new
  done   = false
  
  flusher = Thread.new do
    loop do
      break if done
      
      finished = {}
      sleep CableLoad::BUCKET_SECONDS
      current_bucket = CableLoad.bucket_start(Time.now)

      finished = lock.synchronize do
        finished_buckets = published.keys.select { |bucket| bucket < current_bucket }
        published.extract!(*finished_buckets)
      end
      next if finished.empty?

      rows = finished.map do |bucket, frames|
        { run_id: run_id, at: bucket, source: 'publisher', frames: frames }
      end

      CableSample.insert_all(rows)
    rescue => e
      lock.synchronize do
        finished.each { |at, frames| published[at] += frames }
      end
      Sentry.capture_exception(e)
    end
  end

  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  threads = [] 
  
  CableLoad::SYMBOLS.each_with_index do |symbol, index|
    thread = Thread.new do
      
      redis = Redis.new(
        url: redis_url,
        ssl: true,
        connect_timeout: 5,
        read_timeout: 2,
        write_timeout: 2
      )

      sleep(index * (CableLoad::SHORTEST_INTERVAL / CableLoad::SYMBOLS.size))
      
      loop do
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
                
        stage = CableLoad::PLAN.find { |plan| elapsed < plan[:ends_at] }
        
        break if not stage
                
        at = Time.now
        payload = JSON.generate(t: (at.to_f * 1000).round)
        redis.publish("price_channel:#{symbol}", payload)
        
        current_bucket = CableLoad.bucket_start(at)
        
        lock.synchronize { published[current_bucket] += 1 }

        sleep(stage[:interval])
      end
    rescue => e
      Sentry.capture_exception(e)
    ensure
      begin
        redis&.close
      rescue StandardError
        nil
      end
    end
    threads << thread
  end
  
  threads.each(&:join)
  done = true
  flusher.join

  remaining = published.map { |at, frames| { run_id: run_id, at: at, source: 'publisher', frames: frames } }
  CableSample.insert_all(remaining) if remaining.any?
end
