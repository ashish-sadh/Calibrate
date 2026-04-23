#!/bin/bash
# Hook: PreToolUse on Bash
# Runs before xcodebuild archive. Ensures the app is healthy before TestFlight.
# Blocks the archive if any check fails.

set -e

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only gate archive commands
case "$COMMAND" in
  *"xcodebuild archive"*)
    ;;
  *)
    exit 0
    ;;
esac

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
cd "$PROJECT_DIR"

FAILURES=""

echo "=== Pre-Flight Checklist ===" >&2

# 1. Clean build
echo "  [1/5] Clean build..." >&2
xcodebuild build -project Drift.xcodeproj -scheme Drift \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  > /tmp/drift-preflight-build.log 2>&1
if [ $? -ne 0 ]; then
  FAILURES="${FAILURES}\n- BUILD FAILED (see /tmp/drift-preflight-build.log)"
else
  echo "  [1/5] Build OK" >&2
fi

# 2. Full test suite
echo "  [2/5] Full test suite..." >&2
pkill -9 -f xcodebuild 2>/dev/null || true
sleep 2
xcodebuild test -project Drift.xcodeproj -scheme Drift \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:DriftTests \
  > /tmp/drift-preflight-test.log 2>&1
if [ $? -ne 0 ]; then
  FAILED_TESTS=$(grep "✘" /tmp/drift-preflight-test.log 2>/dev/null | head -10)
  FAILURES="${FAILURES}\n- TESTS FAILED:\n${FAILED_TESTS}"
else
  echo "  [2/5] Tests OK" >&2
fi

# 3. AI eval harness
echo "  [3/5] AI eval harness..." >&2
pkill -9 -f xcodebuild 2>/dev/null || true
sleep 2
xcodebuild test -project Drift.xcodeproj -scheme Drift \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:'DriftTests/AIEvalHarness' \
  > /tmp/drift-preflight-eval.log 2>&1
if [ $? -ne 0 ]; then
  FAILED_EVAL=$(grep "✘" /tmp/drift-preflight-eval.log 2>/dev/null | head -10)
  FAILURES="${FAILURES}\n- AI EVAL FAILED:\n${FAILED_EVAL}"
else
  echo "  [3/5] AI eval OK" >&2
fi

# 4. No uncommitted changes
echo "  [4/5] Clean git state..." >&2
DIRTY=$(git status --porcelain 2>/dev/null | grep -v '^??' | grep -v '.claude/' | head -5)
if [ -n "$DIRTY" ]; then
  FAILURES="${FAILURES}\n- UNCOMMITTED CHANGES:\n${DIRTY}"
else
  echo "  [4/5] Git clean" >&2
fi

# 5. Check for recent regressions — any reverts in last 5 commits
echo "  [5/5] No recent reverts..." >&2
REVERTS=$(git log --oneline -5 | grep -i "revert\|checkout --\|broken\|FAILED" | head -3)
if [ -n "$REVERTS" ]; then
  # Warning only, don't block
  echo "  [5/5] WARNING: Recent reverts found (not blocking):" >&2
  echo "  ${REVERTS}" >&2
else
  echo "  [5/5] No reverts" >&2
fi

# 6. Check for open P0 bug issues — FAIL-CLOSED: treat API errors as "bugs present".
# Also cross-check the watchdog's cache-p0-bugs file so a transient gh flake can't
# silently skip the guard. Build 152 (2026-04-20) shipped with #271 open because the
# previous version silently treated empty gh output as "no bugs."
echo "  [6/6] No P0 bugs..." >&2
P0_RAW=$(gh issue list --state open --label bug --label P0 --json number,title 2>&1)
GH_EXIT=$?
CACHE_P0=$(cat "$HOME/drift-state/cache-p0-bugs" 2>/dev/null || true)
if [ "$GH_EXIT" -ne 0 ]; then
  FAILURES="${FAILURES}\n- gh api failed verifying P0 status (exit $GH_EXIT). Watchdog cache says:\n${CACHE_P0:-(empty)}\n${P0_RAW}"
elif [ -n "$P0_RAW" ] && echo "$P0_RAW" | jq -e 'length > 0' >/dev/null 2>&1; then
  P0_TITLES=$(echo "$P0_RAW" | jq -r '.[].title' | head -3)
  FAILURES="${FAILURES}\n- OPEN P0 BUGS (fix before publishing):\n${P0_TITLES}"
elif [ -n "$CACHE_P0" ]; then
  FAILURES="${FAILURES}\n- Watchdog cache-p0-bugs is still non-empty (label race). Clear it before publishing:\n${CACHE_P0}"
else
  echo "  [6/6] No P0 bugs" >&2
fi

echo "===========================" >&2

if [ -n "$FAILURES" ]; then
  echo -e "BLOCKED: Pre-flight checks failed. Fix these before publishing to TestFlight:\n${FAILURES}\n\nDo NOT skip pre-flight. Fix the issues, then retry the archive." >&2
  # Remove the authorization flag so it has to go through the cycle again
  rm -f "$HOME/drift-state/testflight-publish-authorized"
  exit 2
fi

echo "Pre-flight passed. Proceeding with archive." >&2
exit 0
