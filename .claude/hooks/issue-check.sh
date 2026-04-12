#!/bin/bash
# Hook: PreToolUse on Bash(git commit *)
# Nags to check GitHub Issues if not checked recently (every 2 hours).

set -e

ISSUES_FILE="$HOME/drift-state/issues-checked-this-session"
STALE_THRESHOLD=7200  # 2 hours in seconds

NOW=$(date +%s)
LAST_CHECK=$(cat "$ISSUES_FILE" 2>/dev/null || echo "0")
ELAPSED=$((NOW - LAST_CHECK))

if [ "$ELAPSED" -lt "$STALE_THRESHOLD" ]; then
  exit 0  # Recently checked, don't nag
fi

cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "REMINDER: Check GitHub Issues before continuing. Run: gh issue list --state open --label bug\nIf there are P0 bugs, fix them before other work. After checking, update the timestamp: echo \$(date +%s) > ~/drift-state/issues-checked-this-session"
  }
}
ENDJSON

exit 0
