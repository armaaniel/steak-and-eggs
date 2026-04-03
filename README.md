# Steak & Eggs

Backend for [steakneggs.app](https://steakneggs.app/) — a trading simulator with streaming market data.

Frontend repo: [steak-and-eggs-spa](https://github.com/armaaniel/steak-and-eggs-spa)

Mobile app: [steak-and-eggs-mobile](https://github.com/armaaniel/steak-and-eggs-mobile)

Price ingestion: [steak-and-eggs-ingester](https://github.com/armaaniel/steak-and-eggs-ingester)

## Architecture

- Standalone price ingestion service ([steak-and-eggs-ingester](https://github.com/armaaniel/steak-and-eggs-ingester)) maintains persistent WebSocket connection to market data provider, publishing prices to Redis — decoupled from the backend for independent scaling and deploys
- React/TypeScript frontend subscribes to ActionCable channels via a WebSocket connection for real-time price updates
- DataCat, an in-app APM dashboard, tracks latency percentiles per route, individual request latency, error rates, and cache hit rates — powered by Rails instrumentation
- Connection health monitoring on the ingestion service with automatic reconnect on stale connections or disconnects
- Scheduled daily portfolio snapshots for each user via AWS Lambda with batch processing, cache invalidation, and error tracking
- Financial transactions use pessimistic locking and database transactions; Transactions track cost basis and realized P&L
- API layer returns graceful fallbacks in the event of service failures and logs errors to Sentry
- GitHub Actions CI/CD pipeline runs a ~180-example RSpec test suite (transactional integrity, Redis caching, error fallbacks, JWT auth) on every PR, then auto-deploys to AWS ECS
- All AWS infrastructure provisioned with Terraform — VPC with public/private subnets, ECS Fargate (web app + standalone price ingester), RDS Postgres, ElastiCache Redis, ALB, and ECR

## Deep Dive

### Market Data Connection

A background thread maintains a persistent WebSocket connection to Polygon.io, a streaming data provider, ingesting 15-minute-delayed prices for all tracked stock tickers. Prices are cached in Redis and broadcast to clients via ActionCable channels. Stale connections and disconnects trigger an automatic reconnect.

### APM / Observability

`ActiveSupport::Notifications` instruments every controller request, including nested service calls. Each service call tracks its duration and whether it hit Redis, the database, or an external API. These are stored on a `Trace` record alongside total duration, DB runtime, view runtime, and HTTP status — enabling percentile (P99, P95, P50) analysis and per-route observability via DataCat, an in-app APM dashboard.

### Caching Strategy

Redis sits in front of most reads. Market snapshots cache for 5 minutes, company data for 3 days, and chart data for 24 hours. The `MarketService` and `PositionService` layers check Redis first and fall back to Polygon.io or Postgres, with all cache hits/misses tracked via instrumentation.

### Daily Portfolio Snapshots

An AWS Lambda function runs daily, triggering a method that iterates through all users in batches of 100. For each user, it calculates their current AUM by bulk-fetching the current value of their positions and reducing them alongside their cash balance, saving the result as a new/updated `PortfolioRecord`.

### Error Handling

Every controller action rescues exceptions and returns structured fallback responses (e.g. `{open: 'N/A', high: 'N/A', ...}`) so the frontend degrades gracefully. All caught errors are forwarded to Sentry.

### Testing

RSpec covers all layers of the application — models, services, requests, and channels. Tests verify transactional integrity (balance rollbacks, cost basis averaging, realized P&L), Redis cache behavior (hits, misses, TTLs, invalidation), and graceful degradation on service failures. All specs run via GitHub Actions CI.

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
| `POST` | `/graphql` | DataCat/APM queries |
| `POST` | `/record` | Snapshot daily portfolio values |


**Tech Stack:** Rails 8 · PostgreSQL · Redis · ActionCable · Polygon.io · AWS · GraphQL · Sentry
