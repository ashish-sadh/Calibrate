#!/bin/bash
# Hook: PostToolUse on Bash(git commit *)
# 1. Auto-adds in-progress label when a commit references an issue (#N).
# 2. For bugs with screenshots: injects screenshot path for cross-check.

set -e

# Skip for planning sessions — planning creates/manages issues, not works on them
SESSION_TYPE=$(cat "$HOME/drift-state/cache-session-type" 2>/dev/null || echo "")
if [ "$SESSION_TYPE" = "planning" ]; then
  exit 0
fi

COMMIT_MSG=$(git log -1 --pretty=%B 2>/dev/null || true)
ISSUE_NUMS=$(echo "$COMMIT_MSG" | grep -oE '#[0-9]+' | grep -oE '[0-9]+' | sort -u)

if [ -z "$ISSUE_NUMS" ]; then
  exit 0
fi

# Only mark in-progress if commit touches Swift files (actual code work)
HAS_CODE=$(git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null | grep -c '\.swift$' || echo "0")
if [ "$HAS_CODE" -eq 0 ]; then
  exit 0
fi

MARKED=""
SCREENSHOT_CHECK=""
OPEN_NUMS=""

for NUM in $ISSUE_NUMS; do
  INFO=$(gh issue view "$NUM" --json state,labels --jq 'select(.state == "OPEN") | .labels | map(.name) | join(",")' 2>/dev/null || true)
  if [ -z "$INFO" ]; then
    # Issue is closed or doesn't exist — remove from cache
    sed -i '' "/^$NUM$/d" "$HOME/drift-state/cache-in-progress" 2>/dev/null || true
    continue
  fi
  OPEN_NUMS="$OPEN_NUMS $NUM"

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

# Maintain in-progress cache — reuse state from loop above (zero extra API calls)
CACHE_FILE="$HOME/drift-state/cache-in-progress"
for NUM in $OPEN_NUMS; do
  grep -q "^$NUM$" "$CACHE_FILE" 2>/dev/null || echo "$NUM" >> "$CACHE_FILE" 2>/dev/null
done
# Check if other cached issues are stale (not in current commit)
if [ -f "$CACHE_FILE" ]; then
  STALE=""
  while read -r IP_NUM; do
    [ -z "$IP_NUM" ] && continue
    IS_CURRENT=false
    for NUM in $ISSUE_NUMS; do
      [ "$IP_NUM" = "$NUM" ] && IS_CURRENT=true
    done
    $IS_CURRENT || STALE="${STALE}#${IP_NUM} "
  done < "$CACHE_FILE"
  if [ -n "$STALE" ]; then
    CONTEXT="${CONTEXT}STALE IN-PROGRESS — you moved on without closing: ${STALE}\nVerify work is done, then close with comment. Or remove in-progress if unfinished.\n\n"
  fi
fi

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
