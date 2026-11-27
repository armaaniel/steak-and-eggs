# DataCat archive

Postgres keeps 31 days of traces and ingester samples. Each night, `rake prune_traces` copies every older UTC day to S3, checks the upload, and only then deletes that day's rows. It also copies yesterday, so S3 is never more than a day behind. Load traces stay in Postgres and aren't archived.

- **Bucket:** `steakneggs-datacat-archive` (private, us-west-1)
- **Objects:** `traces/YYYY-MM-DD.jsonl.gz` and `ingester_samples/YYYY-MM-DD.jsonl.gz`, one per UTC day
- **Rows:** one `row_to_json` object per line, with every column. Trace `spans` and sample `detail` are nested JSON. Timestamps are UTC without a zone suffix.
- **Row count:** in each object's `rows` metadata
- **Endpoints:** stored with the real symbol (`POST /stocks/AAPL/buy`). The API groups them as `POST /stocks/symbol/buy`, so filter on `controller` and `action`, or `endpoint LIKE 'POST /stocks/%/buy'`
- **Re-running a day** overwrites it with the same rows
- **Backfill:** `rake archive:backfill` copies every day still in Postgres without deleting anything. `FROM` and `TO` (UTC dates) narrow it.

## Querying it

```sh
aws s3 sync s3://steakneggs-datacat-archive ./archive
duckdb
```

```sql
-- buy p50 per day
SELECT created_at::date AS day, median(duration) AS p50, count(*) AS n
FROM read_json_auto('archive/traces/*.jsonl.gz')
WHERE controller = 'StocksController' AND action = 'buy' AND status = 201
GROUP BY 1 ORDER BY 1;

-- SQL round trips per canary request
SELECT endpoint, len(list_filter(spans, s -> s.category = 'sql' AND s.name <> 'transaction' AND NOT coalesce(s.cached, false))) AS sql
FROM read_json_auto('archive/traces/2026-11-25.jsonl.gz')
WHERE source = 'canary' LIMIT 20;

-- peak lag per day (meanExcess = sum_lag_ms / sampled_events - 902,000)
SELECT at::date AS day, max(sum_lag_ms::double / sampled_events - 902000) AS peak_ms
FROM read_json_auto('archive/ingester_samples/*.jsonl.gz')
WHERE kind = 'tick' AND sampled_events > 0
GROUP BY 1 ORDER BY 1;
```

The archive holds the same columns the GraphQL API reads from, so anything DataCat shows can be recomputed from it. One difference: the API buckets samples into 60 s points, while the archive has the raw samples.
