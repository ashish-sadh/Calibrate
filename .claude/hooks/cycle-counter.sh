#!/bin/bash
# Hook: PostToolUse on Bash(git commit *)
# Tracks cycle count. Every 20th commit: product review with PR + personas + feedback.

set -e

COUNTER_FILE="$HOME/drift-state/cycle-counter"
LAST_REVIEW_FILE="$HOME/drift-state/last-review-cycle"

COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

LAST_REVIEW=$(cat "$LAST_REVIEW_FILE" 2>/dev/null || echo "0")
SINCE_REVIEW=$((COUNT - LAST_REVIEW))

if [ "$SINCE_REVIEW" -ge 20 ]; then
  TODAY=$(date +%Y-%m-%d)

  cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "PRODUCT REVIEW REQUIRED (cycle $COUNT, last review at cycle $LAST_REVIEW). Pause feature work.\n\nMANDATORY STEPS:\n\n1. READ PERSONA FILES first:\n   - Docs/personas/product-designer.md\n   - Docs/personas/principal-engineer.md\n\n2. READ FEEDBACK from open report PRs:\n   - gh pr list --label report --state open\n   - For each open PR: gh pr view {number} --comments\n   - Note any feedback to incorporate\n\n3. READ OPEN ISSUES:\n   - gh issue list --state open\n\n4. PRODUCT DESIGNER persona (use knowledge from persona file):\n   - Read Docs/roadmap.md, Docs/state.md, git log --oneline -20\n   - Web search: what are Boostcamp, MyFitnessPal, Whoop, Strong, MacroFactor doing now?\n   - Write assessment: strengths, gaps, new ideas, proposed changes\n\n5. PRINCIPAL ENGINEER persona (use knowledge from persona file):\n   - Review proposals for sustainability and sequencing\n   - Triage open GitHub Issues: real bug? P0/P1/P2? Label accordingly\n   - Push back on scope creep, ground in current stack\n\n6. AGREE on direction → update Docs/roadmap.md\n\n7. GENERATE PRODUCT REVIEW PR:\n   git checkout -b review/cycle-$COUNT\n   Write Docs/reports/review-cycle-$COUNT.md with FULL discussion (what happened, designer assessment, engineer response, agreed direction, sprint plan for next 20 cycles, open questions, 'Comment on any line for feedback')\n   git add && git commit -m 'review: product review cycle $COUNT' && git push -u origin review/cycle-$COUNT\n   gh pr create --title 'Product Review — Cycle $COUNT ($TODAY)' --label report\n   git checkout main\n\n8. UPDATE PERSONA FILES: append 'What I learned this review' to each persona file\n\n9. MERGE old review PRs: gh pr list --label report --state open | merge old ones\n\n10. LOG to Docs/product-review-log.md\n\n11. echo $COUNT > ~/drift-state/last-review-cycle\n\n12. Resume the loop"
  }
}
ENDJSON
else
  NEXT_REVIEW=$((LAST_REVIEW + 20))
  echo "Cycle $COUNT. Next product review at cycle $NEXT_REVIEW."
fi

exit 0
