# Datastores — databases, caches and queues

Load whenever the diff touches SQL, an ORM, a cache client, or a queue/stream client, in any
language. These failure modes are language-independent and are where the highest-severity
findings usually live: a bad query pattern is bounded by your traffic, but a bad *shared
dependency* pattern is bounded by everyone's.

---

# Relational databases

## Query shape

- **Missing index for a new predicate.** Any new `WHERE`, `JOIN ON`, or `ORDER BY` column
  must be checked against the migrations. Do not assume an index exists because the column
  looks important. A sequential scan on a large table at T2+ is P0.
- **Composite index column order.** An index on `(a, b)` does not serve a query filtering
  only on `b`. Check the leading column.
- **Functions on indexed columns** (`WHERE lower(email) = ?`, `WHERE date(created_at) = ?`)
  disable the index unless a matching expression index exists.
- **`OFFSET` pagination** degrades linearly — the database still walks the skipped rows. At
  page 1,000 it is scanning a million rows to return ten. Recommend keyset/cursor pagination
  when the diff adds deep paging to a growing table.
- **`SELECT *`** on tables with large text/JSON/blob columns: bytes over the wire and into
  memory, per row, per request.
- **`IN (...)` built from an unbounded list** — plan degradation, parameter limits (Postgres
  65,535 bound parameters), and no cap on work. Chunk it.
- **New `JOIN` on a hot query** — check cardinality. A join that multiplies rows before an
  aggregate is a common source of sudden 100× cost.
- **`COUNT(*)` on a large table for a UI count.** Postgres has no cached count; recommend an
  approximate count or a maintained counter.

## Transactions and locks (Class 3)

- **Any network call, cache call, queue publish or HTTP request inside a transaction.** The
  transaction holds locks and a connection for the duration of someone else's latency. P0 —
  this is one of the most reliable ways to convert a dependency slowdown into a database
  incident.
- `SELECT ... FOR UPDATE` on a row many requests contend for: serialises them all. State the
  contention rate.
- Long transactions in Postgres block `VACUUM` and cause bloat well beyond the transaction
  itself.
- **Lock ordering:** two code paths that lock the same rows in different orders will
  deadlock. Check any new multi-row update against existing ones.
- A transaction opened at the start of a request handler and committed at the end, with
  business logic in between — the scope should be the smallest unit that must be atomic.

## Migrations (Class 1/11)

- `ALTER TABLE ADD COLUMN` with a volatile default, `CREATE INDEX` without `CONCURRENTLY`,
  and column type changes take an `ACCESS EXCLUSIVE` lock and rewrite the table. On a large
  table under load this is an outage, not a migration.
- Backwards-incompatible schema changes without expand/contract: during an ArgoCD rolling
  update, old and new code run against the same schema simultaneously
  (`platform-gke-argocd.md`).
- A migration that backfills in a single statement over millions of rows — recommend batched
  backfill with a bounded rate.

## Connections

`pool size × maxReplicas` vs `max_connections`, including cron/job pods and sidecars. See
`scale-budgets.md`. Also check that a read replica is used where the query is read-only and
the code has a replica route available.

---

# Caches

## Stampede / thundering herd (Class 6)

The canonical high-traffic failure: a hot key expires, and every in-flight request recomputes
it at once. At T3 that is hundreds of simultaneous identical database queries.

Findings:
- Population on miss with **no single-flight / lock / `Cache-Aside` guard**.
- **Uniform TTLs** — keys written together expire together. Require jitter:
  `ttl + rand(0, ttl*0.1)`.
- **No negative caching** for expensive misses, so every request for a nonexistent entity
  hits the database.
- Deploy-time cold cache: an in-process cache is empty on every pod after every rollout —
  see cold-start amplification in `platform-gke-argocd.md`.

## Key design

- **Unbounded key cardinality** — keys built from user input, timestamps, UUIDs, or full
  URLs. A cache with unbounded keys and no eviction policy is a memory leak; with eviction,
  it is a cache with a ~0% hit rate, which is worse than no cache because you pay both costs.
- **Large values on a hot key.** Redis is single-threaded: one large value or one `KEYS`,
  `SMEMBERS`, `HGETALL` over a big structure blocks every other client. `--bigkeys` confirms.
- `KEYS` or `FLUSHDB` anywhere in application code — always a finding. `SCAN` is the
  cursor-based alternative.

## Invalidation

- Prefix or wildcard invalidation that clears thousands of keys — a self-inflicted stampede.
- Write-through paths that update the database and cache non-atomically: state the window
  and whether the resulting staleness is acceptable for this data.
- Missing `maxmemory-policy` — Redis without an eviction policy returns errors on writes when
  full rather than evicting.

---

# Queues, streams and consumers

## Backpressure and concurrency (Class 7)

- **Unbounded consumer concurrency** — the consumer becomes an amplifier, converting queue
  depth into simultaneous load on the database.
- **Prefetch too high with long handlers** — messages sit unacked behind a slow one while
  other consumers idle. Too low, and throughput collapses to one round trip per message.
- **Producer in a loop** with no batching — the publish path becomes the bottleneck.
- **The backlog-drain problem:** ask what happens after a ten-minute consumer outage. The
  backlog is processed at maximum speed against a database sized for steady state. If there
  is no rate limit on the consumer, that recovery is a second incident. This is worth
  checking on every new consumer.

## Partitioning and ordering

- **Hot partition keys:** a routing key with low cardinality, or a dominant value
  (`"default"`, a single large tenant, a popular country) sends most traffic to one
  partition/shard. Throughput is then capped by one consumer regardless of scale.
- Ordering guarantees assumed but not provided — check whether the code depends on order
  that the broker only guarantees per partition.

## Delivery semantics

- **Ack before work completes** — message loss on crash or rollout.
- **Ack long after** — visibility timeout expires, the message is redelivered, and now it is
  processed twice concurrently.
- **Retry without a dead-letter queue and a max attempt count** — a poison message loops
  forever, consuming capacity indefinitely.
- **Non-idempotent handlers** with at-least-once delivery. Every at-least-once consumer needs
  an idempotency key or a natural upsert; flag any new handler that has neither.
- **Large payloads in messages** rather than a pointer to object storage — broker memory,
  network cost, and often a hard message-size limit that fails only for the largest records,
  in production.

## Shutdown

The consumer must stop fetching, finish or requeue in-flight messages, and exit within
`terminationGracePeriodSeconds`. A handler that routinely runs longer than that window loses
work on every deploy — and with ArgoCD auto-sync, deploys are frequent.
