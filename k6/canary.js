import http from 'k6/http'
import { group } from 'k6'
import secrets from 'k6/secrets'
import { expect as baseExpect } from 'https://jslib.k6.io/k6-testing/0.6.1/index.js'

const BASE = 'https://www.steakneggs.art'
const SYMBOL = 'AAPL'
const DEPOSIT = 10000
const expect = baseExpect.configure({ soft: true, softMode: 'throw' })

const BASKET = ['AAPL', 'MSFT', 'NVDA', 'AMZN', 'GOOG', 'META', 'TSLA']
const searchTerm = BASKET[Math.floor(Date.now() / 86400000) % BASKET.length]

const username = `canary_${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`
const password = 'pr0be-pass-a1'
const newPassword = 'pr0be-pass-b2'

const CENT = 0.01

export default async function () {
  const SYNTHETIC_KEY = await secrets.get('synthetic-key')
  const runId = crypto.randomUUID()


  const base = { 'Content-Type': 'application/json', 'Synthetic-Key': SYNTHETIC_KEY, 'Synthetic-Run-Id': runId, 'Synthetic-Source': 'canary' }
  let token = ''
  let failed = false
  let buyPrice = 0
  const auth = () => ({ ...base, authToken: token })

  try {
    group('signup', () => {
      const res = http.post(`${BASE}/signup`, JSON.stringify({ username, password }), {
        headers: base,
      })
      expect(res.status).toBe(200)
      const body = res.json()
      expect(body.username).toBe(username)
      expect(body.token).toBeTruthy()
      token = body.token
    })

    group('login', () => {
      const res = http.post(`${BASE}/login`, JSON.stringify({ username, password }), {
        headers: base,
      })
      expect(res.status).toBe(200)
      token = res.json().token
      expect(token).toBeTruthy()
    })

    group('deposit', () => {
      const res = http.post(`${BASE}/deposit`, JSON.stringify({ amount: String(DEPOSIT) }), {
        headers: auth(),
      })
      expect(res.status).toBe(200) // head(:ok), empty body — verified via balance below
    })

    group('search', () => {
      const res = http.get(`${BASE}/search?q=${searchTerm}`, { headers: auth() })
      expect(res.status).toBe(200)
      expect(res.json().length).toBeGreaterThan(0)
    })

    group('stock price', () => {
      const res = http.get(`${BASE}/stocks/${SYMBOL}/stockprice`, { headers: auth() })
      expect(res.status).toBe(200)
      expect(Number(res.json().price)).toBeGreaterThan(0)
    })

    group('market data', () => {
      const res = http.get(`${BASE}/stocks/${SYMBOL}/marketdata`, { headers: auth() })
      expect(res.status).toBe(200)
      expect(Number(res.json().open)).toBeGreaterThan(0)
      // Specs stub the HTTP call to polygon, an expired API key is invisible there and visible here.
    })

    group('buy', () => {
      const res = http.post(`${BASE}/stocks/${SYMBOL}/buy`, JSON.stringify({ quantity: 1 }), {
        headers: auth(),
      })
      expect(res.status).toBe(201)
      const body = res.json()
      expect(body.symbol).toBe(SYMBOL)
      expect(Number(body.quantity)).toBe(1)
      expect(Number(body.market_price)).toBeGreaterThan(0)
      buyPrice = Number(body.market_price)
    })

    group('portfolio data', () => {
      const res = http.get(`${BASE}/portfoliodata`, { headers: auth() })
      expect(res.status).toBe(200)
      const body = res.json()

      expect(body.positions).toBeDefined()
      expect(body.positions.length).toBe(1) // the buy created exactly one position
      expect(body.positions[0].symbol).toBe(SYMBOL)

      expect(Number(body.positions[0].average_price)).toBe(buyPrice)

      expect(Math.abs(Number(body.balance) - (DEPOSIT - buyPrice))).toBeLessThan(CENT)

      // internal arithmetic of this one response: aum = balance + sum(price * shares)
      const held = Number(body.positions[0].price) * Number(body.positions[0].shares)
      expect(Math.abs(Number(body.aum) - (Number(body.balance) + held))).toBeLessThan(CENT)
    })

    group('sell', () => {
      const res = http.post(`${BASE}/stocks/${SYMBOL}/sell`, JSON.stringify({ quantity: 1 }), {
        headers: auth(),
      })
      expect(res.status).toBe(201)
      // toBeDefined() passes on null; realized_pnl must be an actual number (may be 0 or negative)
      expect(Number.isFinite(Number(res.json().realized_pnl))).toBe(true)
    })

    group('activity', () => {
      const res = http.get(`${BASE}/activitydata`, { headers: auth() })
      expect(res.status).toBe(200)
      expect(res.json().length).toBe(3) // exactly deposit, buy, sell
    })

    group('portfolio chart', () => {
      const res = http.get(`${BASE}/portfoliochart`, { headers: auth() })
      expect(res.status).toBe(200)
      const chart = res.json()
      expect(Number(chart[chart.length - 1].value)).toBeGreaterThan(0)
    })

    group('withdraw', () => {
      const res = http.post(`${BASE}/withdraw`, JSON.stringify({ amount: '100' }), {
        headers: auth(),
      })
      expect(res.status).toBe(200)
    })

    group('change password', () => {
      const res = http.post(
        `${BASE}/change_password`,
        JSON.stringify({ new_password: newPassword }),
        { headers: auth() }
      )
      expect(res.status).toBe(200)
    })

    group('delete account', () => {
      const res = http.del(`${BASE}/delete_account`, null, { headers: auth() })
      expect(res.status).toBe(200)
    })

    group('deleted token rejected', () => {
      const res = http.get(`${BASE}/portfoliodata`, { headers: auth() })
      expect(res.status).toBe(401)
      // Rails.cache is a null store under RSpec, this tests the cache entry is actually evicted
    })
  } catch (e) {
    failed = true
    throw e
  } finally {
	  const headers = { ...base, 'Synthetic-Result': failed ? 'fail' : 'pass' }
		if (token) headers.authToken = token
		http.del(`${BASE}/delete_account`, null, { headers })
	}
}