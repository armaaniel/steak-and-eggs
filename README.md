# Steak & Eggs

Backend for [steakneggs.app](https://steakneggs.app/) — a trading simulator with streaming market data.

## Architecture

- Rails backend maintains persistent WebSocket connection to market data provider, publishing prices to Redis and broadcasting to clients via Rails ActionCable
- React/TypeScript frontend subscribes to ActionCable channels via a WebSocket connection for real-time price updates
- Implemented connection health monitoring with automatic reconnect to market data provider on stale connections or disconnects
- Built APM tool using Rails instrumentation that tracks P99 latency per route, individual request latency, service call breakdown, and cache hit rates
- Scheduled daily portfolio snapshots for each user via AWS Lambda with batch processing, cache invalidation, and error tracking
- Financial transactions use pessimistic locking and database transactions; Transactions track cost basis and realized P&L
- API layer returns graceful fallbacks in the event of service failures and logs errors to Sentry

---

## Deep Dive

### Market Data Connection

A background thread maintains a persistent WebSocket connection to Polygon.io, a streaming data provider, ingesting live prices for all tracked stock tickers. Prices are cached in Redis and broadcast to clients via ActionCable channels. Stale connections and disconnects trigger an automatic reconnect.

### Caching Strategy

Redis sits in front of most reads. Market snapshots cache for 5 minutes, company data for 3 days, and chart data for 24 hours. The `MarketService` and `PositionService` layers check Redis first and fall back to Polygon.io or Postgres, with all cache hits/misses tracked via instrumentation.

### APM / Observability

`ActiveSupport::Notifications` instruments every controller request. Each service call (`MarketService`, `PositionService`, `Ticker`) tracks its duration and whether it hit Redis, the database, or the external API. These are stored on a `Trace` record alongside total duration, DB runtime, view runtime, and HTTP status — enabling P99 analysis and per-route performance debugging via a separate internal tool.

### Daily Portfolio Snapshots

An AWS Lambda function runs daily, hitting an authenticated endpoint that iterates through all users in batches of 100. For each user, it calculates their current AUM by bulk-fetching the current value of their positions and reducing them alongside their cash balance, saving the result as a new `PortfolioRecord`.

### Error Handling

Every controller action rescues exceptions and returns structured fallback responses (e.g. `{open: 'N/A', high: 'N/A', ...}`) so the frontend degrades gracefully rather than crashing. All caught errors are forwarded to Sentry.

## Models

| Table | Description |
|---|---|
| `users` | Auth, balance tracking; has many positions, transactions, and portfolio records |
| `positions` | Symbol, share count, and weighted average cost basis per user |
| `transactions` | Trade history with market price at execution and realized P&L |
| `portfolio_records` | Daily snapshots of portfolio value |
| `tickers` | Symbol reference data (name, exchange, type, currency) |
| `traces` | Per-request APM data with service call breakdown |

## API

Most endpoints require JWT authentication.

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/signup` | Create account |
| `POST` | `/login` | Authenticate, receive JWT |
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
| `POST` | `/stocks/:symbol/buy` | Execute buy order |
| `POST` | `/stocks/:symbol/sell` | Execute sell order |
| `WS` | `/cable` | ActionCable (live price subscriptions) |
| `POST` | `/graphql` | GraphQL endpoint |

**Tech Stack:** Rails 8 · PostgreSQL · Redis · ActionCable · Polygon.io · AWS · GraphQL · Sentry
