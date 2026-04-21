#!/bin/bash
# Hook: PreToolUse on Bash
# Enforces PAUSE at safe between-task boundaries.
# Uses anchored matching — only fires when command STARTS with these patterns.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Anchored: command must start with these — prevents matching on commit messages etc.
if [[ "$COMMAND" != scripts/sprint-service.sh* && \
      "$COMMAND" != scripts/planning-service.sh* && \
      "$COMMAND" != "gh issue close"* ]]; then
    exit 0
fi

# PAUSE gate only applies to autopilot sessions. The watchdog exports
# DRIFT_AUTONOMOUS=1 before launching Claude; human-started sessions don't
# have it. cache-session-type is not used here because it gets overwritten by
# every autopilot spawn and stays stamped "senior"/"junior"/"planning" during
# human takeover.
if [ "${DRIFT_AUTONOMOUS:-}" != "1" ]; then
    exit 0
fi

CONTROL="$(cat "$HOME/drift-control.txt" 2>/dev/null || echo RUN)"
[ "$CONTROL" != "PAUSE" ] && exit 0

# Hard block on claim only — session cannot start new task
if [[ "$COMMAND" == scripts/sprint-service.sh\ claim* ]]; then
    echo "BLOCKED: PAUSE active — cannot claim new task. Finish current work and exit." >&2
    exit 2
fi

# Soft signal for all other safe-stop-point commands
cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "PAUSE active (~/drift-control.txt). Do not start new work. Exit cleanly after this step."
  }
}
ENDJSON
exit 0
