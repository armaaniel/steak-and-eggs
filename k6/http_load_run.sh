#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${1:-${SCRIPT_DIR}/http_load_50rps.js}"
SECRETS="${SCRIPT_DIR}/secrets.txt"
RUN_ID="${RUN_ID:-$(uuidgen | tr '[:upper:]' '[:lower:]')}"
OUT="${SCRIPT_DIR}/runs/${RUN_ID}.csv.gz"

source "${SCRIPT_DIR}/sampler.sh"

mkdir -p "${SCRIPT_DIR}/runs"
echo "run_id: ${RUN_ID}"

start_sampler "${SCRIPT_DIR}/runs/${RUN_ID}.cpu.log"
sleep $(( 60 - 10#$(date +%S) ))
echo "k6 start: $(date -u +%H:%M:%S) UTC"

K6_STATUS=0
caffeinate -i k6 run -e RUN_ID="${RUN_ID}" --secret-source=file="${SECRETS}" --out csv="${OUT}" "${SCRIPT}" || K6_STATUS=$?

sleep "${SAMPLER_WARMUP}"
stop_sampler

SYNTHETIC_KEY="$(sed -n 's/^synthetic-key=//p' "${SECRETS}")" ruby "${SCRIPT_DIR}/import_samples.rb" "${OUT}" "${RUN_ID}"
import_metrics "${RUN_ID}"

echo
echo "run_id: ${RUN_ID}"
exit "${K6_STATUS}"
