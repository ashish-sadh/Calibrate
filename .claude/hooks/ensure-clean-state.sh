#!/bin/bash
# Hook: Stop
# Blocks session from ending if there are uncommitted changes or unpushed commits.
# Forces the model to commit and push before stopping.

set -e

cd "${CLAUDE_PROJECT_DIR:-.}"

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

if [ -n "$ISSUES" ]; then
  echo -e "BLOCKED: Cannot stop with dirty state.\n\n${ISSUES}Commit all changes and push before stopping." >&2
  exit 2
fi

exit 0
