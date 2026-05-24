# Steak & Eggs

Backend for [steakneggs.app](https://steakneggs.app/) — a trading simulator with streaming market data.

Frontend repo: [steak-and-eggs-spa](https://github.com/armaaniel/steak-and-eggs-spa)

Mobile app: [steak-and-eggs-mobile](https://github.com/armaaniel/steak-and-eggs-mobile)

Price ingestion: [steak-and-eggs-ingester](https://github.com/armaaniel/steak-and-eggs-ingester)

[Notion documentation](https://www.notion.so/Steak-Eggs-3487e61da1f98087811cd2dd38b7f662)

## Architecture

- **Decoupled streaming pipeline.** A standalone Ruby process (the ingester) maintains a persistent WebSocket connection to Polygon.io and writes prices to Redis. Rails reads Redis on demand for REST endpoints and publishes to clients through ActionCable for live updates. Independent failure domains, independent scaling, push-based end-to-end.
- **Financial integrity in five layers.** Data correctness is enforced by overlapping mechanisms — database transactions, pessimistic row locks, consistent lock ordering, model validations, and database check constraints. Any one layer can fail and the others catch it. Transactions track cost basis and realized P&L.
- **Resilience by design.** The system degrades gracefully on failure — service-layer fallbacks return structured JSON shapes so the frontend renders placeholders instead of breaking, `RedisService.safe_*` wrappers rescue all Redis errors, timeouts bound every external call (Polygon, Redis, Postgres), and the ingester self-heals with automatic reconnect on stale connections or disconnects. All errors forwarded to Sentry.
- **Built-in observability.** A custom APM (DataCat) built on `ActiveSupport::Notifications` traces every controller request, accumulates per-service breakdowns, and writes asynchronously via a background thread. Tracks latency percentiles, error rates, and cache hit rates per route — no external APM service.
- **Layered caching with three freshness models.** Continuous overwrite for streaming price data, TTL-only for data the user can't directly change, and explicit invalidation for user-affected state. Plus an in-memory `Rails.cache` for the user hot path and `MGET` batching for multi-position reads.
- **Cross-platform clients.** The React/TypeScript web SPA and the React Native mobile app hit the same Rails API. Header-based JWT auth is transport-agnostic.
- **Scheduled daily portfolio snapshots** via an ECS Fargate task triggered by EventBridge Scheduler, reusing the main app task definition with a container command override to run the `record` rake task — batch processing, cache invalidation, and error tracking.
- **GitHub Actions CI/CD** runs Brakeman static analysis and a ~180-example RSpec test suite (transactional integrity, Redis caching, error fallbacks, JWT auth) on every PR, then auto-deploys to AWS ECS on merge to `main`.
- **All AWS infrastructure provisioned with Terraform** — VPC with public/private subnets, ECS Fargate (web app + standalone price ingester), RDS Postgres, ElastiCache Redis, ALB, ECR, and EventBridge Scheduler for daily tasks.

## Deep Dive

### Market Data Pipeline

**Polygon.io → Ingester → Redis → ActionCable → Frontend.** The pipeline is push-based end-to-end. Polygon pushes 15-minute-delayed prices over WebSocket to the ingester, which writes `price:<symbol>` and `open:<symbol>` to Redis (6-day TTL) and publishes to a pub/sub channel. ActionCable streams from the matching channel to subscribed clients, and the frontend updates the UI on receipt.

The ingester runs as its own ECS task — independent lifecycle, independent failure domain. Rails restarts don't drop the Polygon connection; an ingester crash doesn't affect API request handling. Polygon allows exactly one WebSocket per API key, so the ingester deploys with `minimum_healthy_percent = 0` — the old task stops before the new one starts, accepting a few seconds of price-feed downtime per deploy (Redis still holds the last prices).

Stale-connection detection during market hours (no message for 2 minutes) and disconnects trigger an automatic reconnect. Outside trading hours, silence is expected — no false-positive reconnects.

### Financial Integrity

Trades update the user balance, the position row, and a transaction record atomically within a database transaction. Five layers enforce correctness:

1. **Database transactions** — all writes succeed or all roll back.
2. **Pessimistic row locks** — `SELECT ... FOR UPDATE` on the user and position rows prevents lost updates from concurrent trades.
3. **Consistent lock ordering** — always user first, then position. Prevents deadlocks.
4. **Model validations** — balance ≥ 0, shares > 0, quantity/value > 0, case-insensitive username uniqueness.
5. **Database check constraints and unique indexes** — the same rules enforced at the database level, so they can't be bypassed by raw SQL, `update_columns`, or a future rake task.

All monetary values use `BigDecimal` in Ruby and `decimal(17,4)` in Postgres for exact arithmetic.

### Caching Strategy

Cache-aside everywhere, with three deliberately different freshness models:

1. **Continuous overwrite** (streaming data) — the ingester overwrites `price:<symbol>` and `open:<symbol>` on every tick. The 6-day TTL is a safety net for prolonged market closures, not the freshness mechanism.
2. **TTL-only** (user can't directly affect) — market snapshots (5 min), company descriptions (3 days), chart bars (24 h), ticker metadata (1 month). No invalidation logic — the next request after expiry refetches.
3. **Explicit invalidation** (user-affected state) — positions, portfolio history, activity feed. `CacheService.invalidate_user` busts the affected keys synchronously after every write.

An in-memory `Rails.cache` holds the decoded user object after JWT verification — the hottest path, zero network latency. `MGET` batching fetches all position prices in a single Redis round trip for the AUM calculation.

Every Redis call goes through `RedisService.safe_*`, which rescues errors and returns `nil` — callers fall through to Postgres or the upstream API. A Redis outage degrades to slower reads, not 500s.

### APM / Observability

A custom APM (DataCat) built on `ActiveSupport::Notifications`. Every service method wraps its logic in `instrument`, reporting duration and what it touched (Redis, database, external API). Events are accumulated synchronously per-request in a `Concurrent::Map`, then the completed trace is pushed onto a thread-safe `Queue` and written to Postgres by a background thread — keeping the INSERT off the request path.

Each `Trace` record stores total duration, DB runtime, view runtime, HTTP status, and a JSONB breakdown of service calls. The DataCat dashboard queries this via GraphQL, pushing aggregation into Postgres — `PERCENTILE_CONT` for exact P99/P95/P50 latency, conditional `FILTER` clauses for per-route cache hit rates.

### Daily Portfolio Snapshots

An EventBridge Scheduler cron triggers a standalone ECS Fargate task daily at 5 AM UTC (after US market close), reusing the main app task definition with a container command override to run `rake record`. The task iterates through all users in batches of 1,000 — one query for users, one bulk position lookup, one Redis `MGET` for all unique symbols, one `upsert_all`, one bulk cache `DEL`. Five round trips per batch regardless of user or position count.

`upsert_all` with `unique_by: [:user_id, :date]` makes the job idempotent — EventBridge retries, manual reruns, and accidental double-fires all converge to the same result. Per-user errors are isolated via a nested `rescue` so one bad row doesn't halt the snapshot for everyone.

### Resilience

Every external dependency has a bounded timeout: Polygon HTTP calls (1s connect, 2s read), Redis (1s), Postgres connections (2s). Without these, a slow upstream ties up Puma threads and cascades into a full outage.

Controller actions rescue all exceptions and return structured fallback JSON matching the success shape (`{open: 'N/A', high: 'N/A', ...}`) so the frontend always gets a renderable response. Domain errors map to specific status codes (`InsufficientFundsError` → 402). The ALB health check is deliberately shallow (`GET /` → `{status: 'ok'}`) — no Redis ping, no Postgres query — to avoid cascading failures when a downstream service is slow.

### Testing

RSpec covers models, services, requests, and channels. Tests verify buy/sell correctness (balance debits, position creation/destruction, weighted-average recalculation, realized P&L including losses), domain error mapping, Redis cache behavior (hits, misses, TTLs, invalidation), graceful degradation on `Redis::BaseError`, REST and WebSocket JWT auth, and input validation. Brakeman runs static security analysis on every PR. All specs run via GitHub Actions CI.

## Models

| Table | Description |
|---|---|
| `users` | Auth, balance tracking; has many positions, transactions, and portfolio records |
| `positions` | Symbol, share count, and weighted average cost basis per user |
| `transactions` | Trade history with market price at execution and realized P&L |
| `portfolio_records` | Daily snapshots of portfolio value |
| `tickers` | Symbol reference data (name, exchange, type, currency) |
| `traces` | Per-request APM data with JSONB service call breakdown |

## API

Three surfaces: REST (trading app), WebSocket (live prices via ActionCable), and GraphQL (observability dashboard). JWT authentication via the `authToken` header; WebSocket auth via query params.

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/signup` | Create account |
| `POST` | `/login` | Authenticate, receive JWT |
| `POST` | `/demo` | Create demo account ($250k + starter positions) |
| `POST` | `/change_password` | Update password |
| `DELETE` | `/delete_account` | Destroy user and all associated data |
| `GET` | `/` | Health check |
| `POST` | `/deposit` | Add funds |
| `POST` | `/withdraw` | Withdraw funds |
| `GET` | `/search` | Ticker search |
| `GET` | `/portfoliochart` | Historical portfolio value |
| `GET` | `/portfoliodata` | Current AUM + positions with live prices |
| `GET` | `/activitydata` | Transaction history |
| `GET` | `/stocks/:symbol/tickerdata` | Ticker reference info |
| `GET` | `/stocks/:symbol/chartdata` | 5-month daily price chart |
| `GET` | `/stocks/:symbol/companydata` | Market cap + description |
| `GET` | `/stocks/:symbol/marketdata` | Intraday OHLV snapshot |
| `GET` | `/stocks/:symbol/stockprice` | Live price + daily open |
| `GET` | `/stocks/:symbol/userdata` | User's position + balance for symbol |
| `POST` | `/stocks/:symbol/buy` | Execute buy order |
| `POST` | `/stocks/:symbol/sell` | Execute sell order |
| `WS` | `/cable` | ActionCable (live price subscriptions) |
| `POST` | `/graphql` | DataCat/APM queries |

**Tech Stack:** Rails 8 · PostgreSQL · Redis · ActionCable · Polygon.io · AWS (ECS Fargate, RDS, ElastiCache, ALB, EventBridge Scheduler) · Terraform · GraphQL · Sentry
