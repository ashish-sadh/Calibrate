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

COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
LAST_REVIEW=$(cat "$LAST_REVIEW_FILE" 2>/dev/null || echo "0")
NEXT_REVIEW=$((LAST_REVIEW + 10))

echo "=== Drift Loop State ==="
echo "Cycle count: $COUNT"
echo "Last product review: cycle $LAST_REVIEW"
echo "Next product review due: cycle $NEXT_REVIEW"
echo "Read Docs/roadmap.md first to understand product direction."

# Surface pending design-doc issues (cached)
DESIGN_DOCS=$(cached_query "$CACHE_DIR/cache-design-docs" \
  gh issue list --state open --label design-doc --json number,title --jq "'.[] | \"#\\(.number) \\(.title)\"'")
if [ -n "$DESIGN_DOCS" ]; then
  DESIGN_COUNT=$(echo "$DESIGN_DOCS" | wc -l | tr -d ' ')
  echo ""
  echo "PENDING DESIGN DOCS ($DESIGN_COUNT):"
  echo "$DESIGN_DOCS"
  echo "Senior: create branch design/SHORT-NAME, write doc using Docs/designs/TEMPLATE.md, push, create PR with --label design-doc. Do NOT commit design docs to main."
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

echo "========================"

exit 0
