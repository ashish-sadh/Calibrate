#!/bin/bash
# Hook: PostToolUse on Bash(git commit *)
# 1. Auto-adds in-progress label when a commit references an issue (#N).
# 2. For bugs with screenshots: injects screenshot path for cross-check.

set -e

COMMIT_MSG=$(git log -1 --pretty=%B 2>/dev/null || true)
ISSUE_NUMS=$(echo "$COMMIT_MSG" | grep -oE '#[0-9]+' | grep -oE '[0-9]+' | sort -u)

if [ -z "$ISSUE_NUMS" ]; then
  exit 0
fi

MARKED=""
SCREENSHOT_CHECK=""

for NUM in $ISSUE_NUMS; do
  INFO=$(gh issue view "$NUM" --json state,labels --jq 'select(.state == "OPEN") | .labels | map(.name) | join(",")' 2>/dev/null || true)
  [ -z "$INFO" ] && continue

  # Mark in-progress if not already
  if ! echo "$INFO" | grep -q "in-progress"; then
    if echo "$INFO" | grep -qE "bug|sprint-task|feature-request"; then
      gh issue edit "$NUM" --add-label in-progress 2>/dev/null && MARKED="$MARKED #$NUM"
    fi
  fi

  # For bugs: check if issue has screenshot and extract the path
  if echo "$INFO" | grep -q "bug"; then
    BODY=$(gh issue view "$NUM" --json body --jq '.body' 2>/dev/null || true)
    SCREENSHOT=$(echo "$BODY" | grep -oE 'Docs/screenshots/[^ )]+' | head -1 || true)
    if [ -n "$SCREENSHOT" ] && [ -f "$SCREENSHOT" ]; then
      SCREENSHOT_CHECK="${SCREENSHOT_CHECK}Bug #${NUM} has a screenshot at ${SCREENSHOT}. READ this image NOW and verify your fix addresses what's shown. If it doesn't match, revert and fix properly.\n"
    fi
  fi
done

CONTEXT=""
[ -n "$MARKED" ] && CONTEXT="Marked in-progress:${MARKED}\n\n"
[ -n "$SCREENSHOT_CHECK" ] && CONTEXT="${CONTEXT}SCREENSHOT VERIFICATION REQUIRED:\n${SCREENSHOT_CHECK}"

if [ -n "$CONTEXT" ]; then
  cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "${CONTEXT}"
  }
}
ENDJSON
fi

exit 0
