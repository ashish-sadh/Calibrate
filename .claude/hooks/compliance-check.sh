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
HAS_P0=false
if [ -s "$STATE_DIR/cache-p0-bugs" ]; then
    CONTEXT="${CONTEXT}[1] P0 BUGS — fix before anything else:\n$(cat "$STATE_DIR/cache-p0-bugs")\n\n"
    HAS_P0=true
fi

# Product focus
if [ -s "$STATE_DIR/cache-product-focus" ]; then
    FOCUS=$(head -1 "$STATE_DIR/cache-product-focus")
    [ -n "$FOCUS" ] && CONTEXT="${CONTEXT}PRODUCT FOCUS: ${FOCUS}\n\n"
fi

# Bugs with screenshots (all sessions — must view before fixing)
if [ -s "$STATE_DIR/cache-bugs-with-screenshots" ]; then
    CONTEXT="${CONTEXT}BUGS WITH SCREENSHOTS (download + view before fixing):\n$(cat "$STATE_DIR/cache-bugs-with-screenshots")\n\n"
fi

# TestFlight (autonomous only — drift-control.txt = RUN means autopilot is active)
DRIFT_CONTROL=$(cat "$HOME/drift-control.txt" 2>/dev/null | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
if [ "$DRIFT_CONTROL" = "RUN" ] && ! $HAS_P0; then
    LAST_TF=$(cat "$STATE_DIR/last-testflight-publish" 2>/dev/null || echo "0")
    NOW=$(date +%s)
    ELAPSED=$(( NOW - LAST_TF ))
    if [ "$ELAPSED" -gt 10800 ]; then
        HOURS=$(( ELAPSED / 3600 ))
        CONTEXT="${CONTEXT}[2] TESTFLIGHT ${HOURS}h OVERDUE:\n"
        CONTEXT="${CONTEXT}1. Bump CURRENT_PROJECT_VERSION in project.yml (increment by 1)\n"
        CONTEXT="${CONTEXT}2. xcodegen generate\n"
        CONTEXT="${CONTEXT}3. git add project.yml Drift.xcodeproj && git commit -m 'chore: TestFlight build' && git push\n"
        CONTEXT="${CONTEXT}4. The testflight-check hook will inject archive+upload steps on the commit.\n\n"
    fi

    # Check if releases.json is out of date (published but not logged)
    BUILD_NUM=$(grep 'CURRENT_PROJECT_VERSION' "$HOME/workspace/Drift/project.yml" 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "0")
    LATEST_RELEASE=$(python3 -c "import json; d=json.load(open('$HOME/workspace/Drift/command-center/releases.json')); print(d[-1].get('build',0) if d else 0)" 2>/dev/null || echo "0")
    if [ "$BUILD_NUM" != "$LATEST_RELEASE" ] && [ "$BUILD_NUM" -gt "$LATEST_RELEASE" ] 2>/dev/null; then
        CONTEXT="${CONTEXT}RELEASES.JSON OUTDATED: build $BUILD_NUM published but releases.json shows build $LATEST_RELEASE. Update releases.json with the latest build info.\n\n"
    fi
fi

# === SENIOR ONLY (Opus) ===

if [ "$MODEL" = "opus" ]; then
    # Design doc PRs needing reply
    if [ -s "$STATE_DIR/cache-design-reviews" ]; then
        CONTEXT="${CONTEXT}[3] DESIGN DOC PRs — reply to EACH comment individually:\n$(cat "$STATE_DIR/cache-design-reviews")\nUse gh api pulls/{PR}/comments/{ID}/replies. Then revise doc.\n\n"
    fi

    # Pending design docs (no doc written yet)
    if [ -s "$STATE_DIR/cache-pending-designs" ]; then
        CONTEXT="${CONTEXT}DESIGN DOCS AWAITING PE:\n$(cat "$STATE_DIR/cache-pending-designs")\nCreate branch, write doc, create PR, add doc-ready label.\n\n"
    fi

    # Design docs awaiting approval — DO NOT IMPLEMENT
    if [ -s "$STATE_DIR/cache-awaiting-approval" ]; then
        CONTEXT="${CONTEXT}DESIGN DOCS AWAITING HUMAN APPROVAL — DO NOT IMPLEMENT:\n$(cat "$STATE_DIR/cache-awaiting-approval")\nOnly reply to PR comments and revise. Do NOT write code for these until human adds 'approved' label.\n\n"
    fi

    # Admin feedback unreplied
    if [ -s "$STATE_DIR/cache-admin-feedback" ]; then
        CONTEXT="${CONTEXT}[5] ADMIN FEEDBACK — reply to every comment:\n$(cat "$STATE_DIR/cache-admin-feedback")\n\n"
    fi

    # P0 feature requests without sprint tasks
    if [ -s "$STATE_DIR/cache-p0-features" ]; then
        CONTEXT="${CONTEXT}P0 FEATURE REQUESTS — create sprint-task:\n$(cat "$STATE_DIR/cache-p0-features")\n\n"
    fi

    # Approved design docs needing implementation tasks (approved but NOT yet implementing)
    if [ -s "$STATE_DIR/cache-approved-designs" ]; then
        CONTEXT="${CONTEXT}[4] APPROVED DESIGNS — create implementation tasks FIRST:\n$(cat "$STATE_DIR/cache-approved-designs")\n1. Create sprint-task Issues with label design-impl-{N}\n2. Add implementing label: gh issue edit {N} --add-label implementing\n3. Merge the design PR\n4. Then pick up implementation tasks one by one\n\n"
    fi
fi

# === PLANNING ONLY ===

if [ "$SESSION_TYPE" = "planning" ]; then
    CONTEXT="${CONTEXT}PLANNING DELIVERABLES (session BLOCKED from exiting until complete):\n"
    CONTEXT="${CONTEXT}1. Read + reply to ALL admin feedback on report PRs\n"
    CONTEXT="${CONTEXT}2. Write product review (MUST use branch + PR): git checkout -b review/cycle-{N}, write review-cycle-{N}.md using REVIEW-TEMPLATE.md, commit, push, gh pr create --label report, gh pr merge --squash --delete-branch, git checkout main && git pull\n"
    CONTEXT="${CONTEXT}3. Create 8-12 sprint-task Issues (add SENIOR only for complex tasks)\n"
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
