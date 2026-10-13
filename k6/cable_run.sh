#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RUN_ID="${RUN_ID:-$(uuidgen)}"

CLUSTER=steakneggs
TASK_DEF=steakneggs
CONTAINER=steakneggs
CONNECT_GRACE=45

source "${SCRIPT_DIR}/sampler.sh"

SUBNETS=$(terraform -chdir="${REPO_ROOT}" output -json ecs_subnets | jq -r 'join(",")')
SG=$(terraform -chdir="${REPO_ROOT}" output -raw ecs_security_group)

mkdir -p "${SCRIPT_DIR}/runs"
echo "run_id: ${RUN_ID}"

start_sampler "${SCRIPT_DIR}/runs/${RUN_ID}.cpu.log"

k6 cloud run -e RUN_ID="${RUN_ID}" "${SCRIPT_DIR}/cable_run.js" &
K6_PID=$!

echo "waiting ${CONNECT_GRACE}s for cloud provisioning"
sleep "${CONNECT_GRACE}"

OVERRIDES=$(jq -nc \
  --arg container "${CONTAINER}" \
  --arg run_id "${RUN_ID}" \
  '{containerOverrides: [{
      name: $container,
      command: ["rake", "cable_publish"],
      environment: [{name: "RUN_ID", value: $run_id}]
   }]}')

TASK_ARN=$(aws ecs run-task \
  --cluster "${CLUSTER}" \
  --task-definition "${TASK_DEF}" \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[${SUBNETS}],securityGroups=[${SG}],assignPublicIp=ENABLED}" \
  --overrides "${OVERRIDES}" \
  --query 'tasks[0].taskArn' \
  --output text)

echo "publisher: ${TASK_ARN}"

K6_STATUS=0
wait "${K6_PID}" || K6_STATUS=$?
aws ecs wait tasks-stopped --cluster "${CLUSTER}" --tasks "${TASK_ARN}" || true

sleep "${SAMPLER_WARMUP}"
stop_sampler
import_metrics "${RUN_ID}"

echo
echo "run_id: ${RUN_ID}"
exit "${K6_STATUS}"
