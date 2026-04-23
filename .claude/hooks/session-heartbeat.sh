#!/bin/bash
# PreToolUse hook — stamps ~/drift-state/session-heartbeat with epoch seconds
# on every tool call from an autopilot session. The watchdog's liveness check
# reads this instead of log-file mtime; log output buffers can go quiet for
# 10+ minutes during large generation bursts (writing a long test file,
# deep thinking chains) even when the session is actively working. Tool-call
# cadence is a better "alive" signal.
#
# Only stamps when DRIFT_AUTONOMOUS=1 — keeps interactive sessions from
# polluting the watchdog's signal.

set -e

[ "${DRIFT_AUTONOMOUS:-0}" = "1" ] || exit 0

mkdir -p "$HOME/drift-state"
date +%s > "$HOME/drift-state/session-heartbeat"
exit 0
