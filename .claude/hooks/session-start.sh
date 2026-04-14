#!/bin/bash
# Hook: SessionStart
# Injects cycle state and roadmap reminder on session startup.

COUNTER_FILE="$HOME/drift-state/cycle-counter"
LAST_REVIEW_FILE="$HOME/drift-state/last-review-cycle"

COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
LAST_REVIEW=$(cat "$LAST_REVIEW_FILE" 2>/dev/null || echo "0")
NEXT_REVIEW=$((LAST_REVIEW + 10))

echo "=== Drift Loop State ==="
echo "Cycle count: $COUNT"
echo "Last product review: cycle $LAST_REVIEW"
echo "Next product review due: cycle $NEXT_REVIEW"
echo "Read Docs/roadmap.md first to understand product direction."
echo "REMINDER: Mark your target issue in-progress BEFORE starting work: gh issue edit {N} --add-label in-progress"
echo "========================"

exit 0
