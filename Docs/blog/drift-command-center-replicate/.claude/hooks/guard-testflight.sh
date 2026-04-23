#!/bin/bash
# Hook: PreToolUse on Bash
# Two gates for TestFlight — ONLY enforced on autonomous loop sessions (DRIFT_AUTONOMOUS=1).
# Human sessions can publish freely.

set -e

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only gate ACTUAL xcodebuild invocations — not grep/echo/cat that merely mention
# "xcodebuild archive" in their arguments (that false-positive blocked the operator's
# diagnostic greps). Skip leading VAR=value env assignments before reading the verb.
FIRST_WORD=$(echo "$COMMAND" | awk '{for (i=1;i<=NF;i++) if ($i !~ /^[A-Za-z_][A-Za-z0-9_]*=/) {print $i; exit}}')
SUBCMD=$(echo "$COMMAND" | awk '{seen=0; for (i=1;i<=NF;i++) if ($i !~ /^[A-Za-z_][A-Za-z0-9_]*=/) {if (seen) {print $i; exit}; seen=1}}')

case "$FIRST_WORD" in
  xcodebuild|*/xcodebuild) ;;
  *) exit 0 ;;
esac

case "$SUBCMD" in
  archive|-exportArchive) ;;
  *) exit 0 ;;
esac

# Human sessions can always publish
DRIFT_CONTROL=$(cat "$HOME/drift-control.txt" 2>/dev/null | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
if [ "$DRIFT_CONTROL" != "RUN" ]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
FLAG_FILE="$HOME/drift-state/testflight-publish-authorized"

# Gate 1: Authorization check (autonomous only)
if [ ! -f "$FLAG_FILE" ]; then
  echo "BLOCKED: Autonomous session — TestFlight publishing only allowed when triggered by the 3-hour hook." >&2
  exit 2
fi

# Gate 2: Pre-flight checklist (only for archive, not export)
if [ "$SUBCMD" = "archive" ]; then
  exec "$PROJECT_DIR/.claude/hooks/preflight-check.sh"
fi

exit 0
