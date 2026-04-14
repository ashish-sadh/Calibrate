#!/bin/bash
# Hook: PostToolUse on Bash(git commit *)
# Auto-adds in-progress label when a commit references an issue (#N).
# Only marks actionable issues (bug, sprint-task, feature-request) that are open.

set -e

# Extract issue numbers from the last commit message
COMMIT_MSG=$(git log -1 --pretty=%B 2>/dev/null || true)
ISSUE_NUMS=$(echo "$COMMIT_MSG" | grep -oE '#[0-9]+' | grep -oE '[0-9]+' | sort -u)

if [ -z "$ISSUE_NUMS" ]; then
  exit 0
fi

MARKED=""
for NUM in $ISSUE_NUMS; do
  # Check if issue is open and actionable, skip if already in-progress
  INFO=$(gh issue view "$NUM" --json state,labels --jq 'select(.state == "OPEN") | .labels | map(.name) | join(",")' 2>/dev/null || true)
  [ -z "$INFO" ] && continue
  echo "$INFO" | grep -q "in-progress" && continue
  echo "$INFO" | grep -qE "bug|sprint-task|feature-request" || continue
  gh issue edit "$NUM" --add-label in-progress 2>/dev/null && MARKED="$MARKED #$NUM"
done

if [ -n "$MARKED" ]; then
  cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "Marked in-progress:${MARKED}"
  }
}
ENDJSON
fi

exit 0
