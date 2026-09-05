---
name: performance-safeguard
description: Self-review of your own branch changes for performance and scalability risks, before opening a merge request. Use when the user wants a perf check before they open an MR or PR, commit or push; asks whether their change will scale or hold up under load; or raises N+1 queries, unbounded queries, missing indexes, memory leaks, OOM, goroutine or connection leaks, CPU hot paths, blocking calls in async code, lock contention, long transactions, cache stampedes, retry storms, missing timeouts, queue backpressure, fan-out, hot partitions, or pod restarts and HPA thrash. Built for distributed Kubernetes/GKE services with databases, caches and queues, shipped via ArgoCD and observed with New Relic and Sentry. Reviews committed, staged and untracked work together, proves or refutes each candidate against per-pod budgets, and returns suggested diffs with checks the developer can run locally. Not for security, style or test-coverage review; never edits code.
license: MIT
---

# Performance Safeguard

Review the code on this branch for changes that will degrade, destabilise or break a
high-traffic distributed service. Report only what you can substantiate; give a decision,
not a lint dump.

**You are reviewing the developer's own work, in their working tree, before they open the
merge request.** That shapes everything:

- They can still change anything cheaply. Nothing is locked in by review comments or a
  green pipeline, so a structural fix is realistic here in a way it will not be later.
- Their code is spread across commits, the index and untracked files. Review all of it.
- They will run this repeatedly while fixing. It must be fast, and a second pass must not
  repeat itself.
- They can **run things** — a local database, a benchmark, a profiler, a load generator.
  Prefer a check they can execute in the next thirty seconds over a production query they
  cannot run yet.
- Write to their terminal, not to their repository. They are about to commit; do not put
  an untracked report file in the way.

## Operating rules

1. **Never edit code.** Every fix is a suggested diff inside the report. The reviewer does
   not become the author.
2. **No finding without a reachable entry point.** If you cannot name the request path,
   consumer, cron or startup hook that executes the code, it is not a finding.
3. **No finding without a quantity.** Every finding states how many times the hot operation
   runs per request/message, or how large the data it touches gets.
4. **Suppress below L2.** Findings that do not clear the evidence bar in
   `references/evidence-ladder.md` are dropped, not downgraded. A short "Considered and
   cleared" list at the end is how you show your work.
5. **Match the codebase.** Fixes use libraries, helpers and idioms already present in the
   repo. If the repo has a `pkg/cache` wrapper, use it; do not introduce a new dependency.
6. **Out of scope:** security vulnerabilities, code style, naming, test coverage,
   architecture preferences, and anything the diff does not touch. Pre-existing hot spots
   are mentioned only when the diff makes them meaningfully worse.
7. **Be fast, and say what you skipped.** A pre-MR check that takes five minutes gets run
   once and then avoided. Spend the investigation budget on the few candidates that could
   be P0/P1; clear the rest quickly and list them in one line each.

## Phase 1 — Resolve scope

Follow `references/scope-resolution.md`. The default scope is **committed + staged +
unstaged + untracked** work against the branch point — `git diff $(git merge-base origin/main
HEAD)` plus `git ls-files --others --exclude-standard`, not `..HEAD`, which would miss
everything not yet committed.

State the base and the file split (committed / staged / untracked) in the first line of
output. If the diff is empty, say so and stop. On a re-run, follow the re-run rules in that
file: confirm fixes in one line, do not restate unchanged findings.

## Phase 2 — Profile the change

**First, read `references/service-profile.md`.** Any value filled in there is ground truth
and overrides the defaults in `scale-budgets.md`. Values left as `UNKNOWN` fall back to the
defaults — and the report must say which figures were assumed rather than known.

From the changed files, determine:

- **Languages present.** Load only the matching packs from `references/lang/`. Load
  `references/datastore.md` whenever the diff touches SQL, an ORM, a cache client, or a
  queue/stream client in any language.
