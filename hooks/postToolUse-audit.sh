#!/usr/bin/env bash
# Appends every tool-use payload to a daily JSONL log, unchanged apart from a
# wall-clock prefix. Path resolved via $CLAUDE_CONFIG_DIR, default ~/.claude.
set -euo pipefail

LOG_DIR="${CLAUDE_AUDIT_DIR:-$HOME/.claude/audit}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date -u +%Y-%m-%d).jsonl"

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '{"ts":"%s","payload":%s}\n' "$ts" "$(cat)" >> "$LOG_FILE"
exit 0