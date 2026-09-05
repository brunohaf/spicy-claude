# Go — performance detectors

Load when the diff contains `.go` files. Each entry: what to look for, why it bites at
scale, and what refutes it.

## Goroutine leaks (Class 2/3 — the top Go production failure)

- `go func()` with no way to exit: no `ctx.Done()` select, no closing channel, no
  `WaitGroup`. A goroutine blocked forever on a channel send or receive is never collected —
  it holds its stack and everything it references.
- `go` inside a request handler or a loop, unbounded. At T3 that is thousands of goroutines
  per second; if each lives longer than a request, the count only grows.
- Sending on an unbuffered channel with no guaranteed receiver, or a buffered channel that
  fills while the reader has returned.
- `time.After` in a `select` inside a loop — the timer is not collected until it fires; use
  `time.NewTimer` with `defer t.Stop()` or `context.WithTimeout`.
- Missing `defer resp.Body.Close()` after `http.Do` — leaks the connection *and* prevents
  connection reuse, so the transport opens a new socket per call.

> **Refutes:** the goroutine has a `ctx` with a deadline and a `select` on `ctx.Done()`, or
> it is spawned once at startup rather than per request.
> **Verify:** `runtime.NumGoroutine()` trending up between deploys, or `/debug/pprof/goroutine`.

## Context and timeouts (Class 8)

- `context.Background()` or `context.TODO()` inside a request path — breaks cancellation, so
  work continues after the client disconnects. At T3 that is wasted capacity precisely
  during an overload.
- `http.Client{}` literal, or `http.DefaultClient`: **no timeout at all**. This is P0 on any
  synchronous path — a hung dependency exhausts your handler capacity and turns their
  degradation into your outage.
- `db.Query` / `db.Exec` instead of the `...Context` variants: the query is not cancelled
  when the request is.
- A downstream timeout longer than the caller's own — the caller gives up while you keep
  holding a worker and a connection.

## Blocking and the shared runtime (Class 4)

- Blocking syscalls, `time.Sleep`, or CPU-heavy loops while holding a mutex.
- `sync.Mutex` held across a network or database call — serialises every request through one
  critical section. P0 by default; state the hold time and the contention rate.
- `sync.RWMutex` where writes are frequent — writers starve behind a stream of readers.
- A single shared `sync.Mutex` on a map that could be `sync.Map` or sharded, on a hot path.

## Memory and allocation (Class 2/10)

- `append` in a loop with no `make([]T, 0, n)` pre-allocation — repeated growth and copying.
  Matters when `n` is large or the loop is hot.
- **Slice aliasing keeps the whole backing array alive:** `small := big[:10]` retains all of
  `big`. Same for a substring of a large string. This is a classic invisible leak.
- `io.ReadAll` on an HTTP body or file with no `http.MaxBytesReader` or size check — the
  caller decides your memory usage.
- `json.Unmarshal` of a large payload into `map[string]interface{}` — very high allocation
  count. Prefer a typed struct, or `json.Decoder` for streaming.
- `defer` inside a loop — deferred calls accumulate until the function returns, not the
  iteration. With file handles or locks, that is both a leak and a contention bug.
- A package-level `map` or slice that only ever grows. Especially with request-derived keys.
- `GOMEMLIMIT` unset while the container has a memory limit — see `platform-gke-argocd.md`.

## Database pooling (Class 11)

- `SetMaxOpenConns` / `SetMaxIdleConns` / `SetConnMaxLifetime` unset: `database/sql` defaults
  to **unlimited** open connections. Under load one pod can open hundreds; multiply by
  replicas and you exhaust the server. Always do the `× maxReplicas` arithmetic.
- `SetConnMaxLifetime` unset also prevents rebalancing after a database failover or a
  proxy restart — connections stick to the old endpoint.
- A `*sql.DB` created per request instead of once at startup: this is a pool per request,
  and it is catastrophic. Rare, but check.
- `rows.Close()` missing, or not deferred — holds a connection until GC.

## Concurrency patterns (Class 5)

- Sequential calls in a loop where `errgroup.WithContext` + `SetLimit` would parallelise —
  but flag unbounded parallelism just as hard: `errgroup` without `SetLimit` over a
  user-sized list is a fan-out bomb.
- `sync.WaitGroup` with no concurrency cap over a request-controlled collection.
- Missing `singleflight.Group` around an expensive cache-miss recompute (Class 6).

## CPU hot paths (Class 10)

- `regexp.MustCompile` inside a function rather than at package level — recompiles per call.
- `fmt.Sprintf` for simple concatenation in a hot loop; `strings.Builder` for accumulation.
- Reflection, `encoding/json` on very hot paths, repeated `[]byte`↔`string` conversion.
- `map` allocation per request from constant data.

## HTTP server and client settings

- `http.Server` without `ReadTimeout`, `WriteTimeout`, `IdleTimeout` — slow clients hold
  connections indefinitely.
- `http.Transport` with default `MaxIdleConnsPerHost` (2): under concurrency this forces new
  TCP+TLS handshakes constantly. Raise it for hot dependencies.
- No `MaxHeaderBytes` or body size limit on public endpoints.

## Graceful shutdown (Class 11)

- No `srv.Shutdown(ctx)` on `SIGTERM`, or a shutdown context longer than
  `terminationGracePeriodSeconds`.
- Background goroutines not waited on during shutdown — in-flight work is lost on every
  rollout, and ArgoCD rollouts are frequent.

## Tooling to recommend

`go test -bench . -benchmem` for a suspected hot path (allocs/op is the number to compare),
`-race` for new concurrency, `go vet` and `errcheck`. `/debug/pprof/{heap,goroutine,profile}`
for confirming a leak in a live pod, and `go tool pprof -base` to diff two heap profiles —
that diff is the cleanest way to prove a leak.
