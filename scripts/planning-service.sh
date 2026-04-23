#!/bin/bash
# Planning checkpoint service — GitHub issue as source of truth
# Commands: checkpoint <step> | remaining | validate | issue-number | reset
#
# Steps: admin_replied, review_merged, tasks_created, personas_updated,
#        roadmap_updated, sprint_refreshed, feedback_drained,
#        bug_triage, design_docs_noted, feature_requests, state_assessed

set -euo pipefail

PLAN_ISSUE_FILE="$HOME/drift-state/planning-issue"
WORK_DIR="/Users/ashishsadh/workspace/Drift"

get_issue_number() {
    local N
    N=$(cat "$PLAN_ISSUE_FILE" 2>/dev/null | tr -d '[:space:]' || echo "")
    if [[ -z "$N" ]]; then
        echo "planning-service: no planning issue number found at $PLAN_ISSUE_FILE" >&2
        return 1
    fi
    echo "$N"
}

step_to_line() {
    local STEP="$1"
    case "$STEP" in
        admin_replied)       echo "Admin replies" ;;
        review_merged)       echo "Product review" ;;
        tasks_created)       echo "Sprint tasks" ;;
        personas_updated)    echo "Personas updated" ;;
        roadmap_updated)     echo "Roadmap updated" ;;
        sprint_refreshed)    echo "Sprint refreshed" ;;
        feedback_drained)    echo "Feedback drained" ;;
        bug_triage)          echo "Bug triage" ;;
        design_docs_noted)   echo "Design docs" ;;
        feature_requests)    echo "Feature requests" ;;
        state_assessed)      echo "State assessed" ;;
        *)
            echo "planning-service: unknown step '$STEP'" >&2
            return 1
            ;;
    esac
}

cmd_checkpoint() {
    local STEP="$1"
    local LINE_PREFIX
    LINE_PREFIX=$(step_to_line "$STEP") || exit 1

    local N
    N=$(get_issue_number) || exit 1

    local BODY
    BODY=$(gh issue view "$N" --json body --jq '.body' 2>/dev/null || echo "")
    if [[ -z "$BODY" ]]; then
        echo "planning-service: could not read issue #$N body" >&2
        exit 1
    fi

    # Replace "- [ ] <prefix>..." with "- [x] <prefix>..." for matching lines
    local UPDATED
    UPDATED=$(echo "$BODY" | sed "s/- \\[ \\] \\(${LINE_PREFIX}[^\\n]*\\)/- [x] \\1/")

    if [[ "$UPDATED" == "$BODY" ]]; then
        echo "planning-service: step '$STEP' line not found or already checked in issue #$N" >&2
        exit 1
    fi

    gh issue edit "$N" --body "$UPDATED" > /dev/null 2>&1 || true
    echo "planning-service: checkpoint '$STEP' marked done in issue #$N"
}

cmd_remaining() {
    local N
    N=$(get_issue_number) || exit 1

    local BODY
    BODY=$(gh issue view "$N" --json body --jq '.body' 2>/dev/null || echo "")
    if [[ -z "$BODY" ]]; then
        echo "planning-service: could not read issue #$N body" >&2
        exit 1
    fi

    local UNCHECKED
    UNCHECKED=$(echo "$BODY" | grep '^\- \[ \]' || true)
    echo "$UNCHECKED"
}

cmd_validate() {
    local N
    N=$(get_issue_number) || exit 1

    local BODY
    BODY=$(gh issue view "$N" --json body --jq '.body' 2>/dev/null || echo "")

    local FAILURES=""

    # review_merged — mechanical: check git log, but only if review is actually due.
    # report-service.sh review-due exits 0 when DUE, 1 when not due.
    # Skipping the check when not due avoids false-positive blocks on routine planning
    # sessions that legitimately don't need a review.
    if "$WORK_DIR/scripts/report-service.sh" review-due > /dev/null 2>&1; then
        # Review is due — require a recent review-cycle commit on main.
        # Note: capture to variable first — pipefail + grep -q causes SIGPIPE on git log
        local REVIEW_LOG
        REVIEW_LOG=$(git -C "$WORK_DIR" log main --oneline --since="7 hours ago" 2>/dev/null || true)
        if ! echo "$REVIEW_LOG" | grep -qE "review[-/]cycle"; then
            FAILURES="${FAILURES}review_merged: no review-cycle commit found on main in last 7 hours\n"
        fi
    fi

    # tasks_created — mechanical: check sprint-service count
    local TASK_COUNT
    TASK_COUNT=$("$WORK_DIR/scripts/sprint-service.sh" count --sprint 2>/dev/null || echo "0")
    if [[ "$TASK_COUNT" -lt 8 ]]; then
        FAILURES="${FAILURES}tasks_created: only $TASK_COUNT sprint-task issues open (need 8+)\n"
    fi

    # Remaining steps — self-reported via checklist. bug_triage,
    # design_docs_noted, feature_requests, state_assessed were previously
    # unchecked in the validation loop; the planner could close the issue
    # while leaving them blank. Now all nine self-reported steps block.
    for STEP in admin_replied personas_updated roadmap_updated sprint_refreshed feedback_drained bug_triage design_docs_noted feature_requests state_assessed; do
        local LINE_PREFIX
        LINE_PREFIX=$(step_to_line "$STEP")
        if echo "$BODY" | grep -q "^\- \[ \] ${LINE_PREFIX}"; then
            FAILURES="${FAILURES}${STEP}: not checked in planning issue #$N\n"
        fi
    done

    if [[ -n "$FAILURES" ]]; then
        echo -e "Planning validation failed:\n${FAILURES}" >&2
        exit 1
    fi

    echo "planning-service: all planning steps validated"
    exit 0
}

cmd_issue_number() {
    get_issue_number
}

cmd_reset() {
    local N
    N=$(get_issue_number) || exit 1

    local BODY
    BODY=$(gh issue view "$N" --json body --jq '.body' 2>/dev/null || echo "")

    # Replace all checked items back to unchecked
    local RESET
    RESET=$(echo "$BODY" | sed 's/- \[x\]/- [ ]/g')

    gh issue edit "$N" --body "$RESET" > /dev/null 2>&1 || true
    echo "planning-service: reset all checkboxes in issue #$N"
}

COMMAND="${1:-}"

case "$COMMAND" in
    checkpoint)
        if [[ -z "${2:-}" ]]; then
            echo "Usage: planning-service.sh checkpoint <step>" >&2
            exit 1
        fi
        cmd_checkpoint "$2"
        ;;
    remaining)
        cmd_remaining
        ;;
    validate)
        cmd_validate
        ;;
    issue-number)
        cmd_issue_number
        ;;
    reset)
        cmd_reset
        ;;
    *)
        echo "Usage: planning-service.sh <checkpoint <step>|remaining|validate|issue-number|reset>" >&2
        exit 1
        ;;
esac
