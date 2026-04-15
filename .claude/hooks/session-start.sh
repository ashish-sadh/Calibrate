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

# Surface pending design-doc issues
DESIGN_DOCS=$(gh issue list --state open --label design-doc --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null || true)
if [ -n "$DESIGN_DOCS" ]; then
  DESIGN_COUNT=$(echo "$DESIGN_DOCS" | wc -l | tr -d ' ')
  echo ""
  echo "PENDING DESIGN DOCS ($DESIGN_COUNT):"
  echo "$DESIGN_DOCS"
  echo "Senior: write/revise these BEFORE sprint-tasks. Use Docs/designs/TEMPLATE.md."
fi

# Surface product focus
FOCUS=$(gh issue list --state open --label product-focus --json title --jq '.[0].title' 2>/dev/null || true)
if [ -n "$FOCUS" ]; then
  echo ""
  echo "PRODUCT FOCUS: $FOCUS"
  echo "Bias work toward this focus. P0 bugs, feature requests, and design docs are still valid."
fi

# Surface unreplied admin comments on report PRs
UNREPLIED=$(gh pr list --label report --state all --json number,title,comments --jq '
  .[] | select(.comments > 0) | "#\(.number) \(.title) (\(.comments) comments)"
' 2>/dev/null | head -5 || true)
if [ -n "$UNREPLIED" ]; then
  echo ""
  echo "REPORT PRs WITH COMMENTS (check for unreplied admin feedback):"
  echo "$UNREPLIED"
  echo "Read the full report, then reply to every admin comment."
fi

echo "========================"

exit 0
