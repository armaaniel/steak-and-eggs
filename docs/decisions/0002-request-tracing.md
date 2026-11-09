# Record a waterfall of spans for each request

Status: accepted, being built. Written down 2026-11-07.

## Context

1. **A trace shows totals, not a timeline.** Each traced request stores its duration, DB time and a `breakdown` of service calls keyed by name. There are no start times and no nesting, and a second call with the same name overwrites the first.
2. **Where the time went is inferred, not measured.** The `used_redis`, `used_db` and `used_api` flags are set by the service code itself, and DB time is one number for the whole request. Individual SQL statements, Redis commands and HTTP calls aren't recorded.
3. **One process sees the whole request.** Rails starts and finishes every traced request in one Puma process, so a whole trace can be written at once.
4. **DataCat's GraphQL is public.** Anything stored can be read by anyone.
5. **The API runs on 0.25 vCPU and 512 MB.** Tracing has to stay cheap, and it can never put the user's request at risk.

## Goal

For any single request, show a timeline of what it did (every SQL query, Redis command and HTTP call, plus callbacks and rendering), with each part's own time, so "where did the time go" is measured instead of inferred.

## Scope

- **Pass 1:** spans for `before_action`, my code (the controller action and service methods), each SQL query, each Redis command, each HTTP call, and the JSON render. Cache hits are read from what Redis returned, which replaces the `used_*` flags.
- **Pass 2:** move the root out to one Rack middleware, which adds middleware time.
- **Out:** GC and waiting-for-CPU numbers, time in Puma's queue, and timing each middleware layer. Each middleware layer was timed once locally instead: Sentry's was the most expensive real one at ~43 µs, and timing all of them cost ~151 µs per request.

## Design

### Lifecycle

- A trace starts when Rails announces the start of `process_action.action_controller` and ends when that event finishes. One listener object with `start` and `finish` handles both.
- The tracer keeps a stack of open spans in `ActiveSupport::IsolatedExecutionState`, so each Puma thread has its own. When the root closes, the tracer builds the trace, queues it and clears its state, because threads are reused across requests.
- Events with no open trace are ignored: the flush thread's own inserts, and Action Cable's threads.
- Only the root's start and finish decide a trace's lifetime, so pass 2 changes one place.

### Parents

A span's parent is whatever is on top of the stack when it starts. Rebuilding the tree from start and end times afterwards breaks when two spans round to the same times, or when work overlaps.

Transactions are the one event that doesn't nest. Rails starts a transaction lazily: the first query opens its event, and only then, inside it, sends `BEGIN` and starts the transaction (`database_statements.rb:554–555`, `abstract_adapter.rb:994`). The transaction event therefore opens inside that query and closes after it. When a transaction starts while a query is the innermost open span, the tracer slots the transaction in between that query and its parent, so the stack nests again. `BEGIN` stays inside the first query, because that's where Rails sends it.

### Self time

- A span's self time is its total minus its direct children's totals. Every millisecond is counted once, so the categories add up to the duration.
- A span's self time counts toward its own category. `before_action`'s own time, the JWT decode, is callbacks, even though it contains the cached user lookup.
- The exception is a transaction. Its own time is the Ruby between its queries, so it counts as app, not SQL. That keeps `sql_ms` to time spent inside queries, which is what Rails' `db_runtime` measures.
- The root's own time counts as app. The timeline shows it as the gaps between the root's children, with the number on hover.

### Storage

One row per trace, as today.

- **Columns:** anything filtered, sorted or charted across traces. That's today's fields, plus self time per category (`app_ms`, `sql_ms`, `redis_ms`, `http_ms`, `callbacks_ms`, `render_ms`), plus `cache_hits` and `cache_misses`. Those last two count the Redis GETs and MGETs outside `before_action`, by whether Redis returned a value. An MGET is one lookup, and it's a hit only if every key came back. A command that raised counts as neither.
- **`duration`** keeps today's meaning: the controller action's time.
- **`spans`:** a `json` list of span objects, in the order they were opened. A transaction is opened during its first query, so it comes after that query in the list. It's read only when someone opens one trace. The row is the trace, and a span's position in the list is its ID.
- **At most 500 spans are stored per trace,** so one runaway request can't make a huge row. The tracer still records every span in memory, so the summary columns count all of them, and the root notes how many were left out (`dropped`). A transaction is opened after its first query, so if the cut falls between them, the stored query points to its nearest stored ancestor instead.

