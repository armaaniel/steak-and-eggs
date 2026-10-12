module CpuLog
  SAMPLE = /\A\d+\.\d+ \d+ \d+( |\z)/

  def self.read(path)
    lines = File.readlines(path, chomp: true).map { |line| line.delete("\r") }
    start = lines.find { |line| line.start_with?('start ') }
    abort('no start line in the cpu log') unless start

    _, epoch, start_up, part = start.split(' ', 4)
    samples = lines.grep(SAMPLE).map(&:split)

    seconds = samples.each_cons(2).map do |before, after|
      elapsed = after[0].to_f - before[0].to_f
      second = { at: Time.at(epoch.to_f + after[0].to_f - start_up.to_f).utc,
                 cpu: (after[1].to_f - before[1].to_f) / 1e6 / elapsed,
                 pressure: (after[2].to_f - before[2].to_f) / 1e3 / elapsed }

      if after.size >= 13 && before.size >= 13
        second.merge!(gc_ms: (after[6].to_f - before[6].to_f) / elapsed,
                      minors: after[4].to_i - before[4].to_i,
                      majors: after[5].to_i - before[5].to_i,
                      old_objects: after[7].to_i,
                      old_limit: after[8].to_i,
                      major_by: [after[9], before[10]].find { |reason| reason != '-' },
                      yjit_ms: (after[11].to_f - before[11].to_f) / 1e6 / elapsed)
      end

      second
    end

    { part: part.to_s[/0x\h+/], seconds: seconds }
  end
end
