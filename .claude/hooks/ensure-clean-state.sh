#!/bin/bash
# Hook: Stop
# Blocks session from ending if there are uncommitted changes or unpushed commits.
# Forces the model to commit and push before stopping.

set -e

cd "${CLAUDE_PROJECT_DIR:-.}"

# Skip dirty state check if autopilot is running (it owns the working directory)
if pgrep -f 'claude.*-p.*(execute|run.*autopilot|sprint)' > /dev/null 2>&1; then
  exit 0
fi

# Check for uncommitted changes (staged or unstaged)
DIRTY=$(git status --porcelain 2>/dev/null | grep -v '^??' | head -5)
UNTRACKED=$(git status --porcelain 2>/dev/null | grep '^??' | grep -v '.claude/' | head -5)

# Check for unpushed commits
UNPUSHED=$(git log --oneline @{upstream}..HEAD 2>/dev/null | head -5)

ISSUES=""

if [ -n "$DIRTY" ]; then
  ISSUES="${ISSUES}Uncommitted changes:\n${DIRTY}\n\n"
fi

if [ -n "$UNTRACKED" ]; then
  ISSUES="${ISSUES}Untracked files (outside .claude/):\n${UNTRACKED}\n\n"
fi

if [ -n "$UNPUSHED" ]; then
  ISSUES="${ISSUES}Unpushed commits:\n${UNPUSHED}\n\n"
fi

# Check if persona files were updated after a product review
CYCLE_COUNT=$(cat "$HOME/drift-state/cycle-counter" 2>/dev/null || echo "0")
LAST_REVIEW=$(cat "$HOME/drift-state/last-review-cycle" 2>/dev/null || echo "0")
if [ "$CYCLE_COUNT" -eq "$LAST_REVIEW" ] && [ "$CYCLE_COUNT" -gt 0 ]; then
  # A review just happened this cycle — check persona files were updated
  DESIGNER_FILE="${CLAUDE_PROJECT_DIR:-.}/Docs/personas/product-designer.md"
  ENGINEER_FILE="${CLAUDE_PROJECT_DIR:-.}/Docs/personas/principal-engineer.md"
  LAST_COMMIT_TIME=$(git log -1 --format=%ct 2>/dev/null || echo "0")

  for PFILE in "$DESIGNER_FILE" "$ENGINEER_FILE"; do
    if [ -f "$PFILE" ]; then
      PMOD=$(stat -f %m "$PFILE" 2>/dev/null || echo "0")
      if [ "$PMOD" -lt "$LAST_COMMIT_TIME" ]; then
        ISSUES="${ISSUES}Persona file not updated after product review: $(basename $PFILE)\n\n"
      fi
    fi
  done
fi

# Check if any dirty files are report files (need PR branch, not direct main commit)
REPORT_FILES=$(git status --porcelain 2>/dev/null | grep -v '^??' | grep 'Docs/reports/' | awk '{print $2}')

if [ -n "$REPORT_FILES" ] && [ -n "$ISSUES" ]; then
  # Extract report type/name for branch naming
  REPORT_NAME=$(echo "$REPORT_FILES" | head -1 | sed 's|Docs/reports/||;s|\.md||')
  if echo "$REPORT_NAME" | grep -q "^review-cycle"; then
    BRANCH="review/$(echo "$REPORT_NAME" | sed 's/^review-//')"
  elif echo "$REPORT_NAME" | grep -q "^exec-"; then
    BRANCH="report/$REPORT_NAME"
  else
    BRANCH="report/$REPORT_NAME"
  fi

  echo -e "BLOCKED: Cannot stop with dirty state.\n\n${ISSUES}" >&2
  echo -e "IMPORTANT: Report files detected in uncommitted changes ($REPORT_FILES)." >&2
  echo -e "You MUST create a PR branch for reports — do NOT commit them to main." >&2
  echo -e "Steps: git checkout -b $BRANCH && commit report + related files && git push -u origin $BRANCH && gh pr create --label report && git checkout main" >&2
  exit 2
fi

if [ -n "$ISSUES" ]; then
  echo -e "BLOCKED: Cannot stop with dirty state.\n\n${ISSUES}Commit all changes and push before stopping." >&2
  exit 2
fi

# Planning session validation — check deliverables before allowing exit
SESSION_TYPE=$(cat "$HOME/drift-state/cache-session-type" 2>/dev/null || echo "")
if [ "$SESSION_TYPE" = "planning" ]; then
  PLAN_ISSUES=""

  # Were sprint-task issues created in this session?
  TASK_COUNT=$(gh issue list --state open --label sprint-task --json number --jq 'length' 2>/dev/null || echo "0")
  if [ "$TASK_COUNT" -lt 4 ]; then
    PLAN_ISSUES="${PLAN_ISSUES}Only $TASK_COUNT sprint-task issues open (target 8-12). Create more before stopping.\n\n"
  fi

  # Was a product review report committed recently?
  RECENT_REPORT=$(git log --oneline --since="2 hours ago" -- Docs/reports/review-*.md 2>/dev/null | head -1)
  if [ -z "$RECENT_REPORT" ]; then
    PLAN_ISSUES="${PLAN_ISSUES}No product review report committed this session. Write it before stopping.\n\n"
  fi

  # Were admin feedback comments replied to?
  if [ -s "$HOME/drift-state/cache-admin-feedback" ]; then
    PLAN_ISSUES="${PLAN_ISSUES}Admin feedback on report PRs still needs replies:\n$(cat "$HOME/drift-state/cache-admin-feedback")\nReply to every comment before stopping.\n\n"
  fi

  if [ -n "$PLAN_ISSUES" ]; then
    echo -e "BLOCKED: Planning session incomplete.\n\n${PLAN_ISSUES}" >&2
    exit 2
  fi
fi

exit 0