- **Runtime shape.** Read k8s manifests, Helm charts, ArgoCD `Application` specs,
  `Dockerfile`s and config in the repo for replica counts, CPU/memory limits, HPA targets
  and probe settings. These are inputs to Phase 4 — see `references/platform-gke-argocd.md`.
- **Traffic tier per touched entry point.** Assign a tier using
  `references/scale-budgets.md`. Prefer real evidence from the repo (route tables,
  HPA `maxReplicas`, existing rate limits, load-test configs) over the default tier.

## Phase 3 — Build the candidate inventory

Sweep the diff against the twelve classes in `references/taxonomy.md`. Breadth over depth
here: list every candidate with `file:line`, class, and a one-line reason. Cheap and
inclusive — do not judge yet. Aim to have every plausible candidate on the list before any
of them is investigated.

## Phase 4 — Assess each candidate

**Triage before you dig.** Rank the inventory by plausible severity, then spend depth only
where it can change the answer:

- Candidates that could be P0/P1 — unbounded growth, missing timeout, lock across I/O,
  per-item dependency call, pool sizing — get the full trace below.
- Everything else gets a fast pass: if it is clearly bounded, clearly cold, or clearly
  below budget, clear it and record one line for *Considered and cleared*.

For each candidate that survives triage, establish:

| Field | How to establish it |
|---|---|
| **Entry point** | Trace callers up to an HTTP handler, gRPC method, queue consumer, scheduled job or init path. Grep for the symbol; follow until you hit a boundary or run out of callers. |
| **Trigger quantity** | The loop bound, page size, batch size, collection length, or fan-out factor. Read it from code, schema, config or a default. If it is genuinely unbounded, say `unbounded` — that is the strongest possible answer. |
| **Traffic tier** | From Phase 2, for that entry point. |
| **Budget breached** | The specific budget from `references/scale-budgets.md` and the arithmetic. |
| **Failure mode** | Latency / memory growth / OOM / CPU saturation / lock contention / connection exhaustion / cascading failure / data loss. |
| **Blast radius** | One request, one pod, the whole deployment, or a shared dependency other services also use. Shared-dependency findings outrank pod-local ones at equal severity. |
| **Regression?** | Did this property exist before the diff? Compare against the base. A pre-existing pattern the diff merely relocates is not a regression — label it. |

Then apply `references/evidence-ladder.md` to assign L0–L3. Drop L0 and L1 from findings;
L1 items that are cheaply verifiable move to the "Needs data" section with the exact query
that would settle them.

## Phase 5 — Build the remedy

For each surviving finding, write a suggested diff that uses the codebase's existing
idioms. Where more than one reasonable fix exists, or the fix costs something real
(complexity, consistency, memory, latency, a new dependency, an operational burden), emit a
**Tradeoff block** in the format required by `references/report-contract.md`. State a
recommendation and the condition under which the other option wins — but leave the choice
to the user.

Attach a verification step to every finding, from `references/observability.md`. **Prefer a
local check the developer can run right now** — `EXPLAIN ANALYZE` against their dev database,
a `go test -bench -benchmem` comparison, `py-spy` on a local run, a quick `hey`/`k6` burst —
over a production query they cannot run until this ships. Give the production query too,
where it is the only thing that can settle the question, and label it as post-deploy.

## Phase 6 — Report to the terminal

Follow `references/report-contract.md`. **Terminal output is the deliverable.** Do not write
a file into the repository unless asked — the developer is about to commit, and an untracked
report file gets committed by accident or clutters `git status` at exactly the wrong moment.
If they want a file, use the scratchpad path or a location they name.

Lead with the verdict:

| Verdict | Meaning |
|---|---|
| **Open the MR** | Nothing above P2. Anything found is worth knowing, not worth blocking on. |
| **Fix first** | At least one P0/P1 with a fix that is cheap now and expensive after review. |
| **Open the MR, flag the tradeoff** | A real cost exists, but the decision is not yours or theirs alone — it needs a reviewer or an owner. Give them the paragraph to paste into the MR description. |

One sentence of justification, then the findings. If the verdict is *Fix first*, say which
single finding is the reason.
