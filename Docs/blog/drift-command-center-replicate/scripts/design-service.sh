#!/bin/bash
# Design Service — manages the design-doc issue lifecycle for senior sessions.
# Provides deterministic, query-based commands so senior doesn't need to remember
# the lifecycle state — just call the right command and follow the output.
#
# Design doc lifecycle:
#   Issue filed (design-doc) → pending
#   Senior writes doc → doc-ready label added
#   Human reviews PR, comments → in-review
#   Human adds approved label → approved-not-started
#   Senior creates impl tasks → implementing
#   All design-impl-{N} tasks closed → close design issue
#
# Commands:
#   pending               — design-doc issues needing a doc written (no doc-ready)
#   in-review             — design-doc PRs with comments needing reply
#   awaiting-approval     — doc-ready issues without approved (human reviewing, do NOT touch)
#   approved-not-started  — approved issues without implementing label (create impl tasks now)
#   create-impl-tasks <N> — create sprint-task issues, add implementing label, merge design PR
#   check-complete <N>    — exit 0 if all design-impl-{N} tasks are closed
#   summary               — show all design doc issues and their states

set -euo pipefail

REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || echo "ashish-sadh/Drift")
WORK_DIR="/Users/ashishsadh/workspace/Drift"

cmd_pending() {
    local RESULT
    RESULT=$(gh issue list --state open --label design-doc --json number,title,labels \
        --jq '[.[] | select(.labels | map(.name) | index("doc-ready") | not)] | .[] | "#\(.number) \(.title)"' \
        2>/dev/null || true)
    if [ -z "$RESULT" ]; then
        echo "none"
    else
        echo "$RESULT"
        echo ""
        echo "Action: For each, create branch (design/{N}-name), write doc, create PR with --label design-doc, then: gh issue edit {N} --add-label doc-ready"
    fi
}

cmd_in_review() {
    # Find design-doc PRs with comments (general OR inline review comments)
    local RESULT
    RESULT=$(gh pr list --label design-doc --state open --json number,title,comments,reviewComments \
        --jq '.[] | select(.comments > 0 or .reviewComments > 0) | "#\(.number) \(.title) (\(.comments + .reviewComments) comments)"' \
        2>/dev/null || true)
    if [ -z "$RESULT" ]; then
        echo "none"
    else
        echo "$RESULT"
        echo ""
        echo "Action: For each PR — read ALL comments (general + inline review), reply individually, then revise doc and push."
        echo "Reply: gh api repos/$REPO/pulls/{PR}/comments/{ID}/replies -f body='Addressed: ...'"
    fi
}

cmd_awaiting_approval() {
    local RESULT
    RESULT=$(gh issue list --state open --label design-doc --label doc-ready --json number,title,labels \
        --jq '[.[] | select(.labels | map(.name) | index("approved") | not)] | .[] | "#\(.number) \(.title)"' \
        2>/dev/null || true)
    if [ -z "$RESULT" ]; then
        echo "none"
    else
        echo "$RESULT"
        echo ""
        echo "Status: Waiting on human to add 'approved' label. DO NOT implement these yet."
    fi
}

cmd_approved_not_started() {
    local RESULT
    RESULT=$(gh issue list --state open --label design-doc --label approved --json number,title,labels \
        --jq '[.[] | select(.labels | map(.name) | index("implementing") | not)] | .[] | "#\(.number) \(.title)"' \
        2>/dev/null || true)
    if [ -z "$RESULT" ]; then
        echo "none"
    else
        echo "$RESULT"
        echo ""
        echo "Action: Run: scripts/design-service.sh create-impl-tasks {N} for each"
    fi
}

cmd_create_impl_tasks() {
    local DESIGN_NUM="$1"
    if [ -z "$DESIGN_NUM" ]; then
        echo "Usage: design-service.sh create-impl-tasks <issue-number>" >&2
        exit 1
    fi

    # Read design issue
    local ISSUE_DATA
    ISSUE_DATA=$(gh issue view "$DESIGN_NUM" --json title,body,labels 2>/dev/null)
    local TITLE
    TITLE=$(echo "$ISSUE_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin)['title'])" 2>/dev/null)

    echo "Creating implementation tasks for design #$DESIGN_NUM: $TITLE"
    echo ""
    echo "You must create sprint-task issues manually based on the design doc content."
    echo "For each implementation task:"
    echo "  gh issue create --label sprint-task --label design-impl-$DESIGN_NUM \\"
    echo "    --title 'Impl: {task name} (design #$DESIGN_NUM)' \\"
    echo "    --body 'Goal: ...\nFiles: ...\nApproach: ...\nTests: ...\nAC: ...'"
    echo ""
    echo "After creating ALL implementation tasks:"
    echo "  gh issue edit $DESIGN_NUM --add-label implementing"
    echo ""
    echo "Then find and merge the design PR:"
    DESIGN_PR=$(gh pr list --label design-doc --state open --json number,title \
        --jq ".[] | select(.title | test(\"$DESIGN_NUM\")) | .number" 2>/dev/null | head -1 || true)
    if [ -n "$DESIGN_PR" ]; then
        echo "  gh pr merge $DESIGN_PR --squash --delete-branch && git checkout main && git pull"
    else
        echo "  (find the design PR: gh pr list --label design-doc --state open)"
    fi
    echo ""
    echo "Finally: scripts/sprint-service.sh refresh (picks up new impl tasks)"
}

