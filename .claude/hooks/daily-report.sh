#!/bin/bash

# Silent for non-autonomous (human) sessions — these hooks are autopilot-only.
[[ "${DRIFT_AUTONOMOUS:-0}" != "1" ]] && exit 0
# Hook: PostToolUse on Bash(git commit *)
# Fallback daily report trigger — planning is primary, this is fallback only.

set -e

DRIFT_CONTROL=$(cat "$HOME/drift-control.txt" 2>/dev/null | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
if [ "$DRIFT_CONTROL" != "RUN" ]; then exit 0; fi

# Only fire in planning sessions (primary) or if planning is stale >12h (fallback)
SESSION_TYPE=$(cat "$HOME/drift-state/cache-session-type" 2>/dev/null || echo "junior")
LAST_REVIEW=$(cat "$HOME/drift-state/last-review-time" 2>/dev/null || echo "0")
NOW=$(date +%s)
PLANNING_STALE=$(( NOW - LAST_REVIEW > 43200 ))  # 12h

if [[ "$SESSION_TYPE" != "planning" ]] && [[ "$PLANNING_STALE" -eq 0 ]]; then
  exit 0  # Planning is active and recent — it will handle the report
fi

# Check if report already done today
if ! "${CLAUDE_PROJECT_DIR:-.}/scripts/report-service.sh" daily-due 2>/dev/null; then
  exit 0  # Already done
fi

TODAY=$(date +%Y-%m-%d)
cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "DAILY EXEC BRIEFING DUE.\n1. scripts/report-service.sh start-exec\n2. Write Docs/reports/exec-${TODAY}.md using EXEC-TEMPLATE.md\n3. git add + commit + push\n4. gh pr create --label report\n5. scripts/report-service.sh finish  — do NOT call gh pr merge directly; finish handles merge + stamp atomically, and the gating timestamps depend on it."
  }
}
ENDJSON
