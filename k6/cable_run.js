import http from 'k6/http'
import secrets from 'k6/secrets'
import { WebSocket } from 'k6/websockets'

const BASE = 'https://www.steakneggs.art'
const WS = 'wss://www.steakneggs.art/cable'

const SYMBOLS = ['LOAD_01', 'LOAD_02', 'LOAD_03', 'LOAD_04', 'LOAD_05',
                 'LOAD_06', 'LOAD_07', 'LOAD_08', 'LOAD_09', 'LOAD_10']

const BUCKET = 5000
const RESERVOIR = 10
const FLUSH_BASE = 60000
const FLUSH_JITTER = 10000
const SUSPECT_WINDOW = 100
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
  const buckets = new Map()
  const startedAt = Date.now()

  let firstFrameAt = 0
  let flushEndedAt = 0
  let inFlight = false
  let nextFlush = startedAt + FLUSH_BASE + Math.random() * FLUSH_JITTER

  const bucketFor = (ts) => {
    const key = Math.floor(ts / BUCKET) * BUCKET
    if (!buckets.has(key)) {
      buckets.set(key, { at: key, frames: 0, cleanFrames: 0, sumLag: 0, seen: 0, lags: [] })
    }
    return buckets.get(key)
  }

  const restore = (rows) => {
    for (const row of rows) {
      const b = bucketFor(row.at)
      b.frames += row.frames
      b.cleanFrames += row.clean_frames
      b.sumLag += row.sum_lag_ms
      b.seen += row.frames
      for (const lag of row.sample_lags) {
        if (b.lags.length < RESERVOIR) b.lags.push(lag)
      }
    }
  }

  const drain = (closing) => {
    const cutoff = Math.floor(Date.now() / BUCKET) * BUCKET
    const rows = []

    for (const [key, b] of buckets) {
      if (!closing && key >= cutoff) continue
      rows.push({
        at: b.at,
        vu: vu,
        frames: b.frames,
        clean_frames: b.cleanFrames,
        sum_lag_ms: b.sumLag,
        sample_lags: b.lags,
      })
      buckets.delete(key)
    }

    return rows
  }

  const params = () => ({
    headers: { 'Content-Type': 'application/json', 'Synthetic-Key': data.key },
    timeout: '30s',
  })

  const settle = (ok, rows) => {
    inFlight = false
    flushEndedAt = Date.now()
    if (!ok) restore(rows)
  }

  const flush = () => {
    if (inFlight) return
    const rows = drain(false)
    if (!rows.length) return

    inFlight = true
    const body = JSON.stringify({ run_id: data.runId, samples: rows })

    http.asyncRequest('POST', `${BASE}/cable_samples`, body, params()).then(
      (res) => settle(res.status === 201, rows),
      () => settle(false, rows)
    )
  }

  const flushFinal = () => {
    const rows = drain(true)
    if (!rows.length) return
    const body = JSON.stringify({ run_id: data.runId, samples: rows })
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
    if (!firstFrameAt) firstFrameAt = now

    const payload = typeof frame.message === 'string' ? JSON.parse(frame.message) : frame.message
    const lag = now - payload.t
    const b = bucketFor(payload.t)

    b.frames += 1

    if (now - flushEndedAt >= SUSPECT_WINDOW) {
      b.cleanFrames += 1
      b.sumLag += lag
      b.seen += 1

      if (b.lags.length < RESERVOIR) {
        b.lags.push(lag)
      } else {
        const j = Math.floor(Math.random() * b.seen)
        if (j < RESERVOIR) b.lags[j] = lag
      }
    }

    if (now >= nextFlush) {
      flush()
      nextFlush = Date.now() + FLUSH_BASE + Math.random() * FLUSH_JITTER
    }

    if (now - firstFrameAt >= RUN_MS) {
      flushFinal()
      ws.close()
    }
  }

  ws.onclose = () => {
    flushFinal()
  }

  ws.onerror = (e) => {
    console.error(`vu ${vu} socket error: ${e && e.error}`)
  }
}