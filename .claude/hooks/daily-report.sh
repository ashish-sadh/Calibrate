#!/bin/bash
# Hook: PostToolUse on Bash(git commit *)
# Once per day (24h): injects exec report PR generation.
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
    "additionalContext": "DAILY EXEC BRIEFING REQUIRED. Generate now.\n\nIMPORTANT: Write for leadership who have 30 seconds. Use user-visible language ('Users can now...'), not technical language ('Refactored DDD routing'). No commit hashes. No file names. Think product update, not engineering log.\n\n1. Gather data:\n   - Build number: grep CURRENT_PROJECT_VERSION project.yml\n   - Test count: grep -r 'func test' DriftTests/*.swift DriftTests/LLMEval/*.swift 2>/dev/null | wc -l\n   - Coverage: cat ~/drift-state/last-coverage-snapshot\n   - Food count: python3 -c \"import json; print(len(json.load(open('Drift/Resources/foods.json'))))\"\n   - Recent work: git log --oneline --since='24 hours ago'\n   - Roadmap: read Docs/roadmap.md current phase\n   - Risks: check Docs/sprint.md for blockers, Docs/failing-queries.md for gaps\n\n2. Create report branch:\n   git checkout -b report/exec-${TODAY}\n\n3. Write Docs/reports/exec-${TODAY}.md using this EXACT structure:\n\n# Drift Daily Briefing — ${TODAY}\n\n## Headline\n{ONE sentence — the most important thing. e.g. 'Voice input prototype is ready for testing' or 'Calorie tracking bug fixed — was showing 30% too low'}\n\n## Product Snapshot\nDrift is an AI-first health tracker — users type what they ate or did, AI handles logging, tracking, and insights. On-device, no cloud. Currently in closed beta on TestFlight.\n\n| | |\n|---|---|\n| Beta Build | {N} (shipped {date}) |\n| Test Suite | {N} tests, {coverage}% coverage |\n| AI Capabilities | {N} tools |\n| Food Database | {N} foods |\n\n## What Shipped This Period\n{3-5 bullets of USER-VISIBLE improvements. Not 'refactored X' — 'Users can now do Y'}\n\n## What's Working Well\n{2-3 things going right — momentum, quality, user feedback}\n\n## Risks & Blockers\n{1-3 things that need attention — be honest about red flags}\n\n## Focus for Next Period\n{Top 3 priorities with brief 'why' for each}\n\n## Cost\n| | |\n|---|---|\n| Model | Opus |\n| Sessions today | {run ./scripts/token-usage.sh --today to get data} |\n| Est. cost today | {from script output} |\n| Cost/cycle | {from script output} |\n\n## Decision Needed\n{Optional: specific decisions leadership should weigh in on. Omit if none.}\n\n---\nComment on any line for strategic feedback.${REVIEWERS}\n\n4. Open PR and merge immediately (so it shows on dashboard — humans can still comment on merged PRs):\n   git add Docs/reports/exec-${TODAY}.md && git commit -m 'report: daily briefing ${TODAY}' && git push -u origin report/exec-${TODAY}\n   gh pr create --title 'Daily Briefing — ${TODAY}' --label report --body 'Executive briefing. Comment on any line for strategic feedback.'\n   gh pr merge --squash --delete-branch\n   git checkout main && git pull\n\n6. echo \$(date +%s) > ~/drift-state/last-report-time\n\nDo this NOW."
  }
}
ENDJSON

exit 0
