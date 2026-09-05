# Scale budgets — turning "1B users" into arithmetic

A finding needs a number to be a finding. This file turns the service's scale into per-pod
budgets you can check a code path against.

## Step 1 — Find the real numbers first

Always prefer evidence in the repo over the defaults below. Look for:

- `replicas`, and HPA `minReplicas`/`maxReplicas` + `targetCPUUtilizationPercentage`
- `resources.requests` / `resources.limits` for CPU and memory
- rate limits, quotas, throttles in middleware or gateway config
- connection pool sizes, worker/thread counts, consumer concurrency
- load-test scripts (k6, Locust, Gatling, JMeter) — these state intended throughput
- SLO/alert definitions, existing dashboards-as-code
- comments or ADRs stating traffic figures

**Say which numbers you found and which you assumed.** A finding built on a stated
assumption is honest; one built on an unstated assumption is a guess.

## Step 2 — Assign a traffic tier per entry point

Derived from ~1M DAU on the service, with the usual caveats: traffic is not uniform, peak is
3–5× the daily mean, and a handful of endpoints carry most of it.

| Tier | Sustained rps (service-wide) | Typical of |
|---|---|---|
| **T0** | < 1 | Admin, internal tools, manual operations |
| **T1** | 1–50 | Settings writes, account changes, low-frequency writes |
| **T2** | 50–500 | Secondary reads, search, list views, most writes |
| **T3** | 500–5,000 | Core read paths, feed/home/detail, session validation, auth |
| **T4** | > 5,000 | Edge middleware, health/session checks, anything on every request |

Default when you truly cannot tell: **T2 for a new endpoint, T3 for code added to an
existing shared path** (middleware, a base repository, a serializer, a client wrapper). Code
on a shared path inherits the traffic of everything that uses it — this is the assumption
that most often turns out to matter.

**Per-pod rps = tier rps ÷ current replica count.** Use the *minimum* replica count for
steady state, and remember that during an ArgoCD rollout you may briefly have fewer healthy
pods than you think.

## Step 3 — Check against the budgets

### Latency
| Tier | Budget for added p99 latency, per change |
|---|---|
| T4 | ≤ 1 ms |
| T3 | ≤ 5 ms |
| T2 | ≤ 25 ms |
| T1/T0 | ≤ 200 ms |

Anything that adds a network round trip to a T3/T4 path is over budget by construction: a
same-region database or cache call is 0.5–2 ms, a cross-service HTTP call 5–50 ms, a
cross-region call 50–150 ms.

### Database round trips
- **T3/T4: ≤ 1 additional query per request.** N+1 with N ≥ 10 on a T3 path is P1; N
  unbounded, or N ≥ 100, is P0.
- Total queries per request should stay in single digits on read paths.
- Compare added query volume against the pool: `queries/sec/pod × avg query ms ÷ 1000` must
  stay well under the pool size, or requests queue for a connection — which shows up as
  latency with no slow query to blame for it.

### Memory
```
concurrent requests per pod ≈ (rps per pod) × (p99 seconds)
per-request allocation ceiling ≈ (pod memory limit × 0.5) ÷ concurrent requests
```
Worked example: T3 at 800 rps over 12 pods = 67 rps/pod; p99 of 150 ms → ~10 concurrent
requests; a 1 GiB limit with 50% headroom → ~50 MB per request absolute ceiling, and you
should target **under 1 MB**. Anything holding tens of MB per request on a hot path is an
OOMKill waiting for a traffic spike.

Any per-request allocation proportional to user-controlled input, with no cap, is P0 —
because the ceiling is set by the caller, not by you.

### CPU
Pod CPU limit in cores × 1000 = millicores. Budget per request = `millicores ÷ rps per pod`.
At 67 rps/pod with a 1-core limit, that is ~15 ms of CPU per request *total*. Report a
CPU finding when the added work plausibly consumes >10% of that: hashing per item on a
100-item list, a regex compiled per call, JSON round-tripping a large structure. Below 10%,
it is noise — suppress it.

### Fan-out
Calls to a dependency = your rps × calls per request. **Any per-item call to a dependency on
a T2+ path is a finding.** State the resulting load on the dependency in absolute terms;
that number is what makes the argument, and it is often the number nobody had computed.

### Connections (the multiplication that surprises people)
```
total connections = pool size per pod × maxReplicas
```
Check against the database's actual `max_connections` (or the pgbouncer/proxy limit).
Include sidecars and any job/cron pods using the same credentials. Exceeding it during an
autoscale event is a P0 that only appears under load — which is precisely when you cannot
afford it.

## Step 4 — Write the arithmetic into the finding

Never write "this could be slow at scale". Write:

> At T3 (~800 rps, 12 pods → 67 rps/pod), `enrichItems` issues one Redis `GET` per item over
> a page of 100, i.e. **6,700 Redis calls/sec/pod, 80k/sec cluster-wide** against a Redis
> handling ~40k ops/sec today. Budget is ≤1 added round trip per request on T3.

The second version is arguable, checkable, and actionable. The first is an opinion.
