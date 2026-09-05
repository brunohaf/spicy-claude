# Scope resolution — what counts as "the new code"

This skill runs **locally, before the MR is opened**. The developer's work is therefore
split across three places at once, and reviewing only one of them is the most likely way to
miss the thing they just wrote:

1. commits already made on the branch,
2. staged changes,
3. unstaged and untracked files.

**The default is the union of all three.** That is "everything I have done that is not on
main yet" — which is exactly what the MR will contain once they commit and push.

## The default resolution

```bash
git rev-parse --abbrev-ref HEAD
for base in origin/main origin/master main master origin/develop develop; do
  git rev-parse --verify "$base" >/dev/null 2>&1 && BASE=$base && break
done
MERGE_BASE=$(git merge-base "$BASE" HEAD)

# Committed on this branch, plus staged, plus unstaged — in one diff:
git diff "$MERGE_BASE"

# Untracked files are invisible to the above and are frequently the whole new feature:
git ls-files --others --exclude-standard
```

`git diff $MERGE_BASE` (no `..HEAD`) compares the **working tree** against the fork point,
so it captures committed, staged and unstaged changes together. `git diff $MERGE_BASE..HEAD`
would silently drop everything the developer has not committed yet — usually the newest and
least-reviewed code in the branch.

Read untracked files in full; a new file has no diff, and its entire contents are new code.

## Report the split

State it at the top, so the developer knows what was covered:

```
Scope: 14 files vs origin/main@a1b2c3d — 9 committed, 3 staged, 2 untracked
```

If untracked files were found, name them. A developer who forgot to `git add` a new file
learns it here, before the MR is opened with a missing file.

## Fallbacks

- **On the base branch itself, or no upstream:** review `git diff HEAD` plus untracked files,
  and say that no branch point was available.
- **Not a git repository:** ask for a target path. Do not audit the whole tree.
- **Explicit target given** (a path, a commit range, a PR number): it wins over everything
  above.

## Re-runs

This skill is used iteratively — review, fix, review again. On a re-run in the same session,
diff against what was reviewed before and lead with what changed:

- findings the developer fixed → confirm they are resolved, in one line each,
- findings still present → list by number only, do not restate them in full,
- new candidates introduced by the fixes → full treatment.

A fix that introduces a new problem is the highest-value thing a second pass can find; a
batching fix that loads 10,000 rows into memory to avoid an N+1 is the classic example.

## Filter the file list

Include: application source, SQL and migrations, k8s/Helm/ArgoCD manifests, Dockerfiles,
dependency manifests (a version bump can be the regression).

Exclude from *findings*, but still read for context: tests, fixtures, generated code
(`*.pb.go`, `*_pb2.py`, mocks, generated clients), vendored directories, lockfiles, docs.
A new test is often the best available evidence of the intended call volume of new code —
read it even though you will not report on it.

## Read beyond the diff

The diff is the *scope of findings*, never the *scope of reading*. To judge a candidate you
must read the functions it calls, the schema it queries, and the callers that reach it. A
diff-only reading is how a reviewer misses that a new three-line helper is called inside an
existing loop over 10,000 rows.

## Size guard

Pre-MR diffs are usually small; this skill should feel fast. If a diff exceeds ~2,000 changed
lines or ~80 files, say so and prioritise: request handlers, consumers, data access, caching
and concurrency first; config, DTOs and docs last. Report what you did not reach.
