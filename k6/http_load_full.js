import http from 'k6/http'
import { check } from 'k6'
import secrets from 'k6/secrets'

const BASE = 'https://www.steakneggs.art'
const ROUTE = 'stockprice'
const SYMBOL = 'AAPL'

export const options = {
  scenarios: {
    ramp: {
      executor: 'ramping-arrival-rate',
      startRate: 20,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: 400,
      stages: [
  { target: 20, duration: '2m' },                                  // warmup, discard
  { target: 50, duration: '30s' }, { target: 50, duration: '4m' },
  { target: 65, duration: '30s' }, { target: 65, duration: '4m' },
  { target: 75, duration: '30s' }, { target: 75, duration: '4m' },
  { target: 85, duration: '30s' }, { target: 85, duration: '4m' },
],
    },
  },
  thresholds: {
  dropped_iterations: ['count<1'],
},
}

export async function setup() {
  return {
    runId: crypto.randomUUID(),
    key: await secrets.get('synthetic-key'),
  }
}

let buffer = []
let lastFlush = Date.now()

export default function (data) {
  const reqId = crypto.randomUUID()

  const res = http.get(`${BASE}/stocks/${SYMBOL}/stockprice`, {
    headers: {
      'Synthetic-Key': data.key,
      'Synthetic-Source': 'load',
      'Synthetic-Run-Id': data.runId,
      'X-Load-Request-Id': reqId,
    },
  })

  check(res, { 'status 200': (r) => r.status === 200 })

  buffer.push({
    request_id: reqId,
    at: Date.now(),
    route: ROUTE,
    waiting: Math.round(res.timings.waiting),
    duration: Math.round(res.timings.duration),
    status: res.status,
  })

  if (buffer.length >= 200 || Date.now() - lastFlush > 20000) flush(data)
}

function flush(data) {
  if (!buffer.length) return
  const batch = buffer.splice(0)
  lastFlush = Date.now()
  http.post(
    `${BASE}/load_samples`,
    JSON.stringify({ run_id: data.runId, samples: batch }),
    {
      headers: { 'Content-Type': 'application/json', 'Synthetic-Key': data.key },
      timeout: '30s',
    }
  )
}

export function teardown(data) {
  flush(data)
}