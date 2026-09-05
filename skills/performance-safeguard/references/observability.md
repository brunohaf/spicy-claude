# Observability — how to prove or refute a finding

Every finding ships with a check, stated as:
**run this → this result confirms → that result refutes.**

**Prefer a local check.** The developer is at their machine with the code not yet pushed;
something they can run in the next thirty seconds is worth more than a production query they
cannot run until after this ships. Give the production query as well when it is the only
thing that can truly settle the question — and label it clearly as a post-deploy check, so
they do not read it as a blocker on opening the MR.

---

# Local checks — runnable before the MR exists

## Query behaviour, against a dev database

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT ...;
```
`Seq Scan` on a table that is large in production confirms a missing index — even when the
local table is small and the plan is fast. **Read the node type, not the timing.** Local
timings prove nothing; local *plans* prove a great deal.

Count the queries a request actually issues — the direct N+1 test:

```bash
# Postgres: watch what the app sends while you exercise the endpoint
psql -c "ALTER SYSTEM SET log_statement = 'all'"; psql -c "SELECT pg_reload_conf()"
# then tail the log, hit the endpoint once, and count
```
Framework-native equivalents are faster where they exist: `django-debug-toolbar` or
`nplusone` (Django), SQLAlchemy `echo=True`, `pg_stat_statements` reset-then-hit, or an
assertion helper such as Django's `assertNumQueries` — which also leaves a regression test
behind, and is the better recommendation when one exists.

## Allocation and CPU, by benchmark

```bash
# Go — the number that matters is allocs/op and B/op, not ns/op
go test ./internal/feed -bench BenchmarkEnrich -benchmem -count=5
go test ./... -bench . -benchmem -memprofile mem.out && go tool pprof -top mem.out
```
```bash
# Python
python -X importtime -m pytest tests/test_hot_path.py     # import-time surprises
py-spy record -o profile.svg -- python -m app.worker      # flame graph, no code changes
memray run -o out.bin script.py && memray flamegraph out.bin
```
Benchmark the **before and after** of a suggested fix when the finding is about CPU or
allocation. A 3× allocs/op difference is a fact; "this looks allocation-heavy" is not.

## Memory growth, by repetition

Run the hot path in a loop and watch RSS. A leak shows as a line that does not flatten:

```bash
# Go: the built-in way — two heap profiles and a diff
curl -s localhost:6060/debug/pprof/heap > a.pprof   # then exercise the path N times
curl -s localhost:6060/debug/pprof/heap > b.pprof
go tool pprof -base a.pprof b.pprof                 # what grew, and who allocated it
```
```python
# Python
import tracemalloc; tracemalloc.start()
snap1 = tracemalloc.take_snapshot()      # ... exercise the path ...
snap2 = tracemalloc.take_snapshot()
for s in snap2.compare_to(snap1, 'lineno')[:10]: print(s)
```
`go tool pprof -base` and `tracemalloc.compare_to` are the two cleanest ways to prove a leak,
because both answer "what grew" rather than "how much is allocated".

## Concurrency and blocking

```bash
go test ./... -race                    # new goroutines/shared state: run it, always
go test ./... -run TestX -timeout 30s  # a deadlock shows as a timeout with a full dump
```
For an async Python handler suspected of blocking the loop, the fastest proof is to run the
service locally, issue one slow request and several fast ones concurrently, and see whether
the fast ones stall. Cross-endpoint stalling *is* the signature of loop blocking.

## Load, cheaply

```bash
hey -z 30s -c 50 http://localhost:8080/v1/feed
k6 run --vus 50 --duration 30s script.js
```
Local absolute numbers do not transfer to production. What does transfer: whether latency
**degrades non-linearly** as concurrency rises, and whether memory returns to baseline after
the run. Both are properties of the code, not of the machine.

## Scale the input, not the machine

The most under-used local check: run the new code against a realistic input size rather than
a fixture of three rows. Seed 10,000 rows, request the maximum page size, and send the
largest payload the API permits. Most L1 candidates become L2 or get cleared in one run — and
this is the check to suggest first when the trigger quantity is what you could not establish.

---

# Production checks — after this ships

Label these as post-deploy. They are how the developer confirms the fix worked and watches
for the failure mode, not a gate on opening the MR.

## New Relic (NRQL)

Adjust `appName` and attribute names to the service's conventions — check the repo for
`newrelic.yml`, `NEW_RELIC_APP_NAME`, or dashboards-as-code first.

**Throughput and latency of the touched endpoint** — establishes the traffic tier, which is
the input to every budget calculation:

```sql
SELECT rate(count(*), 1 second), percentile(duration, 50, 95, 99)
FROM Transaction WHERE appName = 'SERVICE' AND name = 'WebTransaction/Go/route'
SINCE 7 days ago TIMESERIES 1 hour
```

**Database calls per transaction** — the direct test for N+1:

```sql
SELECT average(databaseCallCount), max(databaseCallCount), percentile(databaseDuration, 95)
FROM Transaction WHERE appName = 'SERVICE' AND name = 'WebTransaction/Go/route'
SINCE 1 day ago
```

> Confirms if the call count sits well above the number of logical entities per request, or
> if it scales with page size. Refutes if it stays flat as the page grows.

**Slowest datastore operations** — finds the query the new code will hit:

```sql
SELECT count(*), average(duration), sum(duration)
FROM Span WHERE appName = 'SERVICE' AND category = 'datastore'
FACET name SINCE 1 day ago LIMIT 30
```

Rank by `sum(duration)`, not `average`. A 5 ms query run 200,000 times costs far more than a
2-second query run twice — and only the first one hurts you when volume grows.

**Dependency fan-out:**

```sql
SELECT count(*), average(duration) FROM Span
WHERE appName = 'SERVICE' AND category = 'http'
FACET name SINCE 1 day ago LIMIT 30
```

**Memory and restarts per pod:**

```sql
SELECT average(memoryUsedBytes) FROM SystemSample
WHERE appName = 'SERVICE' FACET hostname SINCE 3 days ago TIMESERIES
```

A sawtooth that resets without a deploy is a restart; a monotonic climb between restarts is
a leak. Say which pattern would confirm the finding.

**Cache hit rate**, where instrumented — the test for stampede risk:

```sql
SELECT percentage(count(*), WHERE cache.hit = true) FROM Span
WHERE appName = 'SERVICE' AND name LIKE '%cache%' SINCE 1 day ago TIMESERIES 5 minutes
```

> Sharp dips at a fixed interval = synchronised TTL expiry = stampede confirmed.

**Before/after comparison** — for any "ship with monitoring" verdict, give the user this
plus a rollback threshold:

```sql
SELECT percentile(duration, 95) FROM Transaction
WHERE appName = 'SERVICE' AND name = 'WebTransaction/Go/route' COMPARE WITH 1 day ago
```

## Sentry

- Search `is:unresolved` scoped to the touched module for existing timeout, pool-exhaustion
  or serialisation errors. Pre-existing errors on a path you are about to make busier are
  strong evidence.
- Error types that map to taxonomy failure modes: `OperationalError`, `TimeoutError`,
  `PoolTimeout`, `context deadline exceeded`, `connection reset by peer`, `MemoryError`,
  `WORKER TIMEOUT`.
- Sentry **Performance** surfaces slow transactions and has built-in N+1 detection for the
  affected route — check it before asserting an N+1 the APM may already have confirmed.
- **OOMKills usually produce no Sentry event at all.** The absence of errors around a restart
  is itself the signal. Say this explicitly on memory findings, so a clean Sentry is not
  misread as an all-clear.
- Flag when a change can generate a high volume of a new error type: Sentry quota exhaustion
  during an incident blinds you exactly when you need visibility most.

## Cluster (kubectl / ArgoCD)

```bash
kubectl get deploy,hpa -n NAMESPACE
kubectl describe hpa NAME -n NAMESPACE
kubectl top pods -n NAMESPACE
kubectl get events -n NAMESPACE --sort-by=.lastTimestamp | grep -Ei 'oom|evict|kill|unhealthy|backoff'
kubectl get pods -n NAMESPACE -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].restartCount}{" "}{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}{end}'
argocd app get APP
```

`lastState.terminated.reason == OOMKilled` is the definitive answer on a memory-limit
finding. A high restart count with `Error` instead points at startup or probe problems.

## Datastore-side checks

```sql
-- PostgreSQL: which queries actually cost the most
SELECT calls, mean_exec_time, total_exec_time, rows, query
FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 20;

