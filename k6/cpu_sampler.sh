STATS=/tmp/runtime_stats

read up idle < /proc/uptime
echo "start $(date +%s) $up $(grep -m1 'CPU part' /proc/cpuinfo | tr -d ' \t')"
end=$(( ${up%.*} + ${SAMPLE_SECONDS:-3600} ))

while [ "${up%.*}" -lt "$end" ]; do
  read up idle < /proc/uptime
  read usage < /sys/fs/cgroup/cpu/cpuacct.usage
  read some pressure < /proc/pressure/cpu
  stats=""
  [ -r "$STATS" ] && read stats < "$STATS"
  echo "$up $usage ${pressure##*total=} $stats"
  sleep 1
done
