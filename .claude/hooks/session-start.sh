#!/bin/bash
# Hook: SessionStart
# Injects cycle state, product focus, design docs, report feedback.
# Uses 5-min cache to reduce API calls on rapid restarts.

COUNTER_FILE="$HOME/drift-state/cycle-counter"
LAST_REVIEW_FILE="$HOME/drift-state/last-review-cycle"
CACHE_DIR="$HOME/drift-state"

# Cache helper — only query API if cache older than 5 min
cached_query() {
  local CACHE_FILE="$1"
  shift
  local TTL=300
  local NOW=$(date +%s)
  local MOD=$(stat -f %m "$CACHE_FILE" 2>/dev/null || echo "0")
  if (( NOW - MOD < TTL )) && [ -s "$CACHE_FILE" ]; then
    cat "$CACHE_FILE"
  else
    eval "$@" > "$CACHE_FILE" 2>/dev/null || true
    cat "$CACHE_FILE"
  fi
}

# Reset stale session type — the watchdog writes this just before launching Claude (<10s).
# If it's older than 2 minutes it's leftover from a previous autonomous session; human
# sessions should not inherit it and get blocked on planning deliverables.
SESSION_TYPE_FILE="$HOME/drift-state/cache-session-type"
if [ -f "$SESSION_TYPE_FILE" ]; then
  NOW=$(date +%s)
  MOD=$(stat -f %m "$SESSION_TYPE_FILE" 2>/dev/null || echo "0")
  if (( NOW - MOD > 120 )); then
    echo "human" > "$SESSION_TYPE_FILE"
  fi
fi

COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
LAST_REVIEW=$(cat "$LAST_REVIEW_FILE" 2>/dev/null || echo "0")
NEXT_REVIEW=$((LAST_REVIEW + 10))

echo "=== Drift Loop State ==="
echo "Cycle count: $COUNT"
echo "Last product review: cycle $LAST_REVIEW"
echo "Next product review due: cycle $NEXT_REVIEW"
echo "Read Docs/roadmap.md first to understand product direction."

# Sprint service status (shows queue + in-progress at session start)
SPRINT_STATUS=$("${CLAUDE_PROJECT_DIR:-.}/scripts/sprint-service.sh" status 2>/dev/null || echo "Sprint service not initialized")
echo ""
echo "=== Sprint Queue ==="
echo "$SPRINT_STATUS"
SESSION_TYPE=$(cat "$HOME/drift-state/cache-session-type" 2>/dev/null || echo "junior")
NEXT_TASK=$("${CLAUDE_PROJECT_DIR:-.}/scripts/sprint-service.sh" next --"${SESSION_TYPE}" 2>/dev/null || echo "none")
echo "Your next task (${SESSION_TYPE}): $NEXT_TASK"
echo "Commands: scripts/sprint-service.sh claim <N> | done <N> <commit> | unclaim <N>"
echo "Design: scripts/design-service.sh summary"

# Surface pending design-doc issues (cached)
DESIGN_DOCS=$(cached_query "$CACHE_DIR/cache-design-docs" \
  gh issue list --state open --label design-doc --json number,title --jq "'.[] | \"#\\(.number) \\(.title)\"'")
if [ -n "$DESIGN_DOCS" ]; then
  DESIGN_COUNT=$(echo "$DESIGN_DOCS" | wc -l | tr -d ' ')
  echo ""
  echo "PENDING DESIGN DOCS ($DESIGN_COUNT):"
  echo "$DESIGN_DOCS"
  echo "Senior: create branch, write doc, create PR with --label design-doc, then add doc-ready label to the issue."
fi

# Surface product focus (cached)
FOCUS=$(cached_query "$CACHE_DIR/cache-product-focus" \
  gh issue list --state open --label product-focus --json body --jq "'.[0].body // empty'" | head -1)
if [ -n "$FOCUS" ]; then
  echo ""
  echo "PRODUCT FOCUS: $FOCUS"
  echo "Bias work toward this focus. P0 bugs, feature requests, and design docs are still valid."
fi

# Surface unreplied admin comments on report PRs (cached)
UNREPLIED=$(cached_query "$CACHE_DIR/cache-report-comments" \
  gh pr list --label report --state all --json number,title,comments --jq "'.[] | select(.comments > 0) | \"#\\(.number) \\(.title) (\\(.comments) comments)\"'" | head -5)
