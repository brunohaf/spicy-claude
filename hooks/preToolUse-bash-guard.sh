#!/usr/bin/env bash
# hooks/preToolUse-bash-guard.sh - resolved via $CLAUDE_CONFIG_DIR, default ~/.claude
# Reads the proposed tool invocation as JSON on stdin.

set -euo pipefail
payload="$(cat)"

# Extract the proposed command. The tool input schema for Bash is at
# .tool_input.command (verified 2026-04 at code.claude.com/docs/en/hooks).
# Confirm against the official hook reference if the schema changes.
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')

if [[ -z "$cmd" ]]; then
  exit 0  # not a Bash tool call; nothing to do
fi

# A regex-based denylist that catches shapes a literal pattern cannot.
deny_patterns=(
  'rm[[:space:]]+-rf?[[:space:]]+/'      # rm -rf / or variants
  'rm[[:space:]]+-rf?[[:space:]]+~'      # rm -rf ~
  'rm[[:space:]]+-rf?[[:space:]]+\$HOME' # rm -rf $HOME
  ':(){.*};:'                            # classic fork bomb
  'mkfs\.'                               # any mkfs.* invocation
  'dd[[:space:]]+if=.*of=/dev/'          # dd to a raw device
)

for re in "${deny_patterns[@]}"; do
  if printf '%s' "$cmd" | grep -E -q "$re"; then
    printf 'pre-tool guard: refusing to run "%s" (matched %s)\n' "$cmd" "$re" >&2
    exit 2
  fi
done

exit 0