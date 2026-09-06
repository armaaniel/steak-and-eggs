import http from 'k6/http'
import { check } from 'k6'
import secrets from 'k6/secrets'

//   Flushes cost 4% CPU, APM costs 34%. 45% No trace_queue, 49% No trace_queue with flushes

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