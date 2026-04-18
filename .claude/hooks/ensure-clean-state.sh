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

# Check for in-progress issues that weren't closed (autonomous sessions only)
DRIFT_CONTROL=$(cat "$HOME/drift-control.txt" 2>/dev/null | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
if [ "$DRIFT_CONTROL" = "RUN" ]; then
  IN_PROGRESS=$(gh issue list --state open --label in-progress --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null || true)
  if [ -n "$IN_PROGRESS" ]; then
    echo -e "BLOCKED: Issues still in-progress. Verify work is done (build + tests pass), then close with comment:\n\n${IN_PROGRESS}\n\nFor each: gh issue close N --comment 'Done: {what was done} (commit {hash})'\nOr remove in-progress if unfinished: gh issue edit N --remove-label in-progress" >&2
    exit 2
  fi
fi

# Planning session validation — only for autonomous planning sessions (watchdog sets both)
SESSION_TYPE=$(cat "$HOME/drift-state/cache-session-type" 2>/dev/null || echo "")
if [ "$SESSION_TYPE" = "planning" ] && [ "$DRIFT_CONTROL" = "RUN" ]; then
  PLAN_ISSUES=""

  # Were sprint-task issues created in this session?
  TASK_COUNT=$(gh issue list --state open --label sprint-task --json number --jq 'length' 2>/dev/null || echo "0")
  if [ "$TASK_COUNT" -lt 4 ]; then
    PLAN_ISSUES="${PLAN_ISSUES}Only $TASK_COUNT sprint-task issues open (target 8-12). Create more before stopping.\n\n"
  fi

  # Was a product review report committed recently? Must be review-cycle-*.md format
  RECENT_REPORT=$(git log --oneline --since="2 hours ago" -- Docs/reports/review-cycle-*.md 2>/dev/null | head -1)
  if [ -z "$RECENT_REPORT" ]; then
    PLAN_ISSUES="${PLAN_ISSUES}No product review report committed this session. Write review-cycle-{N}.md using REVIEW-TEMPLATE.md.\n\n"
  else
    # Check report has required sections
    REPORT_FILE=$(git log --since="2 hours ago" --name-only --pretty=format: -- Docs/reports/review-cycle-*.md 2>/dev/null | head -1)
    if [ -n "$REPORT_FILE" ] && [ -f "$REPORT_FILE" ]; then
      MISSING=""
      grep -q "Product Designer Assessment" "$REPORT_FILE" || MISSING="${MISSING}Product Designer Assessment, "
      grep -q "Principal Engineer Assessment" "$REPORT_FILE" || MISSING="${MISSING}Principal Engineer Assessment, "
      grep -q "The Debate" "$REPORT_FILE" || MISSING="${MISSING}The Debate, "
      grep -q "Competitive Analysis" "$REPORT_FILE" || MISSING="${MISSING}Competitive Analysis, "
      if [ -n "$MISSING" ]; then
        PLAN_ISSUES="${PLAN_ISSUES}Product review missing required sections: ${MISSING%. }. Use REVIEW-TEMPLATE.md.\n\n"
      fi
    fi

    # Check if a report PR was created (not just committed to main)
    REPORT_NAME=$(basename "$REPORT_FILE" .md 2>/dev/null || echo "")
    if [ -n "$REPORT_NAME" ]; then
      REPORT_PR=$(gh pr list --label report --state all --json title,number --jq ".[] | select(.title | test(\"$REPORT_NAME\")) | .number" 2>/dev/null | head -1 || true)
      if [ -z "$REPORT_PR" ]; then
        PLAN_ISSUES="${PLAN_ISSUES}Product review committed but NO PR created. Human needs a PR to comment line-by-line.\nCreate branch, push, create PR with --label report, then merge: gh pr merge --squash --delete-branch\n\n"
      fi
    fi
  fi

  # Were admin feedback comments replied to?
  if [ -s "$HOME/drift-state/cache-admin-feedback" ]; then
    PLAN_ISSUES="${PLAN_ISSUES}Admin feedback on report PRs still needs replies:\n$(cat "$HOME/drift-state/cache-admin-feedback")\nReply to every comment before stopping.\n\n"
  fi

  # Were open feature requests reviewed and planned?
  FR_COUNT=$(gh issue list --state open --label feature-request --json number --jq 'length' 2>/dev/null || echo "0")
  if [ "$FR_COUNT" -gt 0 ]; then
    FR_LIST=$(gh issue list --state open --label feature-request --json number,title,labels --jq '.[] | "#\(.number) \(.title) [\(.labels | map(.name) | join(", "))]"' 2>/dev/null || true)
    PLAN_ISSUES="${PLAN_ISSUES}Open feature requests ($FR_COUNT) — review and plan these:\n${FR_LIST}\nP0: create sprint-task now. P1: include in sprint. Others: defer or close.\n\n"
  fi

  # Were approved design docs given implementation tasks?
  APPROVED_DESIGNS=$(gh issue list --state open --label design-doc --label approved --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null || true)
  if [ -n "$APPROVED_DESIGNS" ]; then
    PLAN_ISSUES="${PLAN_ISSUES}Approved design docs need implementation tasks:\n${APPROVED_DESIGNS}\nCreate sprint-task Issues with design-impl-{N} label for each.\n\n"
  fi

  if [ -n "$PLAN_ISSUES" ]; then
    echo -e "BLOCKED: Planning session incomplete.\n\n${PLAN_ISSUES}" >&2
    exit 2
  fi
fi

exit 0