if [ -n "$UNREPLIED" ]; then
  echo ""
  echo "REPORT PRs WITH COMMENTS (check for unreplied admin feedback):"
  echo "$UNREPLIED"
  echo "Read the full report, then reply to every admin comment."
fi

SESSION_TYPE=$(cat "$HOME/drift-state/cache-session-type" 2>/dev/null || echo "junior")

if [[ "$SESSION_TYPE" == "senior" ]]; then
  # Design service summary
  DESIGN_SUMMARY=$("${CLAUDE_PROJECT_DIR:-.}/scripts/design-service.sh" summary 2>/dev/null || echo "")
  if [ -n "$DESIGN_SUMMARY" ]; then
    echo ""
    echo "=== Design Docs ==="
    echo "$DESIGN_SUMMARY"
  fi

  # Bugs needing investigation plan
  BUGS_UNPLANNED=$("${CLAUDE_PROJECT_DIR:-.}/scripts/issue-service.sh" bugs-needing-plan 2>/dev/null || echo "")
  if [ -n "$BUGS_UNPLANNED" ] && [ "$BUGS_UNPLANNED" != "none" ]; then
    echo ""
    echo "BUGS NEEDING PLAN (investigate + post-plan before fixing):"
    echo "$BUGS_UNPLANNED"
  fi
fi

if [[ "$SESSION_TYPE" == "planning" ]]; then
  PLAN_ISSUE=$(cat "$HOME/drift-state/planning-issue" 2>/dev/null || echo "")
  if [[ -n "$PLAN_ISSUE" ]]; then
    REMAINING=$("${CLAUDE_PROJECT_DIR:-.}/scripts/planning-service.sh" remaining 2>/dev/null || echo "")
    if [[ -n "$REMAINING" ]]; then
      echo ""
      echo "PLANNING RESUME — steps still needed:"
      echo "$REMAINING"
      echo "Start from the first unchecked step. Completed steps are already done."
    else
      echo ""
      echo "PLANNING: All steps checked. Verify and close the planning issue."
    fi
  fi

  # Show pending process feedback count
  FEEDBACK_LOG="$HOME/drift-state/process-feedback.log"
  if [ -f "$FEEDBACK_LOG" ] && [ -s "$FEEDBACK_LOG" ]; then
    FEEDBACK_COUNT=$(wc -l < "$FEEDBACK_LOG" | tr -d ' ')
    echo ""
    echo "PROCESS FEEDBACK: $FEEDBACK_COUNT session hiccup(s) pending review."
    echo "Run: scripts/issue-service.sh drain-feedback — then create infra-improvement issues for systemic ones."
  fi
fi

echo "========================"

# ── Autonomous session init (watchdog-managed sessions only) ──────────────────
DRIFT_CONTROL=$(cat "$HOME/drift-control.txt" 2>/dev/null | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
WORK_DIR="${CLAUDE_PROJECT_DIR:-.}"

if [[ "$DRIFT_CONTROL" == "RUN" ]]; then
    # Reset session task counter (sprint-service enforces 5-task limit via this)
    "$WORK_DIR/scripts/sprint-service.sh" start-session 2>/dev/null || true

    # Create + claim overhead tracking issue (session bookkeeping — not an impl task)
    SESSION_TYPE=$(cat "$HOME/drift-state/cache-session-type" 2>/dev/null || echo "junior")
    OVERHEAD_N=$(gh issue create \
      --label overhead \
      --title "Session $SESSION_TYPE — $(date '+%Y-%m-%d %H:%M') overhead" \
      --body "Overhead: session setup, bug investigations, design review, context gathering" \
      --json number --jq '.number' 2>/dev/null || echo "")
    if [[ -n "$OVERHEAD_N" ]]; then
        echo "$OVERHEAD_N" > "$HOME/drift-state/current-overhead-issue"
        "$WORK_DIR/scripts/sprint-service.sh" claim "$OVERHEAD_N" 2>/dev/null || true
        echo ""
        echo "=== Session Init ==="
        echo "Overhead issue #$OVERHEAD_N created and claimed (close at session end)."
        echo "Task budget: up to 5 implementation tasks (sprint-service tracks automatically)."
    fi

    # Show last session summary so each session knows where to pick up
    if [[ -f "$HOME/drift-state/last-session-summary.md" ]]; then
        echo ""
        echo "=== Last Session ==="
        cat "$HOME/drift-state/last-session-summary.md"
        echo "===================="
    fi
fi

exit 0
