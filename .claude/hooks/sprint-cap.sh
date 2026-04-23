#!/bin/bash
# PreToolUse on Bash — cap open sprint-task issues at SPRINT_CAP.
#
# Rationale: planning cycles accumulate sprint tasks faster than execution
# closes them. Past a certain queue depth the backlog becomes noise — no
# one scrolls past the top 20, stale items rot, and planners still feel
# compelled to hit the "8+ sprint tasks created" checklist target. Capping
# the queue forces planners to focus on closing / deleting / consolidating
# before adding more.
#
# Enforced only on autopilot (DRIFT_AUTONOMOUS=1). Interactive sessions
# can override — the human knows what they're doing.

set -e

SPRINT_CAP=100

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

# Only block `gh issue create … --label sprint-task`. Don't care about
# other gh invocations. Match by literal substring so `gh issue comment`,
# `gh issue view`, etc. aren't affected.
if ! echo "$COMMAND" | grep -qE 'gh issue create .*--label[= ]sprint-task'; then
    exit 0
fi

# Interactive sessions bypass
[ "${DRIFT_AUTONOMOUS:-0}" = "1" ] || exit 0

OPEN_COUNT=$(gh issue list --state open --label sprint-task --json number --jq 'length' 2>/dev/null || echo "0")

if [ "$OPEN_COUNT" -ge "$SPRINT_CAP" ]; then
    cat >&2 <<EOF
BLOCKED: Sprint queue at $OPEN_COUNT/$SPRINT_CAP. Do NOT create more sprint-task issues.

Instead:
  - Close stale tasks that no longer reflect priorities
  - Consolidate duplicate / near-duplicate issues
  - Mark superseded items 'wontfix' with a comment pointing to the replacement
  - Focus this session on executing existing tasks, not filing new ones

Checklist "8+ sprint tasks created" is satisfied by keeping the queue
fresh, not by padding it.
EOF
    exit 2
fi

exit 0
