# Evidence ladder — the bar a finding must clear

A performance review is only worth reading if the reader can trust that everything in it is
real. One confident-sounding false positive costs more credibility than five missed
findings. Rank every candidate, then **drop anything below L2 from the findings list.**

## The levels

**L0 — Pattern only.** A shape that is sometimes slow, with no established caller.
"There's a loop with a query in it" but the function is unreferenced, or reachable only from
a test. → **Discard silently.**

**L1 — Reachable but unquantified.** Reaches a real entry point, but you cannot establish
how often it runs or how much data it touches. The loop bound comes from a request payload
with no documented limit; the table size is unknown. → **Move to "Needs data"** with the one
query that would settle it. Do not present as a finding.

**L2 — Confirmed by construction.** Reachable, *and* quantified from code, schema, or
config, *and* the arithmetic breaches a budget in `scale-budgets.md`. You can write the
sentence: *"At T3 (≈800 rps across 12 pods = 67 rps/pod), this issues 1 + N queries where N
is the page size of 100, so 6,700 queries/sec/pod against a pool of 20 connections."*
→ **Report as a finding.**

**L3 — Confirmed regression.** L2, *and* the base commit did not have this property. The
diff introduced it. → **Report as a finding, ranked above equivalent L2s.**

## The unbounded shortcut

Genuinely unbounded growth reaches L2 without arithmetic. If a collection, cache, retry
chain or goroutine count has no ceiling and is fed by user-controlled input, "unbounded" is
the proof. Say what feeds it and what the ceiling should be.

## Mandatory suppression rules

Do not report, regardless of how bad the pattern looks:

- One-shot code: migrations, backfills, seeders, build scripts, `main()` setup that runs once.
- Test files, fixtures, benchmarks, local dev tooling.
- Code behind a feature flag that defaults off — unless the diff also flips the default.
  If it does, that *is* the finding.
- Admin/internal endpoints with a bounded, known-low call rate. Say why you cleared it.
- CLI tools and batch jobs where wall-clock time is not a constraint and memory fits.
- Micro-optimisations with no budget impact: string concatenation outside a hot path,
  an extra allocation per request, a map lookup that could be a slice. These are noise.
- Anything whose fix would be slower than the problem it solves.

## Severity, once a finding clears L2

| | Meaning |
|---|---|
| **P0** | Will cause an incident on rollout. Unbounded memory on a hot path, missing timeout on a synchronous dependency, retry amplification, a lock held across I/O, a query that table-scans a large table at T3+. |
| **P1** | Degrades under normal peak, or fails under a plausible spike. N+1 at T2+, cache stampede without jitter, pool sizing that breaks at max replicas, fan-out that multiplies dependency load. |
| **P2** | Real but bounded cost: measurable latency or memory increase that does not threaten stability. Worth fixing, not worth blocking on. |
| **Watch** | Correct today, breaks at a stated growth threshold. Always name the threshold: *"fine below ~5k rows per tenant; the largest tenant today is 1.2k."* |

## Calibration

Before you write a finding, try to refute it. Ask: is there a cache in front of this? a rate
limit? a bounded queue? a `LIMIT` further down? an index that makes the scan cheap? Does the
framework batch this automatically? If you cannot find the refutation, the finding stands —
and say in one clause what you checked. That sentence is what makes it credible.
