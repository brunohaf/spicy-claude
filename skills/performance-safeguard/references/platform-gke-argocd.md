# Platform — GKE and ArgoCD

Code review that ignores the deployment substrate misses a whole category of incident. Read
the manifests in the repo; they are inputs to the arithmetic in `scale-budgets.md`.

## What to read from the repo

```bash
git ls-files | grep -Ei '(deployment|statefulset|hpa|pdb|values|kustomization|application)\.ya?ml$'
git ls-files | grep -Ei '^(k8s|deploy|manifests|charts|helm|argocd)/'
```

Extract: `replicas`, HPA min/max and target metric, `resources.requests/limits`, probe
settings and timings, `terminationGracePeriodSeconds`, `strategy` (rolling update surge and
unavailable), PodDisruptionBudget, node selectors and topology spread, and — from ArgoCD —
`syncPolicy`, sync waves, and whether `prune`/`selfHeal` are enabled.

## The multiplication rule

Every per-pod resource is really a cluster-wide resource. When the diff changes any of
these, multiply by `maxReplicas` and check the far end:

| Per-pod setting | Multiply by maxReplicas, check against |
|---|---|
| DB connection pool | Database `max_connections` / pgbouncer pool size |
| Redis/cache client pool | Redis `maxclients`, and its single-threaded op budget |
| Outbound HTTP connections | The dependency's capacity and its own connection limits |
| Consumer concurrency | Partition count, and downstream write capacity |
| In-process cache size | Pod memory limit — this one does *not* multiply, it must fit |

Autoscaling makes this dynamic: the cluster is fine at 8 pods and exhausts the database at
40 — during the traffic spike that caused the scale-up. This is the most common way a change
that passed load testing still takes down production.

## Memory and OOMKill

- The memory *limit* is a hard kill, not a target. A pod exceeding it is `OOMKilled` with no
  stack trace and no graceful shutdown — Sentry usually shows nothing, only the restart.
- Runtimes do not know about cgroup limits unless told. Flag when the diff adds significant
  memory use without a corresponding runtime setting:
  - **Go:** `GOMEMLIMIT` should be ~80–90% of the container memory limit, otherwise the GC
    will not collect aggressively enough to avoid the kill.
  - **Python:** no equivalent. Per-worker memory × worker count must fit the limit, and
    fragmentation plus copy-on-write behaviour after `fork` make actual usage higher than
    the arithmetic suggests.
- `requests` far below `limits` puts the pod in the `Burstable` QoS class, so it can be
  evicted under node pressure. A memory-hungry change raises eviction risk for *other* pods
  on the same node.

## CPU limits and throttling

CPU limits throttle rather than kill. A change that adds CPU work to a pod already near its
limit shows up as p99 latency with no slow span anywhere — the classic hard-to-diagnose
regression. If the diff adds meaningful CPU to a service whose limit is close to its
request, say so and name `container_cpu_cfs_throttled_seconds_total` as the metric to watch.

## Startup, probes and rollout

- Work added to startup lengthens rollouts and can trip `startupProbe`/`readinessProbe`
  thresholds. For new warm-up, cache preload, migration check or schema fetch on boot,
  compare its duration against `initialDelaySeconds + (failureThreshold × periodSeconds)`.
- **Cold-start amplification:** during a rollout every replica restarts. Anything a pod does
  once on boot happens `replicas` times within a few minutes — an empty in-process cache
  means a full-cluster cache-miss storm hits the database at the moment of deploy. This is a
  real and frequently missed failure mode; call it out whenever the diff adds a dependency
  on a warm cache.
- **Graceful shutdown:** on `SIGTERM` the pod must stop accepting work, drain in-flight
  requests, and finish or requeue consumer messages within `terminationGracePeriodSeconds`
  (default 30s), or it is `SIGKILL`ed. Any new long-running work — a slow request, a long
  consumer handler, a detached goroutine or background task — must be checked against that
  window. Work that outlives it is silently lost.
- **Readiness flapping:** a pod that reports ready before it is warm receives traffic, fails,
  and restarts. Look for readiness checks that do not actually exercise the dependencies the
  pod needs to serve.

## ArgoCD specifics

- **`selfHeal: true`** reverts manual `kubectl` changes. Any mitigation that involves editing
  live resources must go through git instead, or it will be undone. Mention this whenever a
  suggested workaround is "scale up" or "raise the limit".
- **Sync waves** order resources. A migration in an earlier wave than the deployment changes
  the schema before the new code runs. Flag any backwards-incompatible migration that lacks
  a two-phase (expand/contract) plan: during a rolling update, old and new code run
  simultaneously against one schema.
- **Progressive rollout as a legitimate mitigation:** for a P1 that is expensive to fix
  properly, shipping behind a flag and ramping while watching a named metric is a real
  option. If you suggest it, say which metric and which threshold should trigger rollback.
- Automated sync with `prune` means a merged PR reaches production without a human gate. The
  time from merge to blast radius is minutes, which raises the bar for knowingly shipping a
  P1.

## PodDisruptionBudget and node events

If the diff makes pods slower to start or drain, node upgrades and preemption — common on
GKE, especially with Spot or preemptible node pools — become more disruptive. A PDB of
`minAvailable: 1` on a two-replica deployment plus a 90-second startup means a capacity dip
on every node event.
