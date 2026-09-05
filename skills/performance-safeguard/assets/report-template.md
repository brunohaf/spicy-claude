# Performance review — `<branch>`

> Optional. The terminal is the deliverable (`references/report-contract.md`); use this only
> when the developer explicitly asks for a file, and write it to the scratchpad or a path
> they name — never the repo root, where it will land in their next commit.

**Verdict: <Open the MR | Fix first | Open the MR, flag the tradeoff>** — <one sentence.>

**Scope** base `<origin/main @ sha>` · `<n>` files — `<n>` committed, `<n>` staged, `<n>` untracked
**Untracked** `<names — or "none">`
**Stacks** `<Go 1.x, Python 3.x, Postgres, Redis, Kafka>`
**Platform inputs** `<replicas min/max, CPU/mem limits, pool sizes — or "not found in repo">`

---

## Summary

| # | Sev | Class | Location | Finding | Evidence |
|---|-----|-------|----------|---------|----------|
| 1 | P0 | 3 Locking | `path/file.go:84` | Mutex held across HTTP call | L3 |
| 2 | P1 | 1 Query | `path/repo.py:112` | N+1 on feed enrichment | L2 |
| 3 | P2 | 10 CPU | `path/util.go:22` | Regex compiled per call | L2 |
| 4 | Watch | 2 Memory | `path/cache.py:40` | In-process cache unbounded above ~5k tenants | L2 |

---

## Findings

### [P0] `<title>`
`<file:line>` · Class `<n>` `<name>` · **L`<n>` — `<confirmed by construction | confirmed regression>`**

**Entry point** `<route or consumer>` → `<fn>` → `<fn>`
**Trigger** `<N per request, from where you read it>`
**Traffic** `<tier, rps, replicas, rps/pod>`
**Budget** `<the budget breached, from scale-budgets.md>`

**Arithmetic** `<the multiplication, ending in an absolute number>`

**Failure mode** `<latency | memory growth | OOMKill | CPU saturation | lock contention | connection exhaustion | cascading failure | data loss>`
**Blast radius** `<request | pod | deployment | shared dependency X, also used by Y and Z>`
**Regression** `<yes — introduced by this diff | no — pre-existing, made worse by …>`

**Why I believe it** `<what you checked that failed to refute it: no cache wrapper, no LIMIT downstream, no index in migrations, no rate limit in middleware>`

**Suggested fix** — `<why this fix fits the codebase: names the existing helper/pattern it reuses>`

```diff
- <before>
+ <after>
```

> **Tradeoff — `<the decision>`**
>
> **Option A — `<name>` (recommended)**
> - Pro: `<…>`
> - Con: `<…>`
>
> **Option B — `<name>`**
> - Pro: `<…>`
> - Con: `<…>`
>
> **Recommendation: `<A|B>`**, because `<…>`. **Choose the other if** `<the specific
> condition that flips it>`.

**Check it now** `<the local command; what confirms, what refutes>`

```bash
<EXPLAIN ANALYZE / go test -bench -benchmem / py-spy / hey>
```

**After deploy** `<the production query that watches for the failure mode>`

```sql
<NRQL>
```

---

## Needs data

Reachable, but the trigger volume could not be established from the code.

| Location | Question | Check that settles it, locally |
|---|---|---|
| `<file:line>` | `<how large does X get?>` | `<seed N rows, call it, count queries>` |

---

## Considered and cleared

- `<file:line>` — `<looked like an N+1, but the framework batches it via …>`
- `<file:line>` — `<unbounded list, but the endpoint is admin-only at T0>`
- `<file:line>` — `<loop with a query, but this is a one-shot migration>`

---

## Platform notes

- **Connections** `<pool>` × `<maxReplicas>` = `<total>` vs `max_connections` `<n>` — `<verdict>`
- **Memory** per-request ceiling `<n>` MB; largest observed allocation in the diff `<n>` MB
- **Rollout** `<cold-start amplification, warm-cache dependency, startup duration vs probes>`
- **Shutdown** `<longest new unit of work vs terminationGracePeriodSeconds>`
- **Migrations** `<lock type, table size, expand/contract needed?, sync-wave ordering>`

---

## Paste into the MR description

> **Performance note.** `<the tradeoff that was made, the numbers behind it, and the
> condition under which it should be revisited.>`

---

## After it merges

| Watch | Metric | Threshold | Action |
|---|---|---|---|
| `<finding #>` | `<metric>` | `<value>` | `<roll back / disable flag / scale X>` |

Rollback: `<argocd app rollback APP <revision>, or revert the flag>`
