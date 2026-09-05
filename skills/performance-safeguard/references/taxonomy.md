# Candidate taxonomy — the twelve classes

Sweep the diff against every class. Each entry lists what to grep for and the question that
decides whether it is real. The question matters more than the pattern: the pattern finds
candidates, the question kills false positives.

---

## 1. Query shape and data access
**Cues:** a query, `.get()`, `.filter()`, `.find()` or ORM attribute access inside a loop or
comprehension; `SELECT *`; a query with no `LIMIT`; `OFFSET` with a large page number;
`ORDER BY` on an unindexed column; `IN (...)` built from a list; a `JOIN` added to a hot
query; a new `WHERE` clause on a column with no index in the migration files.
**Decide:** How many rows does this touch at p99, and does an index cover the predicate?
Check the migrations for the index — do not assume one exists.

## 2. Unbounded memory growth
**Cues:** appending to a slice/list/map inside a request or consumer path with no cap;
reading a whole file, response body or query result into memory; a module-level or `static`
collection that only grows; a cache with no eviction or TTL; unbounded string building;
`json.Unmarshal`/`json.loads` on a body with no size limit.
**Decide:** What bounds this, and who controls that bound — us or the caller?

## 3. Concurrency and locking
**Cues:** a mutex, semaphore or distributed lock acquired before an I/O call; a lock held
across the whole function; a database transaction that spans an HTTP call or a queue
publish; `SELECT ... FOR UPDATE`; a global/singleton lock; lock ordering that differs
between two call sites; a distributed lock whose TTL is shorter than the work it guards.
**Decide:** What is the longest time this lock can be held, and how many requests contend
for it per second? Locks held across network I/O are P0 by default.

## 4. Blocking in an async or shared-pool context
**Cues:** synchronous I/O, `time.sleep`, a CPU-bound loop, or a blocking library call inside
an `async def`, an event loop, or a handler that shares a bounded worker pool; a `requests`
call in async code; heavy crypto or compression on the request path.
**Decide:** Does this block a thread/loop that other requests need? Blocking the only event
loop is P0 even at low volume.

## 5. Fan-out and chatty dependencies
**Cues:** a network, cache or database call inside a loop over request data; sequential
`await`s that have no data dependency; a new dependency call on an existing hot path; a
per-item call where a batch API exists.
**Decide:** Requests to us × calls per request = requests to the dependency. Can the
dependency take that number? Fan-out multiplies your traffic tier into someone else's.

## 6. Cache behaviour
**Cues:** a new cache read/write; identical TTLs across many keys; cache population on miss
with no single-flight or lock; no negative caching on an expensive miss; an invalidation
that clears a prefix or the whole namespace; a cache key built from unbounded input
(user-supplied strings, timestamps, UUIDs) — that is a memory leak wearing a cache costume.
**Decide:** What happens the moment this key expires under peak load — one recompute, or
every in-flight request recomputing at once? What is the cardinality of the key space?

## 7. Queue and consumer semantics
**Cues:** prefetch/`max_in_flight`/concurrency settings; a consumer with no bounded
concurrency; retry with no dead-letter path; ack before work completes, or long after; a
partition/routing key with low cardinality or an obvious hot value (`"default"`, a tenant
id, a country code); a producer in a loop; a message that carries a large payload instead of
a reference.
**Decide:** If the consumer stops for ten minutes, what does the backlog do — and what
happens when it restarts and processes the backlog at full speed against the database?

## 8. Timeouts, retries and circuit breaking
**Cues:** an HTTP/gRPC/database client constructed without a timeout; a context with no
deadline; retries without exponential backoff *and* jitter; retries at more than one layer
of the stack; retry on a non-idempotent operation; no cap on total retry attempts; a
timeout longer than the caller's timeout.
**Decide:** Multiply retries across layers — 3 × 3 × 3 is 27× load on a struggling
dependency at exactly the moment it can least take it. Missing timeout on a synchronous
dependency is P0: it converts a slow dependency into an outage by exhausting your workers.

## 9. Payload and serialisation
**Cues:** a response with no pagination; a new field on a hot response, especially a list or
a nested object; serialising a large structure per request; parsing a large body before
validating its size; base64 of binary data; N+1 serialisation of related objects.
**Decide:** Bytes per response × responses per second = bandwidth and allocation rate. A
2 KB field added to a 1,000 rps endpoint is 2 MB/s and a lot of GC pressure.

## 10. Hot-path CPU and allocation
**Cues:** regex compiled inside a loop or per call; reflection on the request path; hashing,
crypto or compression per item; sorting inside a loop; repeated conversion between types;
building a map/dict per request from a constant; deep copies of large structures.
**Decide:** Cost per operation × operations per second per pod, against the pod's CPU limit.
Only report if it moves the CPU budget meaningfully — see `scale-budgets.md`.

## 11. Lifecycle under Kubernetes
**Cues:** connection pool sizes, thread/worker counts, in-process caches sized without
reference to the pod memory limit; new work in `init`/startup; no graceful shutdown or
draining; a change to readiness/liveness probes; long-running work that outlives a
`SIGTERM`; state held in process memory that assumes a single replica.
**Decide:** Multiply everything per-pod by `maxReplicas`. A pool of 50 looks fine until 40
pods make it 2,000 connections against a database that accepts 500. See
`platform-gke-argocd.md`.

## 12. Observability and configuration cost
**Cues:** a metric, span or log line with an unbounded label/tag/attribute (user id, request
id, URL path with ids, error message); logging inside a loop or on the happy path at
`INFO`/`DEBUG`; a new span per item; a feature-flag or config lookup per request or per
item; synchronous logging to a remote sink.
**Decide:** Cardinality is a cost and a stability risk in New Relic as much as in the app.
Per-request flag evaluation that hits the network is a hidden dependency call — treat it
under class 5.

---

## Sweep discipline

Go class by class over the whole diff rather than file by file. File-by-file review finds
local problems; class-by-class review finds the ones that emerge from how the pieces
combine — which is where the real incidents come from.
