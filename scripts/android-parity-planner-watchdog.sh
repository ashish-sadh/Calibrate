#!/bin/bash
# Planner lane (Opus) of the tiered parity autopilot:
#   Fable tests & finds gaps → OPUS PLANS (this) → Sonnet executes.
# Runs one short /android-parity-planner session whenever `needs-plan` issues
# exist; idles otherwise. Shares the control file with the other lanes.
set -uo pipefail

WORK_DIR="/Users/ashishsadh/workspace/Drift"
CONTROL_FILE="$HOME/drift-android-parity.txt"
LOG_DIR="$HOME/drift-android-parity-planner-logs"
PID_FILE="$LOG_DIR/claude.pid"
WATCHDOG_LOG="$LOG_DIR/watchdog.log"
CHECK_INTERVAL=60
STALL_SECONDS=1500       # planners are read+comment only; 25 min silent = hung
CRASH_WINDOW=60
MAX_FAST_CRASHES=5
COOL_OFF=1800
QUEUE_POLL=600           # check for needs-plan work every 10 min when idle

mkdir -p "$LOG_DIR"
[ -f "$CONTROL_FILE" ] || echo "RUN" > "$CONTROL_FILE"

EXISTING=$(pgrep -f "android-parity-planner-watchdog.sh" | grep -v $$ || true)
[ -n "$EXISTING" ] && { echo "$EXISTING" | xargs kill 2>/dev/null || true; sleep 1; }

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$WATCHDOG_LOG"; }

fast_crashes=0
log "Planner watchdog started (pid $$)."

while true; do
    CONTROL=$(tr -d '[:space:]' < "$CONTROL_FILE" 2>/dev/null || echo RUN)
    case "$CONTROL" in
        STOP)  log "STOP — exiting."; exit 0 ;;
        PAUSE) sleep "$CHECK_INTERVAL"; continue ;;
    esac

    # Only spawn when there is planning work (saves Opus).
    PENDING=$(cd "$WORK_DIR" && gh issue list --label android-parity --label needs-plan --state open --json number --jq 'length' 2>/dev/null || echo 0)
    if [ "${PENDING:-0}" -eq 0 ]; then
        sleep "$QUEUE_POLL"; continue
    fi

    SESSION_LOG="$LOG_DIR/session-$(date +%Y%m%d-%H%M%S).log"
    log "$PENDING needs-plan issue(s) — spawning planner → $SESSION_LOG"
    (
        cd "$WORK_DIR" || exit 1
        export DRIFT_AUTONOMOUS=1
        exec "${CLAUDE_BIN:-$HOME/.local/bin/claude}" -p "/android-parity-planner" \
            --dangerously-skip-permissions \
            --model claude-opus-4-8 \
            --fallback-model claude-sonnet-5 \
            --effort max \
            --output-format stream-json \
            --verbose
    ) > "$SESSION_LOG" 2>&1 &
    CLAUDE_PID=$!
    echo "$CLAUDE_PID" > "$PID_FILE"
    STARTED=$(date +%s)

    while kill -0 "$CLAUDE_PID" 2>/dev/null; do
        sleep "$CHECK_INTERVAL"
        CONTROL=$(tr -d '[:space:]' < "$CONTROL_FILE" 2>/dev/null || echo RUN)
        if [ "$CONTROL" = "STOP" ] || [ "$CONTROL" = "PAUSE" ]; then
            log "$CONTROL — killing planner $CLAUDE_PID"
            kill "$CLAUDE_PID" 2>/dev/null; sleep 5
            kill -9 "$CLAUDE_PID" 2>/dev/null || true
            break
        fi
        if [ -f "$SESSION_LOG" ]; then
            AGE=$(( $(date +%s) - $(stat -f %m "$SESSION_LOG") ))
            if [ "$AGE" -gt "$STALL_SECONDS" ]; then
                log "Stall (${AGE}s) — killing planner $CLAUDE_PID"
                kill "$CLAUDE_PID" 2>/dev/null; sleep 5
                kill -9 "$CLAUDE_PID" 2>/dev/null || true
                break
            fi
        fi
    done
    wait "$CLAUDE_PID" 2>/dev/null
    RC=$?
    RAN=$(( $(date +%s) - STARTED ))
    log "Planner ended rc=$RC after ${RAN}s"

    if [ "$RAN" -lt "$CRASH_WINDOW" ]; then
        fast_crashes=$((fast_crashes + 1))
        if [ "$fast_crashes" -ge "$MAX_FAST_CRASHES" ]; then
            log "$fast_crashes fast crashes — cooling off ${COOL_OFF}s"
            sleep "$COOL_OFF"; fast_crashes=0
        fi
    else
        fast_crashes=0
    fi
    sleep 60
done
