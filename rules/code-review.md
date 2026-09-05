# Code Review

Scope: applies only to an explicit review of a diff, branch or MR. Not to ordinary
implementation turns.

## Flag

- Correctness bugs: off-by-one, null handling, error paths, race conditions
- Security: injection risks, missing auth checks, secrets in code
- Missing tests for new logic
- N+1 queries and unbounded queries
- Convention violations from `CLAUDE.md`, `CLAUDE.local.md` or `.claude/rules/`
- Unrelated bugs: flag them, never fix them in the same change

## Do NOT flag

- Style preferences not written down in project rules
- Refactoring suggestions for working code
- Anything outside this diff

## Output

Group findings by severity: Critical / High / Medium / Low.
Each finding: file + line + issue + suggested fix.
End with a verdict: **SHIP**, **FIX FIRST**, or **REWORK**.
