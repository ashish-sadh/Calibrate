#!/bin/bash
# Android Parity Watchdog — loops autonomous /android-parity sessions so the
# iOS-matching port (epic #1059) is never idle. Modeled on
# self-improve-watchdog.sh but independent of Drift Control: its own control
# file, logs, and cadence.
#
# Usage: ./scripts/android-parity-watchdog.sh &
# Stop:  echo "STOP"  > ~/drift-android-parity.txt
# Pause: echo "PAUSE" > ~/drift-android-parity.txt
# Run:   echo "RUN"   > ~/drift-android-parity.txt
set -uo pipefail

WORK_DIR="/Users/ashishsadh/workspace/Drift"
CONTROL_FILE="$HOME/drift-android-parity.txt"
LOG_DIR="$HOME/drift-android-parity-logs"
PID_FILE="$LOG_DIR/claude.pid"
WATCHDOG_LOG="$LOG_DIR/watchdog.log"
CHECK_INTERVAL=60
STALL_SECONDS=2700       # 45 min with no log growth = hung session
CRASH_WINDOW=90          # session died faster than this = crash
MAX_FAST_CRASHES=5       # this many in a row → cool off
COOL_OFF=1800

mkdir -p "$LOG_DIR"
[ -f "$CONTROL_FILE" ] || echo "RUN" > "$CONTROL_FILE"

# Single instance
EXISTING=$(pgrep -f "android-parity-watchdog.sh" | grep -v $$ || true)
if [ -n "$EXISTING" ]; then
    echo "$EXISTING" | xargs kill 2>/dev/null || true
    sleep 1
fi

# Keep the Mac awake while we supervise (see watchdog_sleep_guard memory).
caffeinate -is -w $$ &

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$WATCHDOG_LOG"; }

fast_crashes=0
log "Android parity watchdog started (pid $$). Control: $CONTROL_FILE"

while true; do
    CONTROL=$(tr -d '[:space:]' < "$CONTROL_FILE" 2>/dev/null || echo RUN)
    case "$CONTROL" in
        STOP)  log "STOP — exiting."; exit 0 ;;
        PAUSE) sleep "$CHECK_INTERVAL"; continue ;;
    esac

    SESSION_LOG="$LOG_DIR/session-$(date +%Y%m%d-%H%M%S).log"
    log "Spawning /android-parity session → $SESSION_LOG"
    # exec so $! is the claude process itself — kill/stall-kill previously hit
    # only the wrapper subshell, orphaning the session (2026-07-19 incident).
    (
        cd "$WORK_DIR" || exit 1
        export DRIFT_AUTONOMOUS=1
        export JAVA_HOME=/opt/homebrew/opt/openjdk
        export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
        exec "${CLAUDE_BIN:-$HOME/.local/bin/claude}" -p "/android-parity" \
            --dangerously-skip-permissions \
            --model claude-fable-5 \
            --fallback-model claude-opus-4-8 \
            --effort max \
            --output-format stream-json \
            --verbose
    ) > "$SESSION_LOG" 2>&1 &
    CLAUDE_PID=$!
    echo "$CLAUDE_PID" > "$PID_FILE"
    STARTED=$(date +%s)

    # Babysit until it exits or stalls
    while kill -0 "$CLAUDE_PID" 2>/dev/null; do
        sleep "$CHECK_INTERVAL"
        CONTROL=$(tr -d '[:space:]' < "$CONTROL_FILE" 2>/dev/null || echo RUN)
        if [ "$CONTROL" = "STOP" ] || [ "$CONTROL" = "PAUSE" ]; then
            log "$CONTROL requested — killing session $CLAUDE_PID"
            kill "$CLAUDE_PID" 2>/dev/null; sleep 5
            kill -9 "$CLAUDE_PID" 2>/dev/null || true
            break
        fi
        # Stall: log file stopped growing
        if [ -f "$SESSION_LOG" ]; then
            AGE=$(( $(date +%s) - $(stat -f %m "$SESSION_LOG") ))
            if [ "$AGE" -gt "$STALL_SECONDS" ]; then
                log "Stall (${AGE}s silent) — killing session $CLAUDE_PID"
                kill "$CLAUDE_PID" 2>/dev/null; sleep 5
                kill -9 "$CLAUDE_PID" 2>/dev/null || true
                break
            fi
        fi
    done
    wait "$CLAUDE_PID" 2>/dev/null
    RC=$?
    RAN=$(( $(date +%s) - STARTED ))
    log "Session ended rc=$RC after ${RAN}s"

    if [ "$RAN" -lt "$CRASH_WINDOW" ]; then
        fast_crashes=$((fast_crashes + 1))
        if [ "$fast_crashes" -ge "$MAX_FAST_CRASHES" ]; then
            # Repeated fast crashes = Claude credit exhausted (Fable AND Opus).
            # Raise the flag the Codex fallback lane watches, then cool off.
            log "$fast_crashes fast crashes — Claude likely exhausted; raising codex-fallback flag; cooling off ${COOL_OFF}s"
            touch "$LOG_DIR/claude-exhausted.flag"
            sleep "$COOL_OFF"
            fast_crashes=0
        fi
    else
        # A real session ran — Claude is back. Clear the exhaustion flag so the
        # Codex fallback lane stands down and parity resumes ownership.
        fast_crashes=0
        rm -f "$LOG_DIR/claude-exhausted.flag"
    fi
    sleep 15
done
