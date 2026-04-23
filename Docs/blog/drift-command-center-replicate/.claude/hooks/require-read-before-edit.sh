#!/bin/bash
# Hook: PreToolUse on Edit/Write
# Blocks editing a file that hasn't been Read in this session.
# Prevents blind edits that cause build failures.

set -e

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')

# Skip if no file path (shouldn't happen for Edit/Write)
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Skip for new files being created (Write to non-existent path)
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# Skip for docs/config files — these don't cause build failures
case "$FILE_PATH" in
  *.md|*.json|*.yml|*.yaml|*.txt|*.sh|*.log)
    exit 0
    ;;
esac

# Check if the file was Read in this session's transcript
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  if grep -q "\"file_path\":\"$FILE_PATH\"" "$TRANSCRIPT" 2>/dev/null; then
    exit 0  # File was read, allow edit
  fi
  # Also check with escaped slashes
  ESCAPED_PATH=$(echo "$FILE_PATH" | sed 's/\//\\\//g')
  if grep -q "$ESCAPED_PATH" "$TRANSCRIPT" 2>/dev/null; then
    exit 0
  fi
fi

echo "BLOCKED: Must Read $FILE_PATH before editing it. Read the file first to understand types, signatures, and imports." >&2
exit 2
