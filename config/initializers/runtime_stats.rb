Rails.application.config.after_initialize do
  next if Rails.env.test?

  path = ENV.fetch('RUNTIME_STATS_PATH', '/tmp/runtime_stats')
  staging = "#{path}.tmp"

  Thread.new do
    loop do
      sleep 1

      gc = GC.stat
      latest = GC.latest_gc_info
      yjit = (defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? && RubyVM::YJIT.runtime_stats) || {}

      stats = [
        gc[:count], gc[:minor_gc_count], gc[:major_gc_count], gc[:time],
        gc[:old_objects], gc[:old_objects_limit],
        latest[:major_by] || '-', latest[:need_major_by] || '-',
        yjit[:compile_time_ns] || 0, yjit[:compiled_iseq_count] || 0
      ]

      File.write(staging, "#{stats.join(' ')}\n")
      File.rename(staging, path)
    rescue => e
      Sentry.capture_exception(e)
      break
    end
  end
end