-- Is the predicate the new code adds actually indexed?
-- A Seq Scan on a large table confirms the finding.
EXPLAIN (ANALYZE, BUFFERS) SELECT ...;

-- Connection headroom, against the multiplication in platform-gke-argocd.md
SELECT count(*) AS in_use,
       (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max_conn
FROM pg_stat_activity;

-- Long-running transactions: the lock-scope finding, confirmed
SELECT pid, now() - xact_start AS age, state, left(query, 120)
FROM pg_stat_activity WHERE xact_start IS NOT NULL ORDER BY age DESC LIMIT 10;
```

```bash
redis-cli INFO stats     # instantaneous_ops_per_sec, keyspace_hits/misses, evicted_keys
redis-cli INFO memory    # used_memory vs maxmemory, mem_fragmentation_ratio
redis-cli --bigkeys      # a large key on a hot path blocks Redis for every client
redis-cli --latency      # confirms whether Redis itself is the stall
```

Queue depth and consumer lag are the two numbers that settle most class-7 findings; name the
specific metric for the broker in use (Kafka consumer lag, SQS
`ApproximateAgeOfOldestMessage`, RabbitMQ `messages_ready`, Pub/Sub
`oldest_unacked_message_age`).

## When nothing can prove it yet

If a finding is L1 and neither a local check nor existing telemetry can settle it, the
recommendation is not "investigate further" — it is one of:

- **a local experiment**, stated concretely: seed N rows, call it, count the queries;
- **a test that pins the behaviour**, which also prevents the regression returning —
  `assertNumQueries`, a benchmark with an allocation ceiling, a timeout assertion;
- **an instrument to add in this MR**, with the metric name and the threshold that would
  make it a finding later.

All three are actionable and all three can be done before the MR is opened. "Needs more
investigation" is not an outcome; it is the absence of one.
