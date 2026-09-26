import http from 'k6/http'
import secrets from 'k6/secrets'
import { WebSocket } from 'k6/websockets'

const BASE = 'https://www.steakneggs.art'
const WS = 'wss://www.steakneggs.art/cable'

const SYMBOLS = ['LOAD_01', 'LOAD_02', 'LOAD_03', 'LOAD_04', 'LOAD_05',
                 'LOAD_06', 'LOAD_07', 'LOAD_08', 'LOAD_09', 'LOAD_10']

const BUCKET = 5000
const FLUSH_BASE = 60000
const FLUSH_JITTER = 10000
const RUN_MS = 1130000

export const options = {
  cloud: {
    distribution: { west: { loadZone: 'amazon:us:palo alto', percent: 100 } },
  },
  scenarios: {
    hold: {
      executor: 'per-vu-iterations',
      vus: 100,
      iterations: 1,
      maxDuration: '30m',
    },
  },
}

export async function setup() {
  return {
    runId: __ENV.RUN_ID || crypto.randomUUID(),
    key: await secrets.get('synthetic-key'),
  }
}

export default function (data) {
  const vu = __VU
  const received = new Map()
  const startedAt = Date.now()

  let firstFrameAt = 0
  let flushing = false
  let nextFlush = startedAt + FLUSH_BASE + Math.random() * FLUSH_JITTER
  let stopTimer

  function params() {
    return {
      headers: { 'Content-Type': 'application/json', 'Synthetic-Key': data.key },
      timeout: '30s',
    }
  }

  function bucketStart(time) {
    return Math.floor(time / BUCKET) * BUCKET
  }

  function bucketFor(time) {
    const start = bucketStart(time)

    if (!received.has(start)) {
      received.set(start, { at: start, frames: 0, lags: [] })
    }
    return received.get(start)
  }

  function extractSamples({ final = false } = {}) {
    const currentBucket = bucketStart(Date.now())
    const samples = []

    for (const [start, bucket] of received) {
      if (final || start < currentBucket) {
        samples.push({
          at: bucket.at,
          vu,
          frames: bucket.frames,
          lags: bucket.lags,
        })
        received.delete(start)
      }
    }

    return samples
  }

  async function flush() {
    if (flushing) return
    const samples = extractSamples()
    if (samples.length === 0) return

    flushing = true
    const body = JSON.stringify({ run_id: data.runId, samples: samples })

    try {
      const res = await http.asyncRequest('POST', `${BASE}/cable_samples`, body, params())
      if (res.status !== 201) throw new Error(`status ${res.status}`)
    } catch (e) {
      for (const sample of samples) {
        const bucket = bucketFor(sample.at)
        bucket.frames += sample.frames
        bucket.lags.push(...sample.lags)
      }
    } finally {
      flushing = false
    }
  }

  function flushFinal() {
    const samples = extractSamples({ final: true })
    if (samples.length === 0) return

    const body = JSON.stringify({ run_id: data.runId, samples })
    http.post(`${BASE}/cable_samples`, body, params())
  }

  const ws = new WebSocket(WS, null, { headers: { Origin: BASE } })

  ws.onopen = () => {
    for (const symbol of SYMBOLS) {
      ws.send(JSON.stringify({
        command: 'subscribe',
        identifier: JSON.stringify({ channel: 'PriceChannel', symbol: symbol }),
      }))
    }
  }

  ws.onmessage = (e) => {
    const now = Date.now()
    const frame = JSON.parse(e.data)

    if (!frame.identifier || frame.message === undefined) return
    if (!firstFrameAt) {
      firstFrameAt = now
      stopTimer = setTimeout(() => ws.close(), RUN_MS)
    }
    const payload = typeof frame.message === 'string' ? JSON.parse(frame.message) : frame.message

    const publishedAt = payload.t
    const lag = now - publishedAt
    const bucket = bucketFor(publishedAt)

    bucket.frames += 1
    bucket.lags.push(lag)

    if (now >= nextFlush) {
      flush()
      nextFlush = Date.now() + FLUSH_BASE + Math.random() * FLUSH_JITTER
    }
  }

  ws.onclose = () => {
    clearTimeout(stopTimer)
    flushFinal()
  }

  ws.onerror = (e) => {
    console.error(`vu ${vu} socket error: ${e && e.error}`)
  }
}