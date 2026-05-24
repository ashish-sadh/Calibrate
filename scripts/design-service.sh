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
#   in-review             — design-doc PRs with unanswered comments (issue + inline + review)
#   address-pr <PR>       — dump every comment surface on a PR + senior reply/revise protocol
#   awaiting-approval     — doc-ready issues without approved (human reviewing, do NOT touch)
#   approved-not-started  — approved issues without implementing label (create impl tasks now)
#   create-impl-tasks <N> — create sprint-task issues, add implementing label, merge design PR
#   check-complete <N>    — exit 0 if all design-impl-{N} tasks are closed
#   summary               — show all design doc issues and their states

set -euo pipefail

REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || echo "ashish-sadh/Drift")
WORK_DIR="/Users/ashishsadh/workspace/Drift"

cmd_pending() {
    # Two failure modes the workflow can be in:
    #   PENDING — issue filed, no design/{N}-* branch exists yet. Real work to do.
    #   ORPHAN  — design/{N}-* branch exists (often with the doc committed), but
    #             no PR was opened and doc-ready was never flipped. Single-point-
    #             failure recovery; #662 sat orphaned for 5 days in 2026-05.
    # The script trusts doc-ready as the workflow signal, so an orphan looks
    # identical to "needs doc written" without scanning git refs.
    local RAW
    RAW=$(gh issue list --state open --label design-doc --json number,title,labels \
        --jq '[.[] | select(.labels | map(.name) | index("doc-ready") | not) | select(.labels | map(.name) | index("blocked") | not)] | .[] | "\(.number)|\(.title)"' \
        2>/dev/null || true)
    if [ -z "$RAW" ]; then
        echo "none"
        return
    fi

    # One ls-remote covers all design/* branches; cheaper than per-issue calls.
    local BRANCHES
    BRANCHES=$(git ls-remote --heads origin 'refs/heads/design/*' 2>/dev/null \
        | awk '{print $2}' | sed 's|refs/heads/||')

    local PENDING="" ORPHAN=""
    while IFS='|' read -r N TITLE; do
        [ -z "$N" ] && continue
        # Match design/{N}- or design/{N}/ (exact issue number boundary —
        # otherwise design/6620 would falsely match issue #662).
        local BRANCH
        # `|| true` guards against grep-no-match (exit 1) propagating under
        # `set -euo pipefail` and killing the script.
        BRANCH=$(echo "$BRANCHES" | grep -E "^design/${N}(-|/|$)" | head -1 || true)
        if [ -n "$BRANCH" ]; then
            ORPHAN+="#$N $TITLE — orphan branch: $BRANCH"$'\n'
        else
            PENDING+="#$N $TITLE"$'\n'
        fi
    done <<< "$RAW"

    if [ -n "$PENDING" ]; then
        echo "PENDING (write doc + open PR + flip doc-ready):"
        printf "%s" "$PENDING"
    fi
    if [ -n "$ORPHAN" ]; then
        [ -n "$PENDING" ] && echo ""
        echo "RECOVERY (design branch exists, no PR — verify doc, open PR, flip doc-ready):"
        printf "%s" "$ORPHAN"
        echo ""
        echo "Action: git fetch origin <branch> && gh pr create --base main --head <branch> --label design-doc -t '<title>' && gh issue edit <N> --add-label doc-ready"
    fi
    if [ -z "$PENDING" ] && [ -n "$ORPHAN" ]; then
        :  # ORPHAN block already printed its action
    elif [ -n "$PENDING" ]; then
        echo ""
        echo "Action (PENDING): create branch design/{N}-name, write doc, create PR with --label design-doc, then: gh issue edit {N} --add-label doc-ready"
    fi
}

cmd_in_review() {
    # Three distinct comment surfaces on a PR:
    #   issue-level   /issues/{N}/comments
    #   inline review /pulls/{N}/comments  (file:line-tied)
    #   review body   /pulls/{N}/reviews   (top-level body when "Submit review")
    # `gh pr list --json` exposes only `.comments` (issue-level array). The
    # previous version asked for `reviewComments` which is not a valid field;
    # the whole query errored and the script silently reported "none". PR
    # #582 sat with a review summary + 2 inline comments invisible to senior
    # sessions for 2 days. Fix: query each surface separately per PR.
    local PRS
    PRS=$(gh pr list --label design-doc --state open --json number,title,comments \
        --jq '.[] | "\(.number)|\(.comments | length)|\(.title)"' 2>/dev/null || true)
    [ -z "$PRS" ] && { echo "none"; return; }

    local RESULT=""
    while IFS='|' read -r N IC TITLE; do
        [ -z "$N" ] && continue
        local RC RVB
        RC=$(gh api "repos/$REPO/pulls/$N/comments" --jq 'length' 2>/dev/null || echo "0")
        RVB=$(gh api "repos/$REPO/pulls/$N/reviews" \
            --jq '[.[] | select(.body != "" and .body != null)] | length' 2>/dev/null || echo "0")
        local TOTAL=$((IC + RC + RVB))
        if [ "$TOTAL" -gt 0 ]; then
            RESULT+="#$N $TITLE ($IC issue, $RC inline, $RVB review)"$'\n'
        fi
    done <<< "$PRS"

    if [ -z "$RESULT" ]; then
        echo "none"
    else
        printf "%s" "$RESULT"
        echo ""
        echo "Action: scripts/design-service.sh address-pr <PR>  — dumps every comment surface and walks the reply+revise+push flow."
        echo "Reply (issue-level): gh pr comment <PR> --body 'Addressed: ...'"
        echo "Reply (inline):      gh api repos/$REPO/pulls/<PR>/comments/<COMMENT_ID>/replies -f body='Addressed: ...'"
    fi
}

