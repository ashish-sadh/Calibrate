#!/bin/bash
# stuck-detector.sh — PostToolUse hook.
#
# Liveness-via-progress detector. The watchdog already kills sessions with no
# heartbeat in 1h. This hook adds finer-grained signals: a session is "stuck"
# even if it's making tool calls, if those tool calls aren't producing
# progress on the claimed issue.
#
# Signals tracked per session (state at ~/drift-state/stuck-detector/<session_id>.json):
#   - tool_calls_since_diff_growth   (zero diff growth over last N calls)
#   - file_read_counts               (same file Read >K times)
#   - tool_calls_since_plan_update   (no plan/progress issue comment update)
#   - first_seen_at                  (session bootstrap timestamp)
#
# Thresholds (enforced only when DRIFT_STUCK_DETECTOR_ENFORCE=1):
#   - >=30 tool calls with zero git-diff line-count growth → mark stuck
#   - >=5 reads of the same file → mark stuck
#   - >=20 tool calls with no issue comment update on the claimed issue → mark stuck
#
# When stuck (enforce mode): the hook writes ~/drift-state/stuck-session-kill
# with the session id + reason. The watchdog's main loop reads this file each
# pass and kills + abandons (sprint-service.sh abandon) when set.
#
# Shadow mode (default): write the file with `[shadow]` prefix; watchdog
# logs but does not kill.

set -e

# Silent for non-autonomous (human) sessions
[ "${DRIFT_AUTONOMOUS:-0}" != "1" ] && exit 0

# Phase 3c 2026-05-26: planning sessions are research-heavy by design.
# The new slim planning skill (15→8 steps) intentionally does many Reads
# (Explore sub-agent + manual code-research) + optional WebSearch BEFORE
# any local diff. The 30-calls-no-diff-growth threshold misfires against
# this shape — observed 2026-05-26 09:18: planning killed at 32 tool
# calls during legitimate research. Watchdog's 1h-no-heartbeat kill +
# planning's own context-budget self-check still cover genuine stuck.
[ "${DRIFT_SESSION_TYPE:-}" = "planning" ] && exit 0

INPUT=$(cat 2>/dev/null || echo '{}')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // {}')

if [ -z "$SESSION_ID" ]; then
    exit 0
fi

STATE_DIR="$HOME/drift-state/stuck-detector"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/$SESSION_ID.json"

# Initialize state file if missing
if [ ! -f "$STATE_FILE" ]; then
    cat > "$STATE_FILE" <<EOF
{
  "session_id": "$SESSION_ID",
  "first_seen_at": $(date +%s),
  "tool_calls_total": 0,
  "tool_calls_since_diff_growth": 0,
  "tool_calls_since_plan_update": 0,
  "file_read_counts": {},
  "last_diff_size": 0
}
EOF
fi

# Increment totals
CURRENT=$(cat "$STATE_FILE")
TOTAL=$(echo "$CURRENT" | jq '.tool_calls_total + 1')

# Measure current diff size (lines)
DIFF_SIZE=$(git diff --numstat 2>/dev/null | awk '{sum += $1 + $2} END {print sum+0}')
LAST_DIFF=$(echo "$CURRENT" | jq '.last_diff_size // 0')

DIFF_GROWTH=$((DIFF_SIZE - LAST_DIFF))
if [ "$DIFF_GROWTH" -gt 0 ]; then
    SINCE_DIFF=0
else
    SINCE_DIFF=$(echo "$CURRENT" | jq '.tool_calls_since_diff_growth + 1')
fi

# Track Read calls per file
FILE_COUNTS=$(echo "$CURRENT" | jq '.file_read_counts')
if [ "$TOOL_NAME" = "Read" ]; then
    READ_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // ""')
    if [ -n "$READ_PATH" ]; then
        FILE_COUNTS=$(echo "$FILE_COUNTS" | jq --arg p "$READ_PATH" '.[$p] = (.[$p] // 0) + 1')
    fi
fi

# Plan/progress comment update detection: any Bash call that posts to gh issue comment on the claimed issue
IN_PROGRESS=$(cat "$HOME/drift-state/in-progress-issue" 2>/dev/null || echo "")
SINCE_PLAN=$(echo "$CURRENT" | jq '.tool_calls_since_plan_update + 1')
if [ -n "$IN_PROGRESS" ] && [ "$TOOL_NAME" = "Bash" ]; then
    CMD=$(echo "$TOOL_INPUT" | jq -r '.command // ""')
    if echo "$CMD" | grep -qE "gh issue comment.*$IN_PROGRESS|issues_comment.*$IN_PROGRESS"; then
        SINCE_PLAN=0
    fi
fi

# Write updated state
UPDATED=$(echo "$CURRENT" | jq \
    --argjson total "$TOTAL" \
    --argjson since_diff "$SINCE_DIFF" \
    --argjson since_plan "$SINCE_PLAN" \
    --argjson file_counts "$FILE_COUNTS" \
    --argjson diff_size "$DIFF_SIZE" \
    '. + {tool_calls_total: $total, tool_calls_since_diff_growth: $since_diff, tool_calls_since_plan_update: $since_plan, file_read_counts: $file_counts, last_diff_size: $diff_size}')
echo "$UPDATED" > "$STATE_FILE"

# Threshold checks
STUCK_REASON=""

if [ "$SINCE_DIFF" -ge 30 ]; then
    STUCK_REASON="zero_diff_growth: ${SINCE_DIFF} tool calls without diff growth"
fi

MAX_READ_COUNT=$(echo "$FILE_COUNTS" | jq '[.[]] | max // 0')
if [ "$MAX_READ_COUNT" -ge 5 ]; then
    REPEATED_FILE=$(echo "$FILE_COUNTS" | jq -r 'to_entries | max_by(.value).key')
    STUCK_REASON="repeated_file_read: $REPEATED_FILE read ${MAX_READ_COUNT} times"
fi

if [ "$SINCE_PLAN" -ge 20 ] && [ -n "$IN_PROGRESS" ]; then
    STUCK_REASON="no_comment_update: ${SINCE_PLAN} tool calls without comment on #$IN_PROGRESS"
fi

if [ -n "$STUCK_REASON" ]; then
    KILL_FILE="$HOME/drift-state/stuck-session-kill"
    if [ "${DRIFT_STUCK_DETECTOR_ENFORCE:-0}" = "1" ]; then
        echo "{\"session_id\":\"$SESSION_ID\",\"reason\":\"$STUCK_REASON\",\"detected_at\":$(date +%s)}" > "$KILL_FILE"
        cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "[stuck-detector] session marked stuck: $STUCK_REASON. Watchdog will abandon claimed issue."
  }
}
EOF
    else
        # Shadow mode: log only
        LOG="$HOME/drift-state/stuck-detector.log"
        echo "$(date '+%Y-%m-%d %H:%M:%S') [shadow] $SESSION_ID stuck: $STUCK_REASON" >> "$LOG"
    fi
fi

exit 0
