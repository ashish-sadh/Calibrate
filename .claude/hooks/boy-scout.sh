#!/bin/bash
# Hook: PostToolUse on Edit/Write
# Boy scout rule: after editing a .swift file, remind to clean what you touched.

set -e

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only for swift files
case "$FILE_PATH" in
  *.swift)
    ;;
  *)
    exit 0
    ;;
esac

BASENAME=$(basename "$FILE_PATH")

cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "Boy scout rule: you just edited ${BASENAME}. If you see obvious code smells in the area you touched (long function, bad naming, dead code, DDD violation, missing error handling), fix them in this same commit. Don't go looking for problems elsewhere — just clean what you touched. For bigger architectural work, do it when feature work requires it."
  }
}
ENDJSON

exit 0
