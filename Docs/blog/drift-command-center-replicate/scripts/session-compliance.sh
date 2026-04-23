#!/bin/bash
# session-compliance.sh — called after every session exit (clean or crash)
# Writes last-session-summary.md and appends to Obsidian session log.
# Must be called BEFORE cleanup_dirty_state so in-progress state is still readable.
#
# Usage: session-compliance.sh <session-type> <model> <exit-reason>
#   exit-reason: normal | crash | stall

set -uo pipefail

WORK_DIR="/Users/ashishsadh/workspace/Drift"
STATE_DIR="$HOME/drift-state"
OBSIDIAN_DIR="$HOME/drift-knowledge"
FEEDBACK_LOG="$STATE_DIR/process-feedback.log"
STATE_FILE="$STATE_DIR/sprint-state.json"

mkdir -p "$STATE_DIR" "$OBSIDIAN_DIR/Sessions"

SESSION_TYPE="${1:-unknown}"
MODEL="${2:-unknown}"
EXIT_REASON="${3:-normal}"

TS=$(date '+%Y-%m-%d %H:%M:%S')
TODAY=$(date '+%Y-%m-%d')

# Close overhead tracking issue (created by session-start.sh hook at session start)
OVERHEAD_N=$(cat "$STATE_DIR/current-overhead-issue" 2>/dev/null | tr -d '[:space:]')
if [[ -n "$OVERHEAD_N" ]] && [[ "$OVERHEAD_N" =~ ^[0-9]+$ ]]; then
    LAST_COMMIT=$(cd "$WORK_DIR" && git rev-parse HEAD 2>/dev/null || echo "no-commit")
    gh issue comment "$OVERHEAD_N" \
      --body "Session ended ($EXIT_REASON). Last commit: $LAST_COMMIT" 2>/dev/null || true
    gh issue close "$OVERHEAD_N" 2>/dev/null || true
    rm -f "$STATE_DIR/current-overhead-issue"
elif [[ -n "$OVERHEAD_N" ]]; then
    echo "[$TS] session-compliance: WARNING invalid overhead issue number '$OVERHEAD_N' — skipping close" >&2
    rm -f "$STATE_DIR/current-overhead-issue"
fi

# Recent commits from this session (last 2 hours)
COMMITS=$(cd "$WORK_DIR" && git log --oneline --since="2 hours ago" 2>/dev/null | head -10 || true)

# Currently claimed in-progress task — readable before cleanup_dirty_state clears it
INTERRUPTED=$(python3 - "$STATE_FILE" 2>/dev/null <<'PYEOF' || true
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    ip = d.get("in_progress")
    if ip:
        title = next((t["title"] for t in d.get("tasks", []) if t["number"] == ip), "")
        print(f"#{ip} {title}")
except json.JSONDecodeError as e:
    print(f"WARNING: state file corrupted ({e}) — interrupted task unknown", file=sys.stderr)
except Exception:
    pass
PYEOF
)

# Write last-session-summary.md (next session reads this at startup)
SUMMARY_FILE="$STATE_DIR/last-session-summary.md"
cat > "$SUMMARY_FILE" <<EOF
# Last Session Summary

**Session type:** $SESSION_TYPE
**Model:** $MODEL
**Ended:** $TS
**Exit reason:** $EXIT_REASON

## Recent Commits (this session)

${COMMITS:-None recorded}

## Interrupted Task

${INTERRUPTED:-None}
EOF

# Append to Obsidian session log
OBSIDIAN_SESSION="$OBSIDIAN_DIR/Sessions/$TODAY.md"
if [[ ! -f "$OBSIDIAN_SESSION" ]]; then
    printf "# Sessions — %s\n" "$TODAY" > "$OBSIDIAN_SESSION"
fi

cat >> "$OBSIDIAN_SESSION" <<EOF

## $SESSION_TYPE ($MODEL) — $TS — exit: $EXIT_REASON

### Commits
${COMMITS:-none}

### Interrupted
${INTERRUPTED:-none}

---
EOF

# Log abnormal exits to process-feedback (planning session drains this)
if [[ "$EXIT_REASON" == "crash" ]] || [[ "$EXIT_REASON" == "stall" ]]; then
    echo "$TS | compliance | $SESSION_TYPE ($MODEL) exited via $EXIT_REASON — interrupted: ${INTERRUPTED:-none}" >> "$FEEDBACK_LOG" 2>/dev/null || true
fi

echo "[$TS] session-compliance: $SESSION_TYPE ($MODEL, $EXIT_REASON) — summary written"
