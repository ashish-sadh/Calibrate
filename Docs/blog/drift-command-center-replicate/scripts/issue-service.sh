#!/bin/bash
# Issue lifecycle service — plan-first workflow, bug investigation, needs-review gate
# Commands: post-plan <N> <body>, investigate-bug <N>, need-review <N>, bugs-needing-plan, ready-from-review

set -euo pipefail

STATE_DIR="$HOME/drift-state"
mkdir -p "$STATE_DIR"

cmd_post_plan() {
    local N="${1:-}"
    local BODY="${2:-}"
    if [ -z "$N" ]; then
        echo "Usage: issue-service.sh post-plan <N> <body>" >&2
        exit 1
    fi

    gh issue comment "$N" --body "## Plan

$BODY" 2>/dev/null || true
    gh issue edit "$N" --add-label plan-posted 2>/dev/null || true
    echo "Plan posted on #$N"
}

cmd_investigate_bug() {
    local N="${1:-}"
    if [ -z "$N" ]; then
        echo "Usage: issue-service.sh investigate-bug <N>" >&2
        exit 1
    fi

    # Read issue for context
    gh issue view "$N" --json title,body,labels 2>/dev/null || true

    # Post structured investigation comment
    gh issue comment "$N" --body "## Investigation

**Root cause:** [investigating — update this comment when identified]

**Affected area:** [files/components involved]

**Fix approach:** [what will change]

**Tests to add:** [what tests will verify the fix]

**Risk:** [low/medium/high — why]" 2>/dev/null || true

    gh issue edit "$N" --add-label plan-posted 2>/dev/null || true
    echo "Investigation posted on #$N — EDIT that comment with actual findings (don't post a new one)"
}

cmd_need_review() {
    local N="${1:-}"
    if [ -z "$N" ]; then
        echo "Usage: issue-service.sh need-review <N>" >&2
        exit 1
    fi

    # Admin-filed bugs already have sprint-task — skip approval gate
    local HAS_SPRINT
    HAS_SPRINT=$(gh issue view "$N" --json labels --jq '[.labels[].name] | index("sprint-task") != null' 2>/dev/null || echo "false")
    if [ "$HAS_SPRINT" = "true" ]; then
        echo "Issue #$N already has sprint-task — no review needed"
        return
    fi

    # Ensure needs-review label exists
    gh label list --json name --jq '.[].name' 2>/dev/null | grep -q "needs-review" || \
        gh label create "needs-review" --color "#e4e669" --description "Awaiting human review before proceeding" 2>/dev/null || true

    gh issue edit "$N" --add-label needs-review 2>/dev/null || true
    gh issue comment "$N" --body "Awaiting your review. Plan is posted above — comment with feedback or approve in Command Center to proceed." 2>/dev/null || true

    echo "Issue #$N marked needs-review"
}

cmd_bugs_needing_plan() {
    local RESULT
    RESULT=$(gh issue list --state open --label bug --json number,title,labels \
        --jq '[.[] | select(.labels | map(.name) | index("plan-posted") | not)] | .[] | "#\(.number) \(.title)"' \
        2>/dev/null || true)
    if [ -z "$RESULT" ]; then
        echo "none"
    else
        echo "$RESULT"
    fi
}

cmd_ready_from_review() {
    local RESULT
    RESULT=$(gh issue list --state open --label needs-review --json number,title \
        --jq '.[] | "#\(.number) \(.title)"' \
        2>/dev/null || true)
    if [ -z "$RESULT" ]; then
        echo "none"
    else
        echo "$RESULT"
    fi
}

FEEDBACK_LOG="$STATE_DIR/process-feedback.log"

cmd_log_feedback() {
    local SESSION_TYPE="${1:-unknown}"
    local TEXT="${2:-}"
    if [ -z "$TEXT" ]; then
        echo "Usage: issue-service.sh log-feedback <session-type> <text>" >&2
        exit 1
    fi
    local TS
    TS=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${TS} | ${SESSION_TYPE} | ${TEXT}" >> "$FEEDBACK_LOG" 2>/dev/null || true
    echo "Feedback logged"
}

cmd_drain_feedback() {
    if [ ! -f "$FEEDBACK_LOG" ] || [ ! -s "$FEEDBACK_LOG" ]; then
        echo "No process feedback pending."
        return 0
    fi
    local CONTENT
    CONTENT=$(cat "$FEEDBACK_LOG") || return 1
    echo "$CONTENT"
    : > "$FEEDBACK_LOG"  # truncate only after successful read
}

# ── Dispatch ──────────────────────────────────────────────────────────────────

CMD="${1:-}"
shift 2>/dev/null || true

case "$CMD" in
    post-plan)          cmd_post_plan "${1:-}" "${2:-}" ;;
    investigate-bug)    cmd_investigate_bug "${1:-}" ;;
    need-review)        cmd_need_review "${1:-}" ;;
    bugs-needing-plan)  cmd_bugs_needing_plan ;;
    ready-from-review)  cmd_ready_from_review ;;
    log-feedback)       cmd_log_feedback "${1:-}" "${2:-}" ;;
    drain-feedback)     cmd_drain_feedback ;;
    *)
        echo "Unknown command: $CMD" >&2
        echo "Commands: post-plan <N> <body>, investigate-bug <N>, need-review <N>, bugs-needing-plan, ready-from-review, log-feedback <type> <text>, drain-feedback" >&2
        exit 1
        ;;
esac
