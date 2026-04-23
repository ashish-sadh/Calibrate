#!/bin/bash
# PreToolUse on Edit|Write — require senior/junior autopilot to have
# claimed an issue before modifying code. Without this gate, sessions
# silently work off nothing trackable and the Sprint dashboard can't
# reflect live progress (observed: active senior session with zero
# in-progress tags).
#
# Enforced only on autopilot (DRIFT_AUTONOMOUS=1) senior/junior.
# Planning sessions bypass — they don't claim sprint tasks, they work
# off the planning issue directly.
#
# Escape hatches — any one is sufficient:
#   1. sprint-state.in_progress is set (some issue claimed)
#   2. current branch is review/cycle-*, report/exec-*, or design-doc/*
#      (named branches map 1:1 to a known non-sprint flow)
#
# Interactive sessions pass through. Bash / Read / Grep / Glob are not
# gated — sessions can explore, comment on issues, and run
# sprint-service.sh claim freely before their first edit.

set -e

# Only enforce in autopilot
[ "${DRIFT_AUTONOMOUS:-0}" = "1" ] || exit 0

SESSION_TYPE=$(cat "$HOME/drift-state/cache-session-type" 2>/dev/null || echo "")
if [[ "$SESSION_TYPE" != "senior" && "$SESSION_TYPE" != "junior" ]]; then
    exit 0
fi

# Escape 1: a sprint/bug/design issue has been claimed via sprint-service
STATE_FILE="$HOME/drift-state/sprint-state.json"
if [ -f "$STATE_FILE" ]; then
    IN_PROGRESS=$(jq -r '.in_progress // empty' "$STATE_FILE" 2>/dev/null || echo "")
    if [ -n "$IN_PROGRESS" ] && [ "$IN_PROGRESS" != "null" ]; then
        exit 0
    fi
fi

# Escape 2: on a named branch for a report / design doc flow
WORK_DIR="${CLAUDE_PROJECT_DIR:-/Users/ashishsadh/workspace/Drift}"
BRANCH=$(git -C "$WORK_DIR" branch --show-current 2>/dev/null || echo "")
case "$BRANCH" in
    review/cycle-*|report/exec-*|report/*exec*|design-doc/*)
        exit 0
        ;;
esac

# No escape matched — block with an actionable message
cat >&2 <<EOF
BLOCKED: ${SESSION_TYPE} session must claim an issue before editing code.

Pick one of:
  scripts/sprint-service.sh next --${SESSION_TYPE}   # get next task number
  scripts/sprint-service.sh claim <N>                # claim it (sprint-task, bug, or design-doc issue)

Non-sprint flows that bypass this gate:
  - Product review: check out review/cycle-<N> branch
  - Daily exec:     check out report/exec-<date> branch
  - Design doc:     check out design-doc/<slug> branch

Admin replies, gh comments, gh issue close — those are Bash and always allowed.
EOF
exit 2
