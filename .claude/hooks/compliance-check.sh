#!/bin/bash
# Hook: PreToolUse on Bash
# Comprehensive compliance check. Reads LOCAL cache files ONLY — zero API calls.
# Cache files are written by the watchdog every 5 minutes.

STATE_DIR="$HOME/drift-state"
MODEL=$(cat "$STATE_DIR/last-model" 2>/dev/null || echo "sonnet")
SESSION_TYPE=$(cat "$STATE_DIR/cache-session-type" 2>/dev/null || echo "junior")
CONTEXT=""

# === ALL SESSIONS ===

# P0 bugs (highest priority)
if [ -s "$STATE_DIR/cache-p0-bugs" ]; then
    CONTEXT="${CONTEXT}P0 BUGS OPEN — fix before other work:\n$(cat "$STATE_DIR/cache-p0-bugs")\n\n"
fi

# Product focus
if [ -s "$STATE_DIR/cache-product-focus" ]; then
    FOCUS=$(head -1 "$STATE_DIR/cache-product-focus")
    [ -n "$FOCUS" ] && CONTEXT="${CONTEXT}PRODUCT FOCUS: ${FOCUS}\n\n"
fi

# TestFlight (autonomous only)
if [ "${DRIFT_AUTONOMOUS:-0}" = "1" ]; then
    LAST_TF=$(cat "$STATE_DIR/last-testflight-publish" 2>/dev/null || echo "0")
    NOW=$(date +%s)
    ELAPSED=$(( NOW - LAST_TF ))
    if [ "$ELAPSED" -gt 10800 ]; then
        HOURS=$(( ELAPSED / 3600 ))
        CONTEXT="${CONTEXT}TESTFLIGHT ${HOURS}h OVERDUE — publish on next commit.\n\n"
    fi
fi

# === SENIOR ONLY (Opus) ===

if [ "$MODEL" = "opus" ]; then
    # Design doc PRs needing reply
    if [ -s "$STATE_DIR/cache-design-reviews" ]; then
        CONTEXT="${CONTEXT}DESIGN DOC PRs NEED REPLY:\n$(cat "$STATE_DIR/cache-design-reviews")\nCheck PR comments, respond, revise doc.\n\n"
    fi

    # Pending design docs (no doc written yet)
    if [ -s "$STATE_DIR/cache-pending-designs" ]; then
        CONTEXT="${CONTEXT}DESIGN DOCS AWAITING PE:\n$(cat "$STATE_DIR/cache-pending-designs")\nCreate branch, write doc, create PR, add doc-ready label.\n\n"
    fi

    # Admin feedback unreplied
    if [ -s "$STATE_DIR/cache-admin-feedback" ]; then
        CONTEXT="${CONTEXT}ADMIN FEEDBACK UNREPLIED:\n$(cat "$STATE_DIR/cache-admin-feedback")\nRead full report at line numbers, reply to every comment.\n\n"
    fi

    # P0 feature requests without sprint tasks
    if [ -s "$STATE_DIR/cache-p0-features" ]; then
        CONTEXT="${CONTEXT}P0 FEATURE REQUESTS — create sprint-task:\n$(cat "$STATE_DIR/cache-p0-features")\n\n"
    fi

    # Approved design docs needing implementation tasks
    if [ -s "$STATE_DIR/cache-approved-designs" ]; then
        CONTEXT="${CONTEXT}APPROVED DESIGNS — create implementation tasks (design-impl-{N} label):\n$(cat "$STATE_DIR/cache-approved-designs")\n\n"
    fi
fi

# === PLANNING ONLY ===

if [ "$SESSION_TYPE" = "planning" ]; then
    CONTEXT="${CONTEXT}PLANNING DELIVERABLES (session BLOCKED from exiting until complete):\n"
    CONTEXT="${CONTEXT}1. Read + reply to ALL admin feedback on report PRs\n"
    CONTEXT="${CONTEXT}2. Write product review report + merge PR\n"
    CONTEXT="${CONTEXT}3. Create 8-12 sprint-task Issues (SENIOR + JUNIOR)\n"
    CONTEXT="${CONTEXT}4. Review ALL open feature requests — P0: sprint-task now, P1: plan in sprint, rest: defer/close\n"
    CONTEXT="${CONTEXT}5. Create implementation tasks for approved design docs (design-impl-{N} label)\n"
    CONTEXT="${CONTEXT}6. Update personas + roadmap\n\n"
fi

# Output
if [ -n "$CONTEXT" ]; then
    cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "${CONTEXT}"
  }
}
ENDJSON
fi

exit 0
