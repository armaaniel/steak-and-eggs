import http from 'k6/http'
import exec from 'k6/execution'
import { check } from 'k6'
import secrets from 'k6/secrets'

const BASE = 'https://www.steakneggs.art'
const ROUTE = 'stockprice'
const SYMBOL = 'AAPL'

export const options = {
  scenarios: {
    ramp: {
      executor: 'ramping-arrival-rate',
      startRate: 50,
      timeUnit: '1s',
      preAllocatedVUs: 150,
      maxVUs: 400,
      stages: [
        { target: 50, duration: '2m' },                                  // warmup, discard
        { target: 50, duration: '3m' },
        { target: 100, duration: '30s' }, { target: 100, duration: '2m30s' },
        { target: 150, duration: '30s' }, { target: 150, duration: '2m30s' },
        { target: 200, duration: '30s' }, { target: 200, duration: '2m30s' },
        { target: 250, duration: '30s' }, { target: 250, duration: '2m30s' },
        { target: 300, duration: '30s' }, { target: 300, duration: '2m30s' },
        { target: 350, duration: '30s' }, { target: 350, duration: '2m30s' },
      ],
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
