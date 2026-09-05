# performance-safeguard

A Claude Code skill a developer runs **on their own branch, before opening the merge
request**. It reviews committed, staged and untracked work together for performance and
stability risks at high traffic, and reports only what it can substantiate.

## Install

Copy the skill directory to one of:

```bash
# Personal — available in every project
cp -r performance-safeguard ~/.claude/skills/

# Project — checked in, available to the team
cp -r performance-safeguard <repo>/.claude/skills/
```

Then, in the target repository, fill in `references/service-profile.md`. This is the step
that determines the quality of every review — see below.

## Use

Run it as the last thing before opening the MR. It triggers on natural requests, not a
command name:

- "check this for perf problems before I open the MR"
- "will this scale?"
- "review my changes for N+1s and memory leaks"
- "anything here that'll blow up under load?"

Or invoke it directly with `/performance-safeguard`.

## What it does

1. Resolves scope as **committed + staged + unstaged + untracked** against the branch point,
   and reports the split — so nothing you haven't committed yet gets skipped.
2. Loads only the language packs matching your diff, plus the datastore pack when relevant.
3. Sweeps for twelve failure classes to build a candidate inventory.
4. Triages, then deeply traces only the candidates that could be P0/P1: entry point, trigger
   quantity, per-pod budget.
5. Drops anything that cannot clear the evidence bar, rather than downgrading it into noise.
6. Prints findings to the terminal with suggested diffs, tradeoff blocks, and **a check you
   can run locally right now** — `EXPLAIN ANALYZE`, a benchmark, `py-spy` — plus the New
   Relic query to watch after it ships.

It **never edits your working tree**, **writes no file into your repo** (you're about to
commit), and does not review security, style or test coverage.

Re-run it after fixing. A second pass confirms what you fixed in one line each and looks for
problems the fixes introduced — a batching fix that loads 10,000 rows to avoid an N+1 is the
classic one.

## Structure

```
performance-safeguard/
├── SKILL.md                       # trigger + six-phase orchestration
├── references/
│   ├── service-profile.md         # ← fill this in per repository
│   ├── scope-resolution.md        # what counts as "new code on this branch"
│   ├── taxonomy.md                # the twelve failure classes
│   ├── evidence-ladder.md         # L0–L3 proof bar and suppression rules
│   ├── scale-budgets.md           # traffic tiers → latency/memory/CPU/connection budgets
│   ├── platform-gke-argocd.md     # limits, HPA, probes, drain, rollout, pool × replicas
│   ├── observability.md           # NRQL / Sentry / kubectl / SQL verification queries
│   ├── report-contract.md         # output schema and tradeoff block format
│   ├── datastore.md               # databases, caches, queues (language-independent)
│   └── lang/{go,python}.md        # per-language detectors
└── assets/report-template.md
```

Only `name` and `description` in `SKILL.md` affect triggering. Everything else is read after
activation, and the `references/` files are read only when relevant to the diff at hand.

## Tuning

**`service-profile.md` is the highest-leverage file.** Real traffic and capacity numbers turn
findings that would be reported as "reachable but unquantified" into findings with
arithmetic attached. A review run against an empty profile is useful; one run against a
filled-in profile is decisive.

If the skill triggers when you don't want it, or misses when you do, edit only the
`description` in `SKILL.md` — that string is the entire trigger surface. If findings are
noisy, tighten `evidence-ladder.md`. If they miss a class of problem your team keeps hitting,
add it to `taxonomy.md` and the relevant language pack.

## Adding a language

Copy the shape of `references/lang/go.md`: detector cues, why each bites at scale, what
refutes it, and the tooling that confirms it in production. Then add the file to the Phase 2
list in `SKILL.md`.
