#!/bin/bash
# Hook: PostToolUse on Bash(git commit *)
# Nags if P0 bugs exist but the commit isn't for a P0 bug.

set -e

P0_BUGS=$(gh issue list --state open --label P0 --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null || true)
if [ -z "$P0_BUGS" ]; then exit 0; fi

# If the commit references a P0 bug, they're working on it — don't nag
COMMIT_MSG=$(git log -1 --pretty=%B 2>/dev/null || true)
for NUM in $(echo "$P0_BUGS" | grep -oE '#[0-9]+' | tr -d '#'); do
    echo "$COMMIT_MSG" | grep -q "#$NUM" && exit 0
done

P0_COUNT=$(echo "$P0_BUGS" | wc -l | tr -d ' ')

cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "P0 BUGS STILL OPEN (${P0_COUNT}). You committed non-P0 work while P0s exist. STOP current task and fix these FIRST:\n${P0_BUGS}\n\nP0 bugs are higher priority than sprint-tasks, design docs, and features. Switch NOW."
  }
}
ENDJSON

exit 0
