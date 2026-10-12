CAP_MS = 250.0

lines = File.readlines(ARGV.fetch(0), chomp: true).map { |line| line.delete("\r") }
start = lines.find { |line| line.start_with?('start ') }
abort('no start line in the cpu log') unless start

_, epoch, start_up, part = start.split(' ', 4)
samples = lines.grep(/\A\d+\.\d+ \d+ \d+\z/).map { |line| line.split.map(&:to_f) }

rows = samples.each_cons(2).map do |(up_before, usage_before, pressure_before), (up, usage, pressure)|
  seconds = up - up_before
  { at: Time.at(epoch.to_f + up - start_up.to_f).utc,
    cpu: (usage - usage_before) / 1e6 / seconds,
    pressure: (pressure - pressure_before) / 1e3 / seconds }
end

puts("cpu part #{part.to_s[/0x\h+/] || 'unknown'}, cap #{CAP_MS.round} ms of cpu per second")
puts('minute  cpu ms/s avg  max   % of cap  pressure ms/s avg  max')

rows.group_by { |row| row[:at].strftime('%H:%M') }.each do |minute, group|
  cpu = group.map { |row| row[:cpu] }
  pressure = group.map { |row| row[:pressure] }
  cpu_avg = cpu.sum / cpu.size

  printf("%s   %8.1f  %6.1f  %6.1f%%  %13.1f  %6.1f\n", minute, cpu_avg, cpu.max, cpu_avg / CAP_MS * 100, pressure.sum / pressure.size, pressure.max)
end
