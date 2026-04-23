#!/bin/bash
# Hook: PostToolUse on Edit/Write
# Runs the drift-control test harness after editing autopilot infrastructure files.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only fire for autopilot infrastructure files
case "$FILE_PATH" in
  */scripts/sprint-service.sh|\
  */scripts/self-improve-watchdog.sh|\
  */scripts/planning-service.sh|\
  */scripts/design-service.sh|\
  */scripts/issue-service.sh|\
  */scripts/test-drift-control.sh|\
  */.claude/hooks/ensure-clean-state.sh|\
  */program.md)
    ;;
  *)
    exit 0
    ;;
esac

WORK_DIR="/Users/ashishsadh/workspace/Drift"
RESULT=$(bash "$WORK_DIR/scripts/test-drift-control.sh" 2>&1)
EXIT_CODE=$?

PASSED=$(echo "$RESULT" | grep -oE 'Passed: [0-9]+' | grep -oE '[0-9]+' || echo "?")
FAILED=$(echo "$RESULT" | grep -oE 'Failed: [0-9]+' | grep -oE '[0-9]+' || echo "?")

if [ "$EXIT_CODE" -eq 0 ]; then
  cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "Drift Control tests: ${PASSED} passed, ${FAILED} failed ✓"
  }
}
ENDJSON
else
  FAILURES=$(echo "$RESULT" | grep "FAIL:" | head -20 | sed 's/"/\\"/g' | tr '\n' '|')
  cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "DRIFT CONTROL TESTS FAILING: ${PASSED} passed, ${FAILED} failed. Fix before committing. Failures: ${FAILURES}"
  }
}
ENDJSON
fi

exit 0
