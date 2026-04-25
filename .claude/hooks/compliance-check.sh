#!/bin/bash

# Silent for non-autonomous (human) sessions — these hooks are autopilot-only.
[[ "${DRIFT_AUTONOMOUS:-0}" != "1" ]] && exit 0
# Hook: PreToolUse on Bash|Grep
# Lightweight P0 reminder only. Sprint service enforces all other priorities.
# Injecting full compliance wall on every bash call trains the model to ignore it.

STATE_DIR="$HOME/drift-state"

# Only output if there are open P0 bugs
if [ -s "$STATE_DIR/cache-p0-bugs" ]; then
    P0S=$(cat "$STATE_DIR/cache-p0-bugs")
    cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "P0 BUGS OPEN — handle before anything else:\n${P0S}\nGet task: scripts/sprint-service.sh next"
  }
}
ENDJSON
fi

exit 0
