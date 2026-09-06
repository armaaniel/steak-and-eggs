import http from 'k6/http'
import secrets from 'k6/secrets'
import { WebSocket } from 'k6/websockets'

const BASE = 'https://www.steakneggs.art'
const WS = 'wss://www.steakneggs.art/cable'

const SYMBOLS = ['LOAD_01', 'LOAD_02', 'LOAD_03', 'LOAD_04', 'LOAD_05',
                 'LOAD_06', 'LOAD_07', 'LOAD_08', 'LOAD_09', 'LOAD_10']

const BUCKET = 5000        // ms per cable_samples row
const RESERVOIR = 10       // raw lag values kept per bucket, for percentiles
const FLUSH_BASE = 60000   // ms between flushes
const FLUSH_JITTER = 10000 // spread so 100 VUs don't align on one tick
const SUSPECT_WINDOW = 500 // ms after a flush returns where timings are unreliable
const RUN_MS = 1130000  // must be under the publisher's total; deadline fires while frames still flow

export const options = {
	cloud: {
		distribution: {
			west: { loadZone: 'amazon:us:palo alto', percent: 100 },
		},
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
  let nextFlush = startedAt + FLUSH_BASE + Math.random() * FLUSH_JITTER

  const bucketFor = (now) => {
    const key = Math.floor(now / BUCKET) * BUCKET
    if (!buckets.has(key)) {
      buckets.set(key, { at: key, frames: 0, sumLag: 0, seen: 0, lags: [], suspect: false })
    }
    return buckets.get(key)
  }

  const flush = (closing) => {
    const now = Date.now()
    const done = []

    for (const [key, b] of buckets) {
      // keep the in-progress bucket unless we're shutting down
      if (!closing && key >= Math.floor(now / BUCKET) * BUCKET) continue
      done.push({
        at: b.at,
        vu: vu,
        frames: b.frames,
        sum_lag_ms: b.sumLag,
        sample_lags: b.lags,
        suspect: b.suspect,
      })
      buckets.delete(key)
    }

    if (!done.length) return

    // Synchronous — blocks this VU's event loop, so frames arriving during the POST
    // queue and stamp late on delivery. That's what flushEndedAt marks.
    http.post(
      `${BASE}/cable_samples`,
      JSON.stringify({ run_id: data.runId, samples: done }),
      {
        headers: { 'Content-Type': 'application/json', 'Synthetic-Key': data.key },
        timeout: '30s',
      }
    )

    flushEndedAt = Date.now()
  }

	const ws = new WebSocket(WS, null, {
	  headers: { Origin: BASE },
	})
	
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

    // welcome, confirm_subscription, and a ping every 3s all arrive on this socket.
    // Only frames carrying an identifier and a message are broadcasts.
    if (!frame.identifier || frame.message === undefined) return
		if (!firstFrameAt) firstFrameAt = now

    const payload = typeof frame.message === 'string' ? JSON.parse(frame.message) : frame.message
    const lag = now - payload.t

    const b = bucketFor(now)
    b.frames += 1
    b.sumLag += lag
    b.seen += 1

    if (now - flushEndedAt < SUSPECT_WINDOW) b.suspect = true

    if (b.lags.length < RESERVOIR) {
      b.lags.push(lag)
    } else {
      const j = Math.floor(Math.random() * b.seen)
      if (j < RESERVOIR) b.lags[j] = lag
    }

    if (now >= nextFlush) {
      flush(false)
      nextFlush = Date.now() + FLUSH_BASE + Math.random() * FLUSH_JITTER
    }

		if (now - firstFrameAt >= RUN_MS) {
		  flush(true)
		  ws.close()
		}
  }

  ws.onclose = () => {
    flush(true)
  }

  ws.onerror = (e) => {
    console.error(`vu ${vu} socket error: ${e && e.error}`)
  }
}