| field | example | present |
|---|---|---|
| `name` | `User Load` | always |
| `category` | `sql` | always |
| `start` | `4.31`, ms after the trace began, rounded to 0.01 ms | always |
| `duration` | `0.52`, ms, rounded to 0.01 ms | always |
| `parent` | `6`, the position of its parent | always. `null` for the root, which is position 0 |
| `sql` | `SELECT "users".* FROM "users" WHERE "users"."id" = ? LIMIT ? FOR UPDATE` | SQL spans |
| `cached` | `true` | SQL spans answered by Rails' query cache |
| `hit` | `true` | Redis GETs and MGETs that didn't raise |
| `dropped` | `102`, spans past the first 500 that weren't stored | the root, only when spans were left out |

Names: SQL uses Rails' query name, with the statement in `sql`. Rails' `SCHEMA` lookups are spans too. A process runs them the first time it touches each table, to learn the table's columns and primary key, and they made up 18 queries and about 35 ms of a cold local buy. `BEGIN`, `COMMIT` and savepoints are named by their statement, since Rails names them all `TRANSACTION`. A transaction itself is `transaction`, and its queries are its children. Redis is the command plus the key's shape (`GET price:?`). A command with several keys lists each distinct shape (`MGET price:? open:?`), and a command with no key is just its name (`SCAN`). HTTP is the method plus the host (`GET api.polygon.io`). Services use the event name without `.datacat`. The root is `Controller#action`.

### Where spans come from

- **Every span comes through one listener,** from an `ActiveSupport::Notifications` event:
  - `process_action` (the root)
  - my `.datacat` services
  - `sql.active_record` and `transaction.active_record`
  - `command.redis`
  - `request.http`
  - `before_action.action_controller` and `render.action_controller`
- **Redis has no publisher of its own,** because `redis-client` isn't part of Rails. A five-line `redis-client` middleware (`RedisClient.register`) announces each command as `command.redis`, carrying the command and its reply. From there it's handled like a query. Announcing it costs about 4 µs of CPU per command locally, most of it the handle and Sentry's breadcrumb. That's about 0.5% of a stockprice, and it buys one code path, plus Redis commands in Sentry's trail before an error.
- **Pipelines aren't covered.** `redis-client` aliases `call_pipelined` to the original `call`, so the middleware only sees single commands. The app's only pipeline is `redis-client`'s own connection setup.
- **HTTP has no publisher either.** A module prepended onto `Net::HTTP` announces each `request` as `request.http`, carrying only the method and the host.
  - When the connection isn't open yet, `Net::HTTP#request` opens it and then calls itself again. A guard on the object skips that inner call, so one call is one span, and connecting is included.
  - Sentry's own patch does the opposite (`return super unless started?`), so its timing leaves connecting out.
  - All five Polygon calls use `Net::HTTP.new` and then `request`, with no `start`, so every call opens a new connection, TLS included. The span shows what that costs.
- **Callbacks have no Rails event, and they aren't one block of code.**
  - The callbacks run, and then the action runs inside `run_callbacks { … }`.
  - So one module prepended onto `AbstractController::Callbacks` uses the handle API by hand, the way Rails times transactions. `process_action` builds and starts the handle, `send_action` finishes it as the action begins, and an `ensure` finishes it when a callback stops the chain (a 401 from `verify_token`).
  - Being prepended there puts it below `Instrumentation`, so the root is already open.
  - Controllers with no before callbacks, like GraphQL's, get no span.
  - The span ends where the action begins, so an `after_action` would count as app. The app has none.
- **Render has no Rails event for JSON either.** A module prepended onto `ActionController::Renderers` wraps `render_to_body`, which is where the renderer calls `to_json`. It reads which renderer it is before calling `super`, because the renderer deletes that key from the options.
- **The publishers run in every environment, including tests,** so the specs exercise the same code as production. Only the listener and the flush thread are skipped in tests.

### Sampling

- **User and canary traffic:** every request records and stores its spans.
- **Load traffic:** decided when the root opens. 1 in 100 requests record spans and summary columns; the other 99 record only today's fields. That keeps tracing's CPU cost off a test that measures CPU.
- **How a request is known to be load traffic:** at that point only the `Synthetic-Source: load` header is available. It isn't verified, but the most a fake header can do is turn off spans for that one request. The row is still written, and its `source` is verified at the end as today.
- **The trace row is never sampled.** Percentiles and the load-test join (`request_id`, `gap`) need every request.

### Privacy

- **Allowlist only:** the span fields above, holding fixed names, Rails' query names, or shapes. Payloads are never copied. Rails' `process_action` payload carries every request header, including the `authToken` JWT, and the params.
- **SQL:** values become `?`, and Rails' trailing comment is stripped. If the replacer doesn't recognise something, the span keeps its name and drops the statement.
- **Redis:** the key up to its first colon, then `?`. A key without a colon becomes `?`. Values are never stored. Every key in the app follows `prefix:value`. The user cache key was `user_42` until it was renamed to `user:42`.
- **HTTP:** method and host only. The Polygon URL carries `apiKey` in its query string.
- **Errors:** class and file:line, as today. Never the message.
- **Enforced when writing,** with tests that feed in real-looking values and assert none survive.

### Failure

The user's request always wins, and the trace is best effort.

- Every listener method rescues its own errors, because Rails re-raises a listener's error into the request. The publishers only announce events and contain no tracer code.
- If the spans haven't nested back to the root when it closes, the row is still written, but without spans or summary columns, and a warning is logged. A wrong waterfall is worse than none. A span that never finished, or an extra finish, causes this.
- The flush thread inserts everything queued, once a second. A failed insert goes to Sentry, that second's traces are dropped, and the loop carries on.
- **Left out, as YAGNI at this traffic:**
  - A cap on the queue, and inserting in chunks. OpenTelemetry's batch span processor does both (a queue of 2,048, batches of 512), and Sentry's SDK caps its own queue at 30 events. But the queue only grows if one second's insert takes longer than a second, or if the flush thread dies.
  - De-duplicating errors before Sentry. Sentry already groups identical errors into one issue, and its SDK discards a flood beyond its queue.

### Cost

- Measured in production on one running task, not locally and not across task replacements.
- A runtime switch in Redis turns tracing off and on, so one load run can alternate windows at a fixed rate. CPU per request from the sampler gives the difference. An environment variable can't do this, because changing one starts a new task.
- The budget is set after the first measurement. On stockprice, 8 µs of CPU is about 1% of capacity.
- Known so far: shaping a statement costs 10–18 µs of CPU locally, so about 0.15 ms for a buy's 11 queries. It runs after the span's clock stops, so it isn't counted in the span.

### Build and verify

First, read the code each piece hooks into: `ActionController::Instrumentation#process_action`, `ActiveSupport::Notifications`' instrumenter and fanout, `AbstractAdapter#log`, `redis-client`'s middlewares, and `Net::HTTP#request`.

Each step is its own commit, and nothing is pushed until every step has been reviewed. A step is done when every line can be explained, its tests pass (failure paths included), a real request matches a prediction written down first, and the overhead has been re-measured.

1. The tracer and listener take over from the current block. The rows stay the same, plus a `spans` list holding the root and my `.datacat` spans.
2. Self time and `app_ms`.
3. SQL and transaction spans. A buy should show 10 queries plus BEGIN/COMMIT, and `sql_ms` should be close to `db_runtime`.
4. Redis spans, `hit`, and the cache columns.
5. HTTP spans.
6. `before_action` and render.
7. A check that the spans nest back to the root before they're stored.
8. GraphQL fields and the real panel.
9. Sampling for load traffic. It comes before the cost run, because that run is a load test, and it should measure what load tests will actually record.
10. The cost in production.

## Options not chosen

| Option | Why not |
|---|---|
| A `spans` table, one row per span | It pays off only for questions about individual spans across traces. Under load it means ~25× more inserted rows, about 7,500 a second at 300 rps. |
| `jsonb` for `spans` | It's bigger (4,456 vs 3,409 bytes for a buy's 25 spans) and only faster for querying inside. Spans are written once and read whole. |
| Tail sampling for load tests | Every request would pay to record spans, during a test that measures CPU. |
| Keeping the `used_*` flags | They're claimed by the code, not observed. |
| Timing middleware in pass 1 | It needs the root outside Rails for well under a millisecond on most requests. Left for pass 2. |

## Consequences

- Rows grow from ~200 bytes to ~850 bytes for a cached stockprice and ~1.2 KB for a buy. 30 days of user traffic comes to ~150 MB.
- DataCat's cache filter, cache-hit column and endpoint stats move from `breakdown` to the new columns.
- `breakdown` still copies `Ticker.search`'s `term` until it's retired.
- **Known limitations:**
  - Time spent waiting for the GVL or CPU is labelled app.
  - Waiting inside a query reads as SQL time. The Oct 31 17:13:59 UTC buy showed 1,275 ms of DB time while Postgres sat at ~5% CPU.
  - Spans are timed by the tracer, not by Rails' own timer, and the two read the clock a few listener calls apart. Over 12 local buys, `sql_ms` matched `db_runtime` to within about 0.1 ms on 10 of them. The other two were off by 0.5 and 1.6 ms, and that's not explained yet.

## Open questions

- The overhead budget.

## Revisit when

- A slow request can't be explained by its spans: add GC and GVL-wait numbers.
- Questions about individual spans across traces come up ("the slowest queries this week"): a spans table.
- Pass 1 is done: move the root to Rack.
- The trace queue is ever seen growing: cap it, and insert in chunks.
- A tracer bug floods Sentry: report only the first error of each class per process.
