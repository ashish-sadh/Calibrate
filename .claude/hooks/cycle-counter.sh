#!/bin/bash
# Hook: PostToolUse on Bash(git commit *)
# Fires on every commit. Enforces: DRAIN/PAUSE stop, feedback replies, bug comments.

set -e

SESSION_TYPE=$(cat "$HOME/drift-state/cache-session-type" 2>/dev/null || echo "junior")

# 1. DRAIN/PAUSE — graceful stop after this commit. ONLY enforced on autopilot
#    sessions. Ground truth for "is this autopilot" is DRIFT_AUTONOMOUS=1, which
#    the watchdog exports before launching Claude. The cache-session-type file
#    is unreliable here because each autopilot spawn overwrites it and human
#    sessions inherit the stale "senior"/"junior" stamp.
DRIFT_STATE=$(cat "$HOME/drift-control.txt" 2>/dev/null | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
if [ "${DRIFT_AUTONOMOUS:-}" = "1" ] && { [ "$DRIFT_STATE" = "DRAIN" ] || [ "$DRIFT_STATE" = "PAUSE" ]; }; then
  cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "${DRIFT_STATE} ACTIVE. This was your last commit. Push and exit now. Do NOT start new work."
  }
}
ENDJSON
  exit 0
fi

# 2. Count cycles
COUNTER_FILE="$HOME/drift-state/cycle-counter"
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# 3. Build context injection based on session role
CONTEXT=""

# All roles: close bugs with a comment
CONTEXT="${CONTEXT}ALWAYS: When closing a bug Issue, reply with a comment: what was fixed + commit hash. Never close silently.\n\n"

# Senior + planning only: reply to admin report PR comments
if [[ "$SESSION_TYPE" == "senior" || "$SESSION_TYPE" == "planning" ]]; then
  CONTEXT="${CONTEXT}ALWAYS: If you see admin (ashish-sadh, nimisha-26) comments on report PRs that haven't been replied to, reply with what action was taken or will be taken. Every admin comment gets a response.\n\n"
fi

# All roles: P0 escalation
CONTEXT="${CONTEXT}P0 BUGS: If you encounter a P0 bug that's too complex for your current session, relabel it SENIOR: gh issue edit {N} --add-label SENIOR\n\n"

echo "Cycle $COUNT."

cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "Cycle $COUNT.\n\n${CONTEXT}"
  }
}
ENDJSON

exit 0
