# spicy-claude

<p align="center">
  <img src="assets/spicy-claude-logo.png"
       alt="spicy-claude logo: a chilli pepper in sunglasses running Claude Code, mug of Spicy Code Fuel in hand"
       width="220">
</p>

My spicy-[claude](https://claude.com/claude-code) user configuration — the authored
parts of `~/.claude`, without the session data, caches or credentials.

Tuned for a Python / GKE / GitLab / Jira stack. If you fork it, the two places to
swap are the CLI names in rule 1 of `CLAUDE.md` and any relevant Makefile targets in its Development Workflow.

## Layout

| Path | What it is |
|---|---|
| `CLAUDE.md` | Global instructions loaded into every session, in every project |
| `settings.json` | Permissions, model, enabled plugins, marketplaces, theme. Inspired [hidekazu-konisi's article](https://hidekazu-konishi.com/entry/claude_code_harness_and_environment_engineering_guide.html)|
| `agents/` | Authored and vendored [subagents](https://code.claude.com/docs/en/sub-agents) |
| `hooks/` | Shell hooks wired up by `settings.json` - a Bash guard and a tool-use audit log |
| `rules/` | Task-scoped rules, loaded on demand rather than every turn |
| `skills/` | Authored [Agent Skills](https://docs.claude.com/en/docs/agents-and-tools/agent-skills) |
| `assets/` | Repository artwork referenced by this README |
| `commands/`, `output-styles/` | Reserved. Empty today, but pre-named in `.gitignore` so the first file added is tracked rather than silently ignored |

### `CLAUDE.md`

Four sections, deliberately gated so stack-specific rules stay dormant elsewhere:

- **Behavioral Principles** — always on. CLI over MCP, no unrequested remote writes,
  cite the tool and command behind every claim, priority order for engineering calls.
- **Problem Framing** — only when the task names a ticket, spans multiple files, or is
  a production incident.
- **Development Workflow** — only when the repo has a Makefile.
- **Code Review** — a pointer to `rules/code-review.md`.

The gating is the point. A global file is read on every turn of every project, so an
ungated rule ("group findings by severity, end with a verdict") leaks into answers that
have nothing to do with it.

### `rules/`

`~/.claude/rules/` is **not** an auto-loaded path — unlike `CLAUDE.md` and a project's
own `.claude/rules/`. Files here are reachable only because `CLAUDE.md` points at them
by name. That is the trade: the review criteria cost one file read when reviewing, and
zero context when not.

### `skills/`

- **`performance-safeguard`** — self-review of your own branch for performance and
  scalability risk before opening an MR. Built for distributed Kubernetes services with
  databases, caches and queues; proves or refutes each candidate finding against per-pod
  budgets instead of guessing.

### `agents/`

Discovery here is **recursive** and identity comes from the `name:` frontmatter,
not the path — unlike `skills/`, which is pinned to exactly
`skills/<name>/SKILL.md`, one level deep. So agents can be foldered freely;
skills cannot.

- **`python-backend-engineer`** (`agents/python-backend-engineer.md`) — Python
  backend work: APIs, data access layers, workers, auth, async services. Adapted from [hesreallyhim/a-list-of-claude-code-agents](https://github.com/hesreallyhim/a-list-of-claude-code-agents/blob/main/agents/python-backend-engineer.md) — the prose, structure and
  worked examples of that agent are the starting point for this one, and the name is kept as upstream's so the lineage stays obvious.
  Changes from upstream: the `CLAUDE.md` priority order
  (correctness → fail-safety → performance → backwards compatibility) and its migration-path rule; verification deferred to the repo's Makefile or README instead of a hardcoded `black`/`isort` invocation; flag-don't-fix for unrelated bugs; an explicit `tools` allowlist and `model: inherit` where upstream inherits every tool by default; and perf sign-off delegated to the `performance-safeguard` skill rather than duplicated.

## Install

Two ways to get the repository's contents to where Claude Code reads them: make
the clone *be* `~/.claude`, or keep it anywhere and point `CLAUDE_CONFIG_DIR` at
it. Neither needs symlinks, so both work on Windows without Developer Mode.

### In place

The repo *is* `~/.claude`, so initialise rather than cloning over it:

```bash
cd ~/.claude
git init
git remote add origin <your-remote>
git add -A
git status
```

### `CLAUDE_CONFIG_DIR`

Point Claude Code at the clone, wherever it lives. The variable relocates
the whole configuration directory — settings, session history and plugins all
move with it — which is why `.gitignore` here is an allowlist: the session state
lands inside the working tree and stays ignored until a path is named.

```bash
export CLAUDE_CONFIG_DIR="$HOME/src/claude-config"    # ~/.bashrc, ~/.zshrc
```

```powershell
[Environment]::SetEnvironmentVariable('CLAUDE_CONFIG_DIR', 'E:\src\claude-config', 'User')
```

Hook commands in `settings.json` are written as
`"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/..."` so they follow the clone instead
of pointing at a `~/.claude` that may no longer hold them - a hardcoded path fails
*silently* here, the same way a missing submodule would.

Verify with `/context` in a new session: `CLAUDE.md` should appear under **Memory
files**. One caveat — the relocation is total, so a machine that already had a
populated `~/.claude` starts fresh on history and plugins; the authored config is
the only part the repository carries.

## What is deliberately not here

Session and machine state, all of it either private or regenerable:
`.credentials.json`, `projects/` (full conversation transcripts), `history.jsonl`,
`plans/`, `file-history/`, `backups/`, `sessions/`, `jobs/`, `tasks/`, `session-env/`,
`plugins/` (clones of public marketplaces), `security/`, `cache/`, `shell-snapshots/`,
`daemon/`, `downloads/`, `ide/`.

`.gitignore` is an allowlist — `*` first, then explicit `!` re-includes — so anything a
future Claude Code release adds is ignored until it is named. Verify before a first push:

```bash
git add -A && git status --porcelain -uall
```

## References

- [Beyond the Prompt: Claude Code](https://arps18.github.io/posts/claude-code-mastery/) by Arpan Patel
- [Claude Code Harness and Environment Engineering: Designing the Frontline Where Local AI Agents Actually Live](https://hidekazu-konishi.com/entry/claude_code_harness_and_environment_engineering_guide.html)
- [Writing a good CLAUDE.md](https://www.humanlayer.dev/blog/writing-a-good-claude-md) by Kyle @ humanlayer
- [Awesome Claude Code](https://github.com/hesreallyhim/awesome-claude-code) and [A List of Claude-Code Agents](https://github.com/hesreallyhim/a-list-of-claude-code-agents) by hesreallyhim
- [Learn Claude Code](https://github.com/shareAI-lab/learn-claude-code) by shareAI-lab
- [Mattpocock's Skills](https://github.com/mattpocock/skills) by mattpocock
- [Andrej Karpathy's Skills](https://github.com/multica-ai/andrej-karpathy-skills) by multica-ai
- [Cloude Skills](https://github.com/Jeffallan/claude-skills) by Jeffallan
- [Claude Development Skills](https://github.com/VelimirMueller/claude_development_skills) by VelimirMueller
- [Awesome Claude Code Subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) by VoltAgent
- [Context Engineering Kit](https://github.com/NeoLabHQ/context-engineering-kit) by NeoLabHQ
- [Claudelog](https://claudelog.com/)
