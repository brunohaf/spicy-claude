# Report contract

The output goes to the **terminal**, for the developer who wrote the code, before they open
the MR. Not a document, not a file in their repo. Shape it for someone who is going to act
on it in the next five minutes and then push.

## Rules

- **Verdict first**, on line two: **Open the MR** / **Fix first** / **Open the MR, flag the
  tradeoff**. One sentence of justification. If *Fix first*, name the one finding responsible.
- **Scope line first of all:** base, file count, and the committed/staged/untracked split.
- **Full detail for P0 and P1 only.** P2 and Watch get one line each in a table. The
  developer can ask for detail on any of them.
- **Every finding carries `file:line`, entry point, quantity, budget, evidence level.**
  Missing any of these means it is not ready — complete it or drop it.
- **Never bare-assert.** "This is slow" is not a finding. "6,700 Redis calls/sec/pod against
  a budget of ≤1 added round trip per request" is.
- **Suggested diffs only. Never edit the working tree.** Their uncommitted work is in it.
- **No file written** unless asked. If asked, use the scratchpad or a path they name — never
  the repo root.
- **Ordering:** P0, P1, then the P2/Watch table. Within a severity, higher evidence level
  first, then wider blast radius.

## Finding format — P0 and P1

```markdown
### [P1] N+1 query in feed enrichment
`internal/feed/enrich.go:84` (unstaged) · Class 1 · **L3 — confirmed regression**

**Path** `GET /v1/feed` → `FeedHandler.List` → `enrichItems` → `repo.GetAuthor`
**Trigger** one query per item; page size defaults to 100, caller may request up to 500
**Traffic** T3 (~800 rps, 12 replicas → 67 rps/pod)
**Budget** ≤ 1 additional query per request on T3 (`scale-budgets.md`)

**Arithmetic** 67 rps/pod × 100 items = 6,700 queries/sec/pod, 80k/sec cluster-wide, against
a pool of 20 connections per pod. At 2 ms per query that needs 13.4 connection-seconds of
capacity per second from a pool that supplies 20 — requests queue for a connection before
the database itself saturates.

**Fails as** connection-pool exhaustion → request queueing → p99 cliff → readiness failures.
**Blast radius** whole deployment, plus the primary that three other services share.
**Checked against** no batching path in `enrichItems`; no cache wrapper on `GetAuthor`
(unlike `GetUser` in the same package); no `LIMIT` between handler and repository.

**Fix** — `GetAuthorsByIDs` already exists and is used by `internal/profile/bulk.go:41`:

```diff
-for i := range items {
-    author, err := s.repo.GetAuthor(ctx, items[i].AuthorID)
-    if err != nil {
-        return nil, err
-    }
-    items[i].Author = author
-}
+ids := make([]int64, 0, len(items))
+for i := range items {
+    ids = append(ids, items[i].AuthorID)
+}
+authors, err := s.repo.GetAuthorsByIDs(ctx, ids)
+if err != nil {
+    return nil, err
+}
+for i := range items {
+    items[i].Author = authors[items[i].AuthorID]
+}
```

**Check it now** — against your local database, with a seeded feed:
```bash
go test ./internal/feed -run TestFeedList -v 2>&1 | grep -c 'SELECT.*authors'
```
> More than one `authors` query confirms it. One confirms the fix.
```

## The P2 / Watch table

```markdown
| Sev | Location | Finding | Why it is not P1 |
|---|---|---|---|
| P2 | `util.go:22` | Regex compiled per call | ~0.4% of the CPU budget at T3 |
| Watch | `cache.py:40` | In-process tenant cache unbounded | Fine below ~5k tenants; largest today 1.2k |
```

## Tradeoff block

Use when more than one reasonable fix exists, or the fix costs something real. Give a
recommendation **and** the condition under which the other option wins — the developer
decides, but an unranked list of options is not advice.

```markdown
> **Tradeoff — how to fix the feed N+1**
>
> **A — batch the query (recommended)**
> - Pro: removes the N+1 entirely; one query regardless of page size; the repository method
>   already exists and is already tested.
> - Con: the `IN` list needs chunking above ~1,000 ids; authors still fetched every request.
>
> **B — cache authors in Redis, 5-minute TTL**
> - Pro: also removes the load for repeat views; helps other endpoints.
> - Con: staleness — a renamed author shows the old name for up to 5 minutes.
> - Con: adds stampede risk needing jitter and single-flight (Class 6).
> - Con: at 80k lookups/sec you are moving load to Redis, not removing it.
>
> **Recommendation: A** — strictly smaller, no new failure modes, the code exists.
> **Choose B instead if** author data is read far more often than the feed itself and you
> already need it cached elsewhere; then do both, batch first.
```

## MR description paragraph

When the verdict is **Open the MR, flag the tradeoff**, end with a block the developer can
paste straight into the MR description. This is what stops a reviewer re-litigating a
decision that was already thought through, and it is often the most-used part of the output:

```markdown
**Paste into the MR description:**

> **Performance note.** `enrichItems` batches author lookups via `GetAuthorsByIDs` rather
> than caching them. At the current feed volume (~800 rps) caching would move 80k lookups/sec
> to Redis rather than remove them, and would introduce up to 5 minutes of name staleness.
> Batching keeps it at one query per request with no staleness. Revisit if author reads grow
> independently of feed reads.
```

## Sections, in order

1. **Scope line** — base, file count, committed/staged/untracked split, untracked files named.
2. **Verdict** — one line, one sentence.
3. **P0 and P1 findings** — full format.
4. **P2 / Watch table** — one line each.
5. **Needs data** — candidates that are reachable but unquantified, each with the single
   check that settles it. Keep to a few lines; offer to dig into any of them.
6. **Considered and cleared** — one line each. Keep it short here: the developer knows their
   own code, and the value is confirming you looked, not explaining their code back to them.
7. **MR description paragraph** — only when there is a tradeoff worth recording.

## When there is nothing to report

Two lines, plus *Considered and cleared*. A clean check that shows what it looked at is a
good result. Padding it with P2 filler to appear productive destroys the signal that makes
the P0s worth reading — and a developer who gets noise before every MR stops running this.