cmd_check_complete() {
    local DESIGN_NUM="$1"
    if [ -z "$DESIGN_NUM" ]; then
        echo "Usage: design-service.sh check-complete <issue-number>" >&2
        exit 1
    fi

    local OPEN_IMPL
    OPEN_IMPL=$(gh issue list --state open --label "design-impl-$DESIGN_NUM" --json number --jq 'length' 2>/dev/null || echo "1")

    if [ "$OPEN_IMPL" -eq 0 ]; then
        echo "All implementation tasks for design #$DESIGN_NUM are closed."
        echo "Close the design issue:"
        echo "  gh issue close $DESIGN_NUM --comment 'All implementation tasks completed. Design fully shipped.'"
        exit 0
    else
        echo "$OPEN_IMPL implementation tasks still open for design #$DESIGN_NUM."
        gh issue list --state open --label "design-impl-$DESIGN_NUM" --json number,title \
            --jq '.[] | "  #\(.number) \(.title)"' 2>/dev/null || true
        exit 1
    fi
}

cmd_summary() {
    echo "=== Design Doc Issues ==="
    echo ""

    echo "PENDING (need doc written):"
    local PENDING
    PENDING=$(gh issue list --state open --label design-doc --json number,title,labels \
        --jq '[.[] | select(.labels | map(.name) | index("doc-ready") | not)] | .[] | "  #\(.number) \(.title)"' \
        2>/dev/null || true)
    [ -n "$PENDING" ] && echo "$PENDING" || echo "  none"
    echo ""

    echo "IN REVIEW (PR has comments to reply to):"
    local IN_REVIEW
    IN_REVIEW=$(gh pr list --label design-doc --state open --json number,title,comments,reviewComments \
        --jq '.[] | select(.comments > 0 or .reviewComments > 0) | "  PR #\(.number) \(.title) (\(.comments + .reviewComments) comments)"' \
        2>/dev/null || true)
    [ -n "$IN_REVIEW" ] && echo "$IN_REVIEW" || echo "  none"
    echo ""

    echo "AWAITING APPROVAL (human reviewing, do NOT implement):"
    local AWAITING
    AWAITING=$(gh issue list --state open --label design-doc --label doc-ready --json number,title,labels \
        --jq '[.[] | select(.labels | map(.name) | index("approved") | not)] | .[] | "  #\(.number) \(.title)"' \
        2>/dev/null || true)
    [ -n "$AWAITING" ] && echo "$AWAITING" || echo "  none"
    echo ""

    echo "APPROVED — NEEDS IMPL TASKS:"
    local APPROVED
    APPROVED=$(gh issue list --state open --label design-doc --label approved --json number,title,labels \
        --jq '[.[] | select(.labels | map(.name) | index("implementing") | not)] | .[] | "  #\(.number) \(.title)"' \
        2>/dev/null || true)
    [ -n "$APPROVED" ] && echo "$APPROVED" || echo "  none"
    echo ""

    echo "IMPLEMENTING (impl tasks in progress):"
    local IMPLEMENTING
    IMPLEMENTING=$(gh issue list --state open --label design-doc --label implementing --json number,title \
        --jq '.[] | "  #\(.number) \(.title)"' 2>/dev/null || true)
    [ -n "$IMPLEMENTING" ] && echo "$IMPLEMENTING" || echo "  none"
}

# ── Dispatch ──────────────────────────────────────────────────────────────────

CMD="${1:-summary}"
shift 2>/dev/null || true

case "$CMD" in
    pending)              cmd_pending ;;
    in-review)            cmd_in_review ;;
    awaiting-approval)    cmd_awaiting_approval ;;
    approved-not-started) cmd_approved_not_started ;;
    create-impl-tasks)    cmd_create_impl_tasks "${1:-}" ;;
    check-complete)       cmd_check_complete "${1:-}" ;;
    summary)              cmd_summary ;;
    *)
        echo "Unknown command: $CMD" >&2
        echo "Commands: pending, in-review, awaiting-approval, approved-not-started, create-impl-tasks, check-complete, summary" >&2
        exit 1
        ;;
esac
