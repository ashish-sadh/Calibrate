#!/bin/bash
# Hook: PreToolUse on Bash
# Two gates for TestFlight — ONLY enforced on autonomous loop sessions (DRIFT_AUTONOMOUS=1).
# Human sessions can publish freely.

set -e

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only care about archive/export commands
case "$COMMAND" in
  *"xcodebuild archive"*|*"xcodebuild -exportArchive"*)
    ;;
  *)
    exit 0
    ;;
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
case "$COMMAND" in
  *"xcodebuild archive"*)
    exec "$PROJECT_DIR/.claude/hooks/preflight-check.sh"
    ;;
  *)
    exit 0
    ;;
esac
