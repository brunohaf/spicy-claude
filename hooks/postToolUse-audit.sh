#!/usr/bin/env bash
# ~/.claude/hooks/postToolUse-audit.sh
set -euo pipefail

LOG_DIR="${CLAUDE_AUDIT_DIR:-$HOME/.claude/audit}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date -u +%Y-%m-%d).jsonl"

# Pass the JSON payload through unchanged, with a wall-clock prefix.
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '{"ts":"%s","payload":%s}\n' "$ts" "$(cat)" >> "$LOG_FILE"
exit 0