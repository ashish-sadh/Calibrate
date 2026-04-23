#!/bin/bash
# Report service — owns exec briefing and product review report lifecycle
# Commands: daily-due, review-due, start-exec, start-review <cycle>, finish, last-exec, last-review

set -euo pipefail

STATE_DIR="$HOME/drift-state"
mkdir -p "$STATE_DIR"

cmd_daily_due() {
    # exits 0 if exec report NOT yet filed (due), exits 1 if already done
    # Check 1: git log for report commit in last 24h
    if git log main --oneline --since="24 hours ago" 2>/dev/null | grep -qE "report.*exec-|exec-.*report|daily briefing|Daily Briefing"; then
        exit 1  # already done
    fi
    # Check 2: fallback — last-report-time file
    LAST=$(cat "$STATE_DIR/last-report-time" 2>/dev/null || echo "0")
    NOW=$(date +%s)
    if [ $(( NOW - LAST )) -lt 86400 ]; then
        exit 1  # already done (within 24h)
    fi
    exit 0  # report due
}

cmd_review_due() {
    # exits 0 if product review NOT yet done (due), exits 1 if done
    # Check 1: git log for review commit in last 6h
    if git log main --oneline --since="6 hours ago" 2>/dev/null | grep -qi "review-cycle"; then
        exit 1  # already done
    fi
    # Check 2: fallback — last-review-time file
    LAST=$(cat "$STATE_DIR/last-review-time" 2>/dev/null || echo "0")
    NOW=$(date +%s)
    if [ $(( NOW - LAST )) -lt 21600 ]; then
        exit 1  # already done (within 6h)
    fi
    exit 0  # review due
}

cmd_start_exec() {
    TODAY=$(date +%Y-%m-%d)
    BRANCH="report/exec-$TODAY"

    # Check if branch already exists on remote
    if git ls-remote --heads origin "$BRANCH" 2>/dev/null | grep -q "$BRANCH"; then
        echo "Branch already exists — checkout and continue:"
        echo "  git checkout $BRANCH"
    else
        echo "Create exec report branch:"
        echo "  git checkout -b $BRANCH"
    fi
    echo ""
    echo "Expected filename: Docs/reports/exec-$TODAY.md"
    echo "Template: Use Docs/reports/EXEC-TEMPLATE.md"
}

cmd_start_review() {
    local CYCLE="${1:-}"
    if [ -z "$CYCLE" ]; then
        CYCLE=$(cat "$STATE_DIR/cycle-counter" 2>/dev/null || echo "0")
    fi
    BRANCH="review/cycle-$CYCLE"

    # Check if branch already exists on remote
    if git ls-remote --heads origin "$BRANCH" 2>/dev/null | grep -q "$BRANCH"; then
        echo "Branch already exists — checkout and continue:"
        echo "  git checkout $BRANCH"
    else
        echo "Create review branch:"
        echo "  git checkout -b $BRANCH"
    fi
    echo ""
    echo "Expected filename: Docs/reports/review-cycle-$CYCLE.md"
    echo "Template: Use Docs/reports/REVIEW-TEMPLATE.md"
}

cmd_finish() {
    # Merge current branch and return to main
    CURRENT_BRANCH=$(git branch --show-current)

    # Self-heal: Command Center filters reviews/execs by label=report — a missing
    # label hides the PR from the UI. Enforce it here so a slip at `gh pr create`
    # time can't surface as an invisible report.
    if echo "$CURRENT_BRANCH" | grep -q "^review/cycle-\|^report/exec-\|^report/.*exec"; then
        PR_INFO=$(gh pr view --json number,labels 2>/dev/null || echo "")
        if [ -n "$PR_INFO" ]; then
            PR_NUM=$(echo "$PR_INFO" | jq -r '.number // empty')
            HAS_LABEL=$(echo "$PR_INFO" | jq -r '[.labels[].name] | index("report") != null')
            if [ -n "$PR_NUM" ] && [ "$HAS_LABEL" = "false" ]; then
                gh pr edit "$PR_NUM" --add-label report >/dev/null 2>&1 \
                    && echo "Added missing 'report' label to PR #$PR_NUM"
            fi
        fi
    fi

    gh pr merge --squash --delete-branch 2>/dev/null || true
    git checkout main && git pull

    # Record timestamp based on branch type
    NOW=$(date +%s)
    if echo "$CURRENT_BRANCH" | grep -q "^report/exec-\|^report/.*exec"; then
        echo "$NOW" > "$STATE_DIR/last-report-time"
        echo "Recorded exec report time"
    elif echo "$CURRENT_BRANCH" | grep -q "^review/cycle-"; then
        echo "$NOW" > "$STATE_DIR/last-review-time"
        echo "Recorded review time"
    fi
}

cmd_last_exec() {
    git log main --oneline 2>/dev/null | grep -iE "report.*exec-|exec-.*report|daily briefing|Daily Briefing" | head -1 || echo "No exec report found in git history"
}

cmd_last_review() {
    git log main --oneline 2>/dev/null | grep -i "review-cycle" | head -1 || echo "No review found in git history"
}

# ── Dispatch ──────────────────────────────────────────────────────────────────

CMD="${1:-}"
shift 2>/dev/null || true

case "$CMD" in
    daily-due)      cmd_daily_due ;;
    review-due)     cmd_review_due ;;
    start-exec)     cmd_start_exec ;;
    start-review)   cmd_start_review "${1:-}" ;;
    finish)         cmd_finish ;;
    last-exec)      cmd_last_exec ;;
    last-review)    cmd_last_review ;;
    *)
        echo "Unknown command: $CMD" >&2
        echo "Commands: daily-due, review-due, start-exec, start-review <cycle>, finish, last-exec, last-review" >&2
        exit 1
        ;;
esac
