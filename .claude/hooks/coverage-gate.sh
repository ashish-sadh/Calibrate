#!/bin/bash

# Silent for non-autonomous (human) sessions — these hooks are autopilot-only.
[[ "${DRIFT_AUTONOMOUS:-0}" != "1" ]] && exit 0
# Hook: PostToolUse on Bash(git commit *)
# Every 5th commit: runs coverage check. If coverage dropped or is below threshold,
# injects a strong message to prioritize writing tests that catch REAL bugs.

set -e

COUNTER_FILE="$HOME/drift-state/cycle-counter"
LAST_COVERAGE_FILE="$HOME/drift-state/last-coverage-snapshot"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")

# Only run every 5th commit
if [ $((COUNT % 5)) -ne 0 ]; then
  exit 0
fi

# Skip for planning sessions — they don't write code
SESSION_TYPE=$(cat "$HOME/drift-state/cache-session-type" 2>/dev/null || echo "junior")
if [[ "$SESSION_TYPE" == "planning" ]]; then
  exit 0
fi

cd "$PROJECT_DIR"

# Run tests with coverage (redirect all output to /tmp)
pkill -9 -f xcodebuild 2>/dev/null || true
sleep 2
rm -rf /tmp/DriftCoverage.xcresult
xcodebuild test -project Drift.xcodeproj -scheme Drift \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:DriftTests \
  -enableCodeCoverage YES \
  -resultBundlePath /tmp/DriftCoverage.xcresult \
  > /tmp/drift-coverage-test.log 2>&1 || true

# Get overall coverage percentage
OVERALL=$(xcrun xccov view --report /tmp/DriftCoverage.xcresult --only-targets 2>/dev/null | grep "Drift.app" | awk '{print $4}' | tr -d '%')

if [ -z "$OVERALL" ]; then
  echo "Coverage check skipped — could not generate report."
  exit 0
fi

# Read previous coverage
PREV_COVERAGE=$(cat "$LAST_COVERAGE_FILE" 2>/dev/null || echo "0")

# Save current
echo "$OVERALL" > "$LAST_COVERAGE_FILE"

# Run the detailed check to find failures
COVERAGE_REPORT=$(./scripts/coverage-check.sh --fail 2>&1 || true)
BELOW_THRESHOLD=$(echo "$COVERAGE_REPORT" | grep -c "❌\|⚠️" || true)

# Check if coverage dropped
DROPPED=false
if [ -n "$PREV_COVERAGE" ] && [ "$PREV_COVERAGE" != "0" ]; then
  if (( $(echo "$OVERALL < $PREV_COVERAGE" | bc -l) )); then
    DROPPED=true
  fi
fi

# Inject message if coverage dropped OR files are below threshold
if [ "$DROPPED" = true ] || [ "$BELOW_THRESHOLD" -gt 0 ]; then
  DROP_MSG=""
  if [ "$DROPPED" = true ]; then
    DROP_MSG="Coverage DROPPED from ${PREV_COVERAGE}% to ${OVERALL}%. "
  fi

  cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "COVERAGE ALERT (cycle $COUNT). ${DROP_MSG}${BELOW_THRESHOLD} file(s) below threshold.\n\nYour NEXT cycle must be writing tests. Not happy-path tests — tests that catch REAL bugs:\n\n1. Think like a user: what inputs would break this? What state transitions are untested?\n2. Test BOUNDARIES: unit conversions (kg/lb — this was broken and no test caught it), empty states, nil values, zero amounts, negative numbers\n3. Test ERROR PATHS: what happens when the DB save fails? When the API returns garbage? When the user enters emoji?\n4. Test STATE TRANSITIONS: multi-turn chat losing context, pendingMealName not being cleared, workout state leaking between sessions\n5. Test REAL SCENARIOS from git log — every recent bug fix should have a regression test\n\nCoverage report:\n${COVERAGE_REPORT}\n\nDo NOT continue feature work until you've written tests that would catch bugs like kg/lb conversion being silently broken."
  }
}
ENDJSON
else
  echo "Coverage check passed: ${OVERALL}% (prev: ${PREV_COVERAGE}%). ${BELOW_THRESHOLD} files below threshold."
fi

exit 0
