#!/bin/bash
# Hook: PostToolUse on Bash(gh issue close *)
# BLOCKS issue close without --comment.

set -e

TOOL_INPUT="${TOOL_INPUT:-}"
echo "$TOOL_INPUT" | grep -q "gh issue close" || exit 0

if ! echo "$TOOL_INPUT" | grep -q "\-\-comment"; then
  echo "BLOCKED: Cannot close issues without --comment. Use: gh issue close N --comment 'Fixed: ... (commit abc123)'"
  exit 2
fi

exit 0
