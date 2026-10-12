require_relative 'cpu_log'

CAP_MS = 250.0
BASELINE_WINDOW = 15

log = CpuLog.read(ARGV.fetch(0))
seconds = log[:seconds]
runtime = seconds.any? { |second| second.key?(:gc_ms) }

puts("cpu part #{log[:part] || 'unknown'}, cap #{CAP_MS.round} ms of cpu per second")
puts("minute  cpu ms/s avg  max   % of cap  pressure ms/s avg  max#{'  gc ms/s  majors  yjit ms/s' if runtime}")

seconds.group_by { |second| second[:at].strftime('%H:%M') }.each do |minute, group|
  cpu = group.map { |second| second[:cpu] }
  pressure = group.map { |second| second[:pressure] }
  cpu_avg = cpu.sum / cpu.size

  printf('%s   %8.1f  %6.1f  %6.1f%%  %13.1f  %6.1f', minute, cpu_avg, cpu.max, cpu_avg / CAP_MS * 100, pressure.sum / pressure.size, pressure.max)
  printf('  %7.1f  %6d  %9.1f', group.sum { |second| second[:gc_ms].to_f } / group.size, group.sum { |second| second[:majors].to_i }, group.sum { |second| second[:yjit_ms].to_f } / group.size) if runtime
  puts
end

exit unless runtime

majors = seconds.select { |second| second[:majors].to_i.positive? }
puts
puts("major collections: #{majors.size}")
majors.each do |second|
  printf("  %s  %-8s  gc %5.1f ms  cpu %5.1f ms/s  pressure %5.1f ms/s  old objects %d of %d\n",
         second[:at].strftime('%H:%M:%S'), second[:major_by] || 'unknown', second[:gc_ms], second[:cpu], second[:pressure], second[:old_objects], second[:old_limit])
end

bursts = seconds.each_index.select do |index|
  window = seconds[[index - BASELINE_WINDOW, 0].max..(index + BASELINE_WINDOW)].map { |second| second[:cpu] }.sort
  baseline = window[window.size / 2]
  over = ->(second) { second[:cpu] > baseline * 1.12 + 8 }

  over.(seconds[index]) && (index.zero? || !over.(seconds[index - 1]))
end

explained = bursts.count do |index|
  seconds[[index - 1, 0].max..(index + 1)].any? { |second| second[:majors].to_i.positive? || second[:yjit_ms].to_f > 5 }
end

puts
puts("cpu bursts: #{bursts.size}, with a major collection or yjit compile within a second: #{explained}")
