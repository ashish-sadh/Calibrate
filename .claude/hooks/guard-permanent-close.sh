#!/bin/bash

# Silent for non-autonomous (human) sessions — these hooks are autopilot-only.
[[ "${DRIFT_AUTONOMOUS:-0}" != "1" ]] && exit 0
# Hook: PreToolUse on Bash(gh issue close *)
# Blocks closing permanent tasks — they must stay open forever.

set -e

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

NUM=$(echo "$COMMAND" | grep -oE 'gh issue close [0-9]+' | grep -oE '[0-9]+$' | head -1)
[ -z "$NUM" ] && exit 0

IS_PERM=$(gh issue view "$NUM" --json labels --jq '[.labels[].name] | index("permanent-task") != null' 2>/dev/null || echo "false")
if [ "$IS_PERM" = "true" ]; then
    echo "BLOCKED: Issue #$NUM is a permanent-task — NEVER close it. Use: scripts/sprint-service.sh session-done $NUM" >&2
    exit 2
fi
exit 0
