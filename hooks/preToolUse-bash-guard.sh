#!/usr/bin/env bash
# Blocks destructive Bash invocations. Reads the proposed tool call as JSON on
# stdin; path resolved via $CLAUDE_CONFIG_DIR, default ~/.claude.

set -euo pipefail
payload="$(cat)"

# Confirm .tool_input.command against the official hook reference if the schema changes.
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')

if [[ -z "$cmd" ]]; then
  exit 0  # not a Bash tool call; nothing to do
fi

# Regexes, so they catch spacing and flag-order variants the literal Bash(...)
# deny rules in settings.json miss.
deny_patterns=(
  'rm[[:space:]]+-rf?[[:space:]]+/'      # rm -rf /
  'rm[[:space:]]+-rf?[[:space:]]+~'      # rm -rf ~
  'rm[[:space:]]+-rf?[[:space:]]+\$HOME' # rm -rf $HOME
  ':(){.*};:'                            # fork bomb
  'mkfs\.'
  'dd[[:space:]]+if=.*of=/dev/'          # dd to a raw device
)

for re in "${deny_patterns[@]}"; do
  if printf '%s' "$cmd" | grep -E -q "$re"; then
    printf 'pre-tool guard: refusing to run "%s" (matched %s)\n' "$cmd" "$re" >&2
    exit 2
  fi
done

exit 0