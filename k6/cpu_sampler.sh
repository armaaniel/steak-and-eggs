STATS=/tmp/runtime_stats
MEMORY=/sys/fs/cgroup/memory

read up idle < /proc/uptime
echo "start $(date +%s) $up $(grep -m1 'CPU part' /proc/cpuinfo | tr -d ' \t')"
end=$(( ${up%.*} + ${SAMPLE_SECONDS:-3600} ))

while [ "${up%.*}" -lt "$end" ]; do
  read up idle < /proc/uptime
  read usage < /sys/fs/cgroup/cpu/cpuacct.usage
  read some pressure < /proc/pressure/cpu
  stats=""
  [ -r "$STATS" ] && read stats < "$STATS"
  while read key value unit; do
    [ "$key" = "VmRSS:" ] && puma=$(( value * 1024 ))
  done < /proc/1/status
  read container < "$MEMORY/memory.usage_in_bytes"
  while read key value; do
    [ "$key" = "total_inactive_file" ] && container=$(( container - value ))
  done < "$MEMORY/memory.stat"
  echo "$up $usage ${pressure##*total=} $stats $puma $container"
  sleep 1
done
