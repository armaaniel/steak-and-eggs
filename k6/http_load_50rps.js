import http from 'k6/http'
import exec from 'k6/execution'
import { check } from 'k6'
import secrets from 'k6/secrets'

//   Flushes cost 4% CPU, APM costs 31% or 10% after refactor

const BASE = 'https://www.steakneggs.art'
const ROUTE = 'stockprice'
const SYMBOL = 'AAPL'

export const options = {
  scenarios: {
    flat: {
      executor: 'constant-arrival-rate',
      rate: 50,
      timeUnit: '1s',
      duration: '3m',
      preAllocatedVUs: 20,
      maxVUs: 50,
    },
  },
  thresholds: {
    dropped_iterations: ['count<1'],
  },
}

export async function setup() {
  return {
    runId: __ENV.RUN_ID,
    key: await secrets.get('synthetic-key'),
  }
}

export default function (data) {
  const reqId = crypto.randomUUID()
  exec.vu.metrics.metadata.request_id = reqId
  exec.vu.metrics.metadata.route = ROUTE
  exec.vu.metrics.metadata.sent_at = String(Date.now())

  const res = http.get(`${BASE}/stocks/${SYMBOL}/stockprice`, {
    headers: {
      'Synthetic-Key': data.key,
      'Synthetic-Source': 'load',
      'Synthetic-Run-Id': data.runId,
      'X-Load-Request-Id': reqId,
    },
  })

  check(res, { 'status 200': (r) => r.status === 200 })
}
