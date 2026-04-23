#!/bin/bash
# Pre/PostToolUse hook — stamps ~/drift-state/session-heartbeat and appends
# to ~/drift-state/session-heartbeat.log on every tool call from an autopilot
# session. The signal file is read by the watchdog's liveness check; the log
# feeds the Command Center activity graph.
#
# Only stamps when DRIFT_AUTONOMOUS=1 so interactive sessions don't pollute
# the watchdog's signal or the graph.

set -e

[ "${DRIFT_AUTONOMOUS:-0}" = "1" ] || exit 0

mkdir -p "$HOME/drift-state"
NOW=$(date +%s)
SESSION_TYPE=$(cat "$HOME/drift-state/cache-session-type" 2>/dev/null || echo "unknown")

# Signal file: latest heartbeat only, atomic replace.
echo "$NOW" > "$HOME/drift-state/session-heartbeat"

# Activity log: one line per invocation, read by the Command Center graph.
# Cap at 20000 lines (~a day of busy work at 1 line / 4s) so the file can't
# grow unbounded — rotate on append when past the cap.
LOG="$HOME/drift-state/session-heartbeat.log"
echo "$NOW $SESSION_TYPE" >> "$LOG"

LINES=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')
if [ -n "$LINES" ] && [ "$LINES" -gt 20000 ]; then
    tail -n 15000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

exit 0
