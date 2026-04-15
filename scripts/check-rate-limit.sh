#!/bin/bash
# Check GitHub API rate limits. Called by watchdog before starting sessions.
# Exits 0 with JSON output. Sets RATE_LOW=1 if remaining < 500.

RATE=$(gh api rate_limit --jq '{
  remaining: .resources.core.remaining,
  limit: .resources.core.limit,
  used: .resources.core.used,
  reset: (.resources.core.reset | todate)
}' 2>/dev/null || echo '{"remaining":5000,"limit":5000,"used":0,"reset":"unknown"}')

REMAINING=$(echo "$RATE" | python3 -c "import sys,json; print(json.load(sys.stdin)['remaining'])" 2>/dev/null || echo "5000")

if [ "$REMAINING" -lt 200 ]; then
    echo "CRITICAL: GitHub API rate limit very low: $REMAINING remaining. Delaying 5 min."
    exit 2
elif [ "$REMAINING" -lt 500 ]; then
    echo "WARNING: GitHub API rate limit low: $REMAINING remaining."
    exit 1
else
    echo "OK: $REMAINING API calls remaining."
    exit 0
fi
