SAMPLER_CLUSTER=steakneggs
SAMPLER_SERVICE=steakneggs
SAMPLER_WARMUP=5

start_sampler() {
  SAMPLER_LOG="$1"
  SAMPLER_TASK=$(aws ecs list-tasks --cluster "${SAMPLER_CLUSTER}" --service-name "${SAMPLER_SERVICE}" --query 'taskArns[0]' --output text)

  local script
  script=$(base64 < "${SCRIPT_DIR}/cpu_sampler.sh" | tr -d '\n')

  ( sleep 86400 | aws ecs execute-command --cluster "${SAMPLER_CLUSTER}" --task "${SAMPLER_TASK}" --container "${SAMPLER_SERVICE}" --interactive \
      --command "sh -c 'echo ${script} | base64 -d | sh'" > "${SAMPLER_LOG}" 2>&1 ) 2>/dev/null &
  SAMPLER_PID=$!

  trap stop_sampler EXIT
  sleep "${SAMPLER_WARMUP}"
}

stop_sampler() {
  [ -z "${SAMPLER_PID:-}" ] && return
  [ -n "${SAMPLER_STOPPED:-}" ] && return
  SAMPLER_STOPPED=1

  local session
  session=$(grep -o 'ecs-execute-command-[a-z0-9]*' "${SAMPLER_LOG}" | head -1 || true)
  if [ -n "${session}" ]; then
    aws ssm terminate-session --session-id "${session}" > /dev/null 2>&1 || true
  fi

  pkill -f "session-manager-plugin.*${SAMPLER_TASK##*/}" || true
  pkill -P "${SAMPLER_PID}" || true
}

import_metrics() {
  local key
  key="$(sed -n 's/^synthetic-key=//p' "${SCRIPT_DIR}/secrets.txt")"

  SYNTHETIC_KEY="${key}" ruby "${SCRIPT_DIR}/import_metrics.rb" "${SAMPLER_LOG}" "$1" || echo "run metrics import failed, rerun k6/import_metrics.rb later"
  echo
  ruby "${SCRIPT_DIR}/cpu_summary.rb" "${SAMPLER_LOG}"
}
