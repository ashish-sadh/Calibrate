#!/bin/bash
# Hook: PreToolUse on Bash(git commit *)
# Every commit: checks for open bug issues and surfaces them.

set -e

# Query open bugs directly
BUGS=$(gh issue list --state open --label bug --json number,title,labels --jq '[.[] | select(.labels | map(.name) | index("needs-review") | not)] | .[] | "#\(.number) \(.title) [\(.labels | map(.name) | join(","))]"' 2>/dev/null || echo "")

if [ -z "$BUGS" ]; then
  exit 0  # No bugs, proceed
fi

BUG_COUNT=$(echo "$BUGS" | wc -l | tr -d ' ')

cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "OPEN BUGS (${BUG_COUNT}):\n${BUGS}\n\nP0 bugs must be fixed before other work. P1 bugs should be addressed soon. If you can fix any of these in your current cycle, do it."
  }
}
ENDJSON

exit 0