cmd_address_pr() {
    local PR="$1"
    if [ -z "$PR" ]; then
        echo "Usage: design-service.sh address-pr <PR-number>" >&2; exit 1
    fi

    local BRANCH
    BRANCH=$(gh pr view "$PR" --json headRefName --jq '.headRefName' 2>/dev/null)
    if [ -z "$BRANCH" ]; then
        echo "PR #$PR not found" >&2; exit 1
    fi

    echo "=== PR #$PR (branch: $BRANCH) ==="
    echo ""
    echo "--- Issue-level comments (/issues/$PR/comments) ---"
    gh api "repos/$REPO/issues/$PR/comments" \
        --jq '.[] | "[id=\(.id)] @\(.user.login) \(.created_at):\n\(.body)\n"' 2>/dev/null \
        || echo "(none)"
    echo ""
    echo "--- Review summaries (/pulls/$PR/reviews — body only) ---"
    gh api "repos/$REPO/pulls/$PR/reviews" \
        --jq '.[] | select(.body != "" and .body != null) | "[review_id=\(.id)] @\(.user.login) [\(.state)] \(.submitted_at):\n\(.body)\n"' 2>/dev/null \
        || echo "(none)"
    echo ""
    echo "--- Inline review comments (/pulls/$PR/comments) ---"
    gh api "repos/$REPO/pulls/$PR/comments" \
        --jq '.[] | "[id=\(.id)] @\(.user.login) \(.path):\(.line // .original_line) \(.created_at):\n\(.body)\n"' 2>/dev/null \
        || echo "(none)"
    echo ""
    echo "=== Senior protocol ==="
    cat <<EOF
1. Reply to each comment (don't drop any):
   gh pr comment $PR --body 'Addressed: ...'                                    # issue-level
   gh api repos/$REPO/pulls/$PR/comments/<COMMENT_ID>/replies -f body='...'     # inline thread
2. If the doc needs revision (most reviews do):
   git fetch origin $BRANCH && git checkout $BRANCH
   # edit Docs/designs/...md
   git commit -- Docs/designs/...md -m "docs(design): address review on PR #$PR"
   git push
   git checkout main
3. ensure-clean-state.sh requires HEAD on main at session end — step 2's final
   checkout matters. If you skip the revise step (replies were enough), still
   stay on main; no checkout needed.
EOF
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
    # Find + auto-merge the design PR (instead of just printing the command —
    # we observed PRs sitting OPEN for days because no session actually ran
    # the merge step. #574 PR #576, #665 PR #670 both stale until 2026-05-12).
    echo "Attempting to merge design PR..."
    DESIGN_PR=$(gh pr list --state open --json number,title,labels \
        --jq "[.[] | select(.labels | map(.name) | index(\"design-doc\")) | select(.title | test(\"$DESIGN_NUM\"))] | .[0].number" 2>/dev/null)
    if [ -n "$DESIGN_PR" ] && [ "$DESIGN_PR" != "null" ]; then
        echo "  Found PR #$DESIGN_PR — merging…"
        if gh pr merge "$DESIGN_PR" --squash --delete-branch 2>&1 | tail -5; then
            git checkout main 2>/dev/null && git pull --ff-only origin main 2>/dev/null
            echo "  Design PR #$DESIGN_PR merged."
        else
            echo "  WARN: auto-merge failed (likely merge conflicts). Resolve locally:"
            echo "    gh pr checkout $DESIGN_PR && git fetch origin main && git merge origin/main"
            echo "  Or land the doc directly to main as a fresh commit + close PR as redundant."
        fi
    else
        echo "  No open design-doc PR found for #$DESIGN_NUM — doc may already be in main."
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
    local IN_REVIEW_PRS IN_REVIEW=""
    IN_REVIEW_PRS=$(gh pr list --label design-doc --state open --json number,title,comments \
        --jq '.[] | "\(.number)|\(.comments | length)|\(.title)"' 2>/dev/null || true)
    while IFS='|' read -r N IC TITLE; do
        [ -z "$N" ] && continue
        local RC RVB
        RC=$(gh api "repos/$REPO/pulls/$N/comments" --jq 'length' 2>/dev/null || echo "0")
        RVB=$(gh api "repos/$REPO/pulls/$N/reviews" \
            --jq '[.[] | select(.body != "" and .body != null)] | length' 2>/dev/null || echo "0")
        local TOTAL=$((IC + RC + RVB))
        [ "$TOTAL" -gt 0 ] && IN_REVIEW+="  PR #$N $TITLE ($IC issue, $RC inline, $RVB review)"$'\n'
    done <<< "$IN_REVIEW_PRS"
    [ -n "$IN_REVIEW" ] && printf "%s" "$IN_REVIEW" || echo "  none"
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
    address-pr)           cmd_address_pr "${1:-}" ;;
    awaiting-approval)    cmd_awaiting_approval ;;
    approved-not-started) cmd_approved_not_started ;;
    create-impl-tasks)    cmd_create_impl_tasks "${1:-}" ;;
    check-complete)       cmd_check_complete "${1:-}" ;;
    summary)              cmd_summary ;;
    *)
        echo "Unknown command: $CMD" >&2
        echo "Commands: pending, in-review, address-pr <PR>, awaiting-approval, approved-not-started, create-impl-tasks, check-complete, summary" >&2
        exit 1
        ;;
esac
