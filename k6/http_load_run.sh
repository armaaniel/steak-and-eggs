#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${1:-${SCRIPT_DIR}/http_load_50rps.js}"
SECRETS="${SCRIPT_DIR}/secrets.txt"
RUN_ID="${RUN_ID:-$(uuidgen | tr '[:upper:]' '[:lower:]')}"
OUT="${SCRIPT_DIR}/runs/${RUN_ID}.csv.gz"
CPU_LOG="${SCRIPT_DIR}/runs/${RUN_ID}.cpu.log"

CLUSTER=steakneggs
SERVICE=steakneggs
SAMPLER_WARMUP=5

mkdir -p "${SCRIPT_DIR}/runs"
echo "run_id: ${RUN_ID}"

TASK=$(aws ecs list-tasks --cluster "${CLUSTER}" --service-name "${SERVICE}" --query 'taskArns[0]' --output text)
SAMPLER=$(base64 < "${SCRIPT_DIR}/cpu_sampler.sh" | tr -d '\n')

( sleep 86400 | aws ecs execute-command --cluster "${CLUSTER}" --task "${TASK}" --container "${SERVICE}" --interactive \
    --command "sh -c 'echo ${SAMPLER} | base64 -d | sh'" > "${CPU_LOG}" 2>&1 ) 2>/dev/null &
SAMPLER_PID=$!

stop_sampler() {
  [ -n "${SAMPLER_STOPPED:-}" ] && return
  SAMPLER_STOPPED=1

  local session
  session=$(grep -o 'ecs-execute-command-[a-z0-9]*' "${CPU_LOG}" | head -1 || true)
  if [ -n "${session}" ]; then
    aws ssm terminate-session --session-id "${session}" > /dev/null 2>&1 || true
  fi

  pkill -f "session-manager-plugin.*${TASK##*/}" || true
  pkill -P "${SAMPLER_PID}" || true
}
trap stop_sampler EXIT

sleep "${SAMPLER_WARMUP}"
sleep $(( 60 - 10#$(date +%S) ))
echo "k6 start: $(date -u +%H:%M:%S) UTC"

K6_STATUS=0
caffeinate -i k6 run -e RUN_ID="${RUN_ID}" --secret-source=file="${SECRETS}" --out csv="${OUT}" "${SCRIPT}" || K6_STATUS=$?

sleep "${SAMPLER_WARMUP}"
stop_sampler

SYNTHETIC_KEY="$(sed -n 's/^synthetic-key=//p' "${SECRETS}")"
SYNTHETIC_KEY="${SYNTHETIC_KEY}" ruby "${SCRIPT_DIR}/import_samples.rb" "${OUT}" "${RUN_ID}"
SYNTHETIC_KEY="${SYNTHETIC_KEY}" ruby "${SCRIPT_DIR}/import_metrics.rb" "${CPU_LOG}" "${RUN_ID}" || echo "run metrics import failed, rerun k6/import_metrics.rb later"

echo
ruby "${SCRIPT_DIR}/cpu_summary.rb" "${CPU_LOG}"

echo
echo "run_id: ${RUN_ID}"
exit "${K6_STATUS}"
