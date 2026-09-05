# Service profile — the real numbers

This file is the skill's single source of ground truth about the service. Everything in
`scale-budgets.md` is a *default*; anything filled in here **overrides it**, and every value
you supply converts findings that would sit at L1 ("reachable but unquantified") into L2
("confirmed by construction"). It is the highest-leverage file in the skill.

Leave a line as `UNKNOWN` and the skill falls back to the default and says so in the report.
Never guess here — a wrong number here produces confident wrong findings, which is worse
than an honest default.

---

## Traffic

```yaml
# Service-wide sustained requests per second, and the peak multiplier over that.
sustained_rps: UNKNOWN
peak_multiplier: UNKNOWN        # e.g. 4 if peak is 4x the daily mean
peak_window: UNKNOWN            # e.g. "19:00-22:00 UTC", "Monday mornings"

# The endpoints that carry most of the traffic, highest first. These are the paths where a
# budget breach is an incident rather than a cost.
hot_paths:
  - route: UNKNOWN              # e.g. GET /v1/feed
    rps: UNKNOWN
  - route: UNKNOWN
    rps: UNKNOWN

# Anything executed on every single request, regardless of route (middleware, auth, session
# lookup, feature-flag init). Code added here inherits T4.
always_on_path: UNKNOWN         # e.g. internal/middleware/, app/middleware.py
```

## Capacity

```yaml
replicas_min: UNKNOWN
replicas_max: UNKNOWN           # HPA maxReplicas — the multiplier for every pool
cpu_limit: UNKNOWN              # e.g. "1000m"
memory_limit: UNKNOWN           # e.g. "2Gi"
termination_grace_period: 30    # seconds; the shutdown budget for new long-running work
```

## Dependencies and their ceilings

```yaml
postgres:
  max_connections: UNKNOWN
  pool_size_per_pod: UNKNOWN
  largest_hot_table: UNKNOWN    # name and approximate row count — decides "is a scan fatal"
  has_read_replica: UNKNOWN

redis:
  ops_per_sec_headroom: UNKNOWN # current ops/sec vs what it can take
  maxmemory: UNKNOWN
  eviction_policy: UNKNOWN

queue:
  broker: UNKNOWN               # kafka | sqs | pubsub | rabbitmq
  partitions: UNKNOWN           # caps consumer parallelism regardless of pod count
  consumer_concurrency: UNKNOWN

# Services that call us, and services we call. Fan-out findings are scored against these:
# a change that multiplies load onto a dependency shared by other teams outranks a
# pod-local problem of the same size.
upstream_callers: UNKNOWN
downstream_shared_dependencies: UNKNOWN
```

## SLOs — what "too slow" means here

```yaml
latency_slo_p99_ms: UNKNOWN     # the number a latency finding is measured against
availability_slo: UNKNOWN       # e.g. 99.9 — sets how much error budget a risky ship spends
error_budget_state: UNKNOWN     # healthy | tight | exhausted; tight budgets raise the bar
```

## Codebase conventions the fixes must respect

```yaml
# Naming these stops the skill suggesting a fix that introduces a redundant dependency.
http_client: UNKNOWN            # e.g. internal/httpx, app.clients.base
cache_wrapper: UNKNOWN          # e.g. pkg/cache, app.cache.get_or_set
batch_loader: UNKNOWN           # e.g. dataloader, repo.GetByIDs convention
metrics_lib: UNKNOWN
feature_flags: UNKNOWN          # and whether evaluation is local or a network call
forbidden: UNKNOWN              # patterns the team has already rejected
```

---

## How to fill this in

Most of it comes from places you already have:

| Field | Where |
|---|---|
| `sustained_rps`, `hot_paths` | New Relic: `SELECT rate(count(*), 1 second) FROM Transaction FACET name SINCE 7 days ago` |
| `replicas_*`, limits, grace period | `kubectl get hpa,deploy -n NS -o yaml`, or the repo manifests |
| `max_connections`, pool size | `SHOW max_connections;` and the pool config in code |
| `partitions` | broker console, or the topic definition in the repo |
| SLOs | the existing alert/SLO definitions |

Fill in the traffic and capacity blocks first — those two unlock the majority of the
arithmetic. The rest can stay `UNKNOWN` until a review needs them.
