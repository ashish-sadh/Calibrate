#!/bin/bash
# Hook: PostToolUse on Bash(git commit *)
# Once per day (24h): injects exec report PR generation + wiki refresh.
# Only runs in autonomous mode (DRIFT_AUTONOMOUS=1).

set -e

# Only for autonomous sessions
if [ "${DRIFT_AUTONOMOUS:-0}" != "1" ]; then
  exit 0
fi

LAST_REPORT_FILE="$HOME/drift-state/last-report-time"
MIN_INTERVAL=86400  # 24 hours in seconds
REVIEWERS_FILE="$HOME/drift-state/reviewers.txt"

NOW=$(date +%s)
LAST_REPORT=$(cat "$LAST_REPORT_FILE" 2>/dev/null || echo "0")
ELAPSED=$((NOW - LAST_REPORT))

if [ "$ELAPSED" -lt "$MIN_INTERVAL" ]; then
  REMAINING=$(( (MIN_INTERVAL - ELAPSED) / 3600 ))
  echo "Exec report: ${REMAINING}h until next report."
  exit 0
fi

# Read reviewers
REVIEWERS=""
if [ -f "$REVIEWERS_FILE" ]; then
  while IFS= read -r user; do
    [ -n "$user" ] && REVIEWERS="${REVIEWERS} @${user}"
  done < "$REVIEWERS_FILE"
fi
[ -z "$REVIEWERS" ] && REVIEWERS="@ashish-sadh"

CYCLE_COUNT=$(cat "$HOME/drift-state/cycle-counter" 2>/dev/null || echo "?")
TODAY=$(date +%Y-%m-%d)

cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "DAILY EXEC REPORT REQUIRED (last report ${ELAPSED}s ago). Generate now.\n\n1. Gather metrics:\n   - Build number: grep CURRENT_PROJECT_VERSION project.yml\n   - Test count: grep -r 'func test' DriftTests/*.swift DriftTests/LLMEval/*.swift 2>/dev/null | wc -l\n   - Coverage: cat ~/drift-state/last-coverage-snapshot\n   - Food count: python3 -c \"import json; print(len(json.load(open('Drift/Resources/foods.json'))))\"\n   - Recent commits: git log --oneline --since='24 hours ago'\n   - Failing queries: grep '\\- \\[ \\]' Docs/failing-queries.md | head -5\n   - Working AI examples: grep '\\- \\[x\\]' Docs/ai-parity.md | head -5\n\n2. Create report branch and file:\n   git checkout -b report/exec-${TODAY}\n   Write Docs/reports/exec-${TODAY}.md with: What is Drift (3 sentences), Key Metrics table, AI Chat Working Examples (5), AI Chat Known Gaps (5), Strategic Direction (from roadmap.md current phase), Completed Today (highlights from git log), Investment Priorities (top 5 from roadmap Now items), 'Comment on any line for feedback.${REVIEWERS}'\n\n3. Open PR:\n   git add Docs/reports/exec-${TODAY}.md && git commit -m 'report: daily exec report ${TODAY}' && git push -u origin report/exec-${TODAY}\n   gh pr create --title 'Exec Report — ${TODAY}' --label report --body 'Daily exec report. Comment on any line for strategic feedback.'\n   git checkout main\n\n4. Check wiki staleness — if Drift.wiki exists and any page >3 days old, refresh from current docs.\n\n5. Merge old exec report PRs: gh pr list --label report --state open | grep exec | merge old ones.\n\n6. echo \$(date +%s) > ~/drift-state/last-report-time\n\nDo this NOW before continuing feature work."
  }
}
ENDJSON

exit 0
