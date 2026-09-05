# Python — performance detectors

Load when the diff contains `.py` files. Establish the concurrency model first — it changes
what counts as a finding.

## Step 0 — Identify the execution model

Grep for `gunicorn`, `uvicorn`, `celery`, `asyncio`, `gevent`, `FastAPI`, `Django`, `Flask`,
and read the worker configuration. Then:

| Model | The dominant risk |
|---|---|
| sync workers (gunicorn/uWSGI) | A worker blocked = one fewer concurrent request. Worker count is your entire concurrency budget. |
| async (asyncio/FastAPI/uvicorn) | One blocking call stalls **every** request on that loop. |
| gevent/eventlet | Unpatched C extensions block the whole hub, invisibly. |
| Celery/RQ | Prefetch, retries, and long tasks vs. shutdown window. |

## Blocking the event loop (Class 4 — P0 in async code)

Inside `async def`, any of these blocks the loop and every other request on it:

- `requests`, `urllib`, `httpx.Client` (sync), `boto3`, sync database drivers
  (`psycopg2`, `pymysql`, `redis.Redis` rather than `redis.asyncio`)
- `time.sleep` instead of `asyncio.sleep`
- Blocking file I/O, `open().read()` on a large file
- CPU-bound work: hashing, compression, image processing, big `json.loads`, heavy regex
- Any Django ORM call in an async view without `sync_to_async`

> **Fix pattern:** `await asyncio.to_thread(fn, ...)` or `loop.run_in_executor` for blocking
> I/O; a process pool or an offloaded task for CPU work. Recommend the async-native client
> where one exists — the executor is a workaround, not a solution.
> **Verify:** event-loop lag, or p99 latency rising across *unrelated* endpoints on the same
> pod — that cross-endpoint correlation is the signature of loop blocking.

## Sequential awaits (Class 5)

`await a(); await b(); await c()` with no data dependency serialises three round trips.
`asyncio.gather` fixes it — but flag `gather` over a user-sized list as unbounded fan-out;
it needs a `Semaphore`.

## ORM traps (Class 1)

**Django**
- Attribute access on a related object inside a loop → N+1. Fix with `select_related`
  (FK/one-to-one, a JOIN) or `prefetch_related` (M2M/reverse, a second query).
- `.all()` with no slice or pagination on a growing table.
- `len(qs)` or `list(qs)` where `.count()` or `.exists()` would do — materialises every row.
- `.count()` inside a loop.
- A new `filter()` on an unindexed column: check `migrations/` for the index, do not assume.
- `.iterator()` missing on a large export — otherwise the whole result set is cached in memory.
- `bulk_create` / `bulk_update` missing where a loop of `.save()` exists.
- `only()`/`defer()` absent where a model has large text or JSON fields on a hot read.
- `atomic()` wrapping a network call — see Class 3; the transaction holds locks for the
  duration of someone else's latency.

**SQLAlchemy**
- Lazy-loaded relationships accessed in a loop → N+1. Use `selectinload`/`joinedload`.
- `session.query(...).all()` with no `limit`.
- Session held open across a request plus an external call; `expire_on_commit` causing
  surprise re-queries after commit.
- `pool_size` and `max_overflow` unset or unexamined — `pool_size × replicas` is the number
  that matters (`platform-gke-argocd.md`).

## Memory (Class 2)

- List comprehension where a generator would do, over a large or unbounded source.
- `.read()` / `.readlines()` on a whole file or response body; `json.loads` on an unbounded
  body without a size check.
- `pandas.read_csv`/`read_sql` on a request path — memory is a multiple of file size and
  wildly variable.
- **Mutable default arguments** (`def f(cache={})`) — shared across all calls for the process
  lifetime; a genuine leak.
- `functools.lru_cache` with `maxsize=None`, or keyed on request-derived values — unbounded
  by construction. `lru_cache` on a method also keeps `self` alive.
- Module-level dict/list that only grows; a logging handler or global registry accumulating
  entries.
- Reference cycles containing `__del__`, and any object graph the GC must traverse
  repeatedly — a large long-lived structure makes every GC pass more expensive.

## Requests, timeouts, retries (Class 8)

- `requests.get(url)` with **no `timeout=`** — waits forever by default. P0 on a request path.
- No `Session` reuse: a new TCP+TLS handshake per call.
- `urllib3.Retry` stacked on top of application-level retries — multiplies.
- Retries with no jitter; retrying non-idempotent POSTs.
- `httpx`/`aiohttp` client constructed per call rather than per process.

## Celery and workers (Class 7/11)

- `worker_prefetch_multiplier` left at the default (4) with long tasks — messages sit unacked
  behind a slow one while other workers idle. Set to 1 for long tasks.
- `acks_late` without idempotency, or without it where duplicates are unacceptable.
- Retries with no `max_retries` and no backoff — a poison message loops forever.
- Large payloads passed as task arguments instead of a reference to storage.
- Task runtime longer than the pod's `terminationGracePeriodSeconds` with no
  `soft_time_limit` — work is killed mid-flight on every rollout.
- `gunicorn` worker count and memory: `workers × per-worker RSS` must fit the container
  limit, and `--max-requests` with `--max-requests-jitter` is the standard mitigation for
  slow leaks. Missing `--timeout` tuning shows up as `WORKER TIMEOUT` in Sentry.

## CPU hot paths (Class 10)

- `re.compile` inside a function; string `+=` accumulation in a loop (use `"".join`).
- `copy.deepcopy` on a request path.
- `json` where `orjson`/`ujson` is already a dependency elsewhere in the repo.
- `in` against a `list` inside a loop where a `set` is O(1).
- Pydantic model validation of large nested payloads per request — real, measurable cost at
  T3; check whether validation is repeated at several layers.

## Tooling to recommend

`py-spy top --pid <pid>` and `py-spy dump` against a live pod (no restart needed, which makes
it the right first call in production), `tracemalloc` snapshots for leak confirmation,
`memray` for allocation profiles, `django-debug-toolbar` or `nplusone` in staging for ORM
query counts, and `EXPLAIN ANALYZE` on the generated SQL — print it with `str(qs.query)`.
