# spicy-claude

<p align="center">
  <img src="assets/spicy-claude-logo.png"
       alt="spicy-claude logo: a chilli pepper in sunglasses running Claude Code, mug of Spicy Code Fuel in hand"
       width="220">
</p>

My spicy-[claude](https://claude.com/claude-code) user configuration: the authored
parts of `~/.claude`, without the session data, caches or credentials.

Tuned for a Python / GKE / GitLab / Jira stack. If you fork it, the two places to
swap are the CLI names in rule 1 of `CLAUDE.md` and any relevant Makefile targets in its Development Workflow.

## Layout

| Path | What it is |
|---|---|
| `LICENSE` | MIT |
| `CLAUDE.md` | Global instructions loaded into every session, in every project |
| `settings.json` | Permissions, model, enabled plugins, marketplaces, theme. Inspired by [hidekazu-konisi's article](https://hidekazu-konishi.com/entry/claude_code_harness_and_environment_engineering_guide.html)|
| `hooks/` | Shell hooks wired up by `settings.json`: a Bash guard and a tool-use audit log |
| `rules/` | Task-scoped rules, read only when a task calls for them |
| `skills/` | Authored [Agent Skills](https://docs.claude.com/en/docs/agents-and-tools/agent-skills) |
| `plugins/` | Plugins as submodules so the pin travels with the repo. The rest of `plugins/` is runtime state and stays ignored |
| `assets/` | Repository artwork referenced by this README |
| `agents/`, `commands/`, `output-styles/` | Reserved. Empty today, and pre-named in `.gitignore` so the first file added is tracked instead of silently ignored |

### `CLAUDE.md`

Four sections, deliberately gated so stack-specific rules stay dormant elsewhere:

- Behavioral Principles: always on. CLI over MCP, no unrequested remote writes,
  cite the tool and command behind every claim, priority order for engineering calls.
- Problem Framing: only when the task names a ticket, spans multiple files, or is
  a production incident.
- Development Workflow: only when the repo has a Makefile.
- Code Review: a pointer to `rules/code-review.md`.

A global file is read on every turn of every project, so an ungated rule ("group
findings by severity, end with a verdict") leaks into answers that have nothing to
do with it.

### `rules/`

`~/.claude/rules/` is not an auto-loaded path, unlike `CLAUDE.md` and a project's
own `.claude/rules/`. Files here are reachable only because `CLAUDE.md` points at
them by name. So the review criteria cost one file read when reviewing, and zero
context when not.

### `skills/`

Made to work with skills submodules, so the pins travel with the repo and an update is a commit here rather than a silent content change. See "Skills submodule" under Install.

### `plugins/manbun/`

A Claude Code *plugin*, not a skill: lazy-senior-dev mode, my fork of [ponytail](https://github.com/DietrichGebert/ponytail) (private for now). It carries its own `.claude-plugin/marketplace.json`, so the repository is a single-plugin
marketplace that installs itself.

It lives under `plugins/` because that is where Claude Code keeps plugins.
Everything else in that directory is runtime state (`cache/`, `marketplaces/`,
`installed_plugins.json`) and stays ignored, so the allowlist opens `plugins/`
for traversal and re-includes exactly one child:

```gitignore
!plugins/
!plugins/manbun
!plugins/manbun/
!plugins/manbun/**
```

The submodule is the pin and an offline copy; it is not what makes the plugin
load. Claude Code loads plugins from its own cache under
`~/.claude/plugins/cache/`, and the two entries in `settings.json` are the wiring
that travels:

```json
"extraKnownMarketplaces": { "manbun": { "source": { "source": "github", "repo": "brunohaf/manbun" } } },
"enabledPlugins":         { "manbun@manbun": true }
```

A local checkout can be registered instead, which is what makes vendoring worth
the submodule: edits to the working tree become the installed plugin.

```bash
claude plugin marketplace add ./plugins/manbun    # source type: directory
```

That records an absolute path in `~/.claude/plugins/known_marketplaces.json`,
which this repository does not track, so it is a per-machine convenience rather
than a replacement for the `settings.json` entries above.

It also rewrites the `extraKnownMarketplaces` entry in `settings.json` itself to
a `directory` source with an absolute path. That file is tracked, so check
`git diff settings.json` after registering a local marketplace and restore the
`github` source before committing. The installed plugin loads from
`~/.claude/plugins/cache/` either way, so restoring it costs nothing.

`.claude-plugin/marketplace.json` requires an `owner` object with a non-empty
`name`. A manifest without it fails to parse from *any* source type, and the
plugin then silently never loads.

### `agents/`

Discovery here is recursive, and identity comes from the `name:` frontmatter
rather than the path. `skills/` is the opposite: pinned to exactly
`skills/<name>/SKILL.md`, one level deep. So agents can be foldered freely;
skills cannot.

The directory ships empty, pre-named in `.gitignore` so the first agent added is
tracked instead of silently ignored. Anything vendored in here needs an upstream
licence that permits redistribution; see License below.

## Install

Three ways to get the repository's contents to where Claude Code reads them:
make the clone *be* `~/.claude`, keep it anywhere and point `CLAUDE_CONFIG_DIR`
at it, or leave it where it is and link the parts you want into `~/.claude`. The
first two need no links, so they work on Windows without Developer Mode.

Whichever you pick, pull the skills first.

### Skills submodule

`skills/` is a submodule, and the skills inside it can be submodules of their own,
so the init has to recurse:

```bash
git submodule update --init --recursive
git submodule status --recursive    # every line should show a commit, not a leading -
```

The same command pulls `plugins/manbun/`. Nothing else is needed for the plugin,
which installs from its marketplace rather than the working tree.

Every `skills/<name>/SKILL.md` that ends up under `~/.claude/skills/` has its
description loaded into every session, so a skill you never use still costs
context. Vendor the whole submodule and link only the ones you want:

```powershell
cmd /c mklink /J "$env:USERPROFILE\.claude\skills\performance-safeguard" "$PWD\skills\performance-safeguard"
```

```bash
ln -s "$PWD/skills/performance-safeguard" ~/.claude/skills/performance-safeguard
```

Skills Claude Code syncs down itself live in `~/.claude/skills/synced/`. Link per
skill; a junction over `skills/` as a whole hides them.

### In place

The repo *is* `~/.claude`, so initialise in place instead of cloning over it:

```bash
cd ~/.claude
git init
git remote add origin <your-remote>
git add -A
git status
```

### `CLAUDE_CONFIG_DIR`

Point Claude Code at the clone, wherever it lives. The variable relocates the
whole configuration directory (settings, session history and plugins all move
with it), which is why `.gitignore` here is an allowlist: the session state lands
inside the working tree and stays ignored until a path is named.

```bash
export CLAUDE_CONFIG_DIR="$HOME/src/claude-config"    # ~/.bashrc, ~/.zshrc
```

```powershell
[Environment]::SetEnvironmentVariable('CLAUDE_CONFIG_DIR', 'E:\src\claude-config', 'User')
```

Hook commands in `settings.json` are written as
`"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/..."` so they follow the clone instead
of pointing at a `~/.claude` that may no longer hold them. A hardcoded path fails
*silently* here, the same way a missing submodule would.

Verify with `/context` in a new session: `CLAUDE.md` should appear under Memory
files. The relocation is total, so a machine that already had a populated
`~/.claude` starts fresh on history and plugins; the authored config is the only
part the repository carries.

### Symlinks

Leave the clone where it is and link its components into `~/.claude`. The repo
becomes the source of truth for the authored config, while the session state
Claude Code writes next to it (`projects/`, `sessions/`, `plugins/`,
`skills/synced/`) stays on the local disk instead of moving with the clone, as it
would under `CLAUDE_CONFIG_DIR`.

Link exactly the paths `.gitignore` allows: `CLAUDE.md`, `settings.json`,
`README.md`, `.gitignore`, `hooks/`, `rules/`, and the skills you picked above.

```bash
repo="$PWD"
for p in CLAUDE.md settings.json README.md .gitignore hooks rules; do
  ln -s "$repo/$p" ~/.claude/"$p"
done
```

On Windows the two link types differ in what they cost. A directory junction
needs no privilege:

```powershell
cmd /c mklink /J "$env:USERPROFILE\.claude\rules" "$PWD\rules"
```

A file symlink needs Developer Mode or an elevated shell, and a hardlink is not a
substitute when the clone and `~/.claude` sit on different drives:

```powershell
# once, elevated
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' AllowDevelopmentWithoutDevLicense 1 -Type DWord
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.claude\settings.json" -Target "$PWD\settings.json"
```

Move the originals aside before linking, `settings.json` in particular, since the
repo's copy replaces the permissions, plugins and hooks the machine was running.
Verify with `Get-ChildItem ~\.claude -Force | Where-Object LinkType` on Windows or
`ls -l ~/.claude` elsewhere, then check `/context` in a new session.

## What is deliberately not here

Session and machine state, all of it either private or regenerable:
`.credentials.json`, `projects/` (full conversation transcripts), `history.jsonl`,
`plans/`, `file-history/`, `backups/`, `sessions/`, `jobs/`, `tasks/`, `session-env/`,
`plugins/`, `security/`, `cache/`, `shell-snapshots/`,
`daemon/`, `downloads/`, `ide/`.

`.gitignore` is an allowlist (`*` first, then explicit `!` re-includes), so anything
a future Claude Code release adds is ignored until it is named. Verify before a
first push:

```bash
git add -A && git status --porcelain -uall
```

## License

[MIT](LICENSE). The repository carries only authored content: instructions, hooks,
skills and settings written here.

Third-party material is deliberately *not* vendored. The projects under
References are credited as influences and reading, not redistributed: a prompt
or agent copied from a repository with no `LICENSE` file is all-rights-reserved by
default, whatever this repository's own licence says. If you add someone else's
agent or skill under `agents/` or `skills/`, check that its upstream licence
permits redistribution first.

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
