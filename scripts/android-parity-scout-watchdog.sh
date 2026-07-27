#!/bin/bash
# Scout lane for the Android-parity loop: loops read-only /android-parity-scout
# sessions that pre-produce port kits for upcoming targets, so implementation
# sessions skip their ~45-60min study phase. Shares the control file with the
# main watchdog (PAUSE/STOP affect both lanes).
set -uo pipefail

WORK_DIR="/Users/ashishsadh/workspace/Drift"
CONTROL_FILE="$HOME/drift-android-parity.txt"
LOG_DIR="$HOME/drift-android-parity-scout-logs"
PID_FILE="$LOG_DIR/claude.pid"
WATCHDOG_LOG="$LOG_DIR/watchdog.log"
CHECK_INTERVAL=60
STALL_SECONDS=1500       # scouts are read-only; 25 min silent = hung
CRASH_WINDOW=90
MAX_FAST_CRASHES=5
COOL_OFF=1800
IDLE_BETWEEN=5400        # Fable tester: one sweep, then a long breather (save Fable)

mkdir -p "$LOG_DIR" "$HOME/drift-android-parity-prep"
[ -f "$CONTROL_FILE" ] || echo "RUN" > "$CONTROL_FILE"

EXISTING=$(pgrep -f "android-parity-scout-watchdog.sh" | grep -v $$ || true)
if [ -n "$EXISTING" ]; then
    echo "$EXISTING" | xargs kill 2>/dev/null || true
    sleep 1
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$WATCHDOG_LOG"; }

fast_crashes=0
log "Scout watchdog started (pid $$)."

while true; do
    CONTROL=$(tr -d '[:space:]' < "$CONTROL_FILE" 2>/dev/null || echo RUN)
    case "$CONTROL" in
        STOP)  log "STOP — exiting."; exit 0 ;;
        PAUSE) sleep "$CHECK_INTERVAL"; continue ;;
    esac

    # Memory-pressure yield: the worker's release archive uses whole-module
    # optimization (very memory-hungry) and gets OOM-SIGKILLed under sustained
    # pressure. A scout building/simulating concurrently is exactly that extra
    # pressure (see harness_android_publish_release_archive_oom memory). Do NOT
    # start a new scout while a publish holds the lock — wait it out.
    if [ -f /tmp/drift-android-publish.lock ]; then
        log "Publish in progress — holding scout to relieve memory pressure."
        sleep "$CHECK_INTERVAL"; continue
    fi

    SESSION_LOG="$LOG_DIR/session-$(date +%Y%m%d-%H%M%S).log"
    log "Spawning /android-parity-scout session → $SESSION_LOG"
    # exec so $! is the claude process itself (see worker watchdog incident note)
    (
        cd "$WORK_DIR" || exit 1
        export DRIFT_AUTONOMOUS=1
        exec "${CLAUDE_BIN:-$HOME/.local/bin/claude}" -p "/android-parity-scout" \
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

    while kill -0 "$CLAUDE_PID" 2>/dev/null; do
        sleep "$CHECK_INTERVAL"
        CONTROL=$(tr -d '[:space:]' < "$CONTROL_FILE" 2>/dev/null || echo RUN)
        if [ "$CONTROL" = "STOP" ] || [ "$CONTROL" = "PAUSE" ]; then
            log "$CONTROL requested — killing scout $CLAUDE_PID"
            kill "$CLAUDE_PID" 2>/dev/null; sleep 5
            kill -9 "$CLAUDE_PID" 2>/dev/null || true
            break
        fi
        # Memory-pressure yield DURING a run: a scout already running when a
        # publish begins keeps spiking memory and OOM-kills the worker's
        # release archive (build 39 recurrence — refraining from *spawning*
        # wasn't enough). Kill the running scout the moment a publish starts;
        # a lost kit is cheap, a stalled publish is not.
        if [ -f /tmp/drift-android-publish.lock ]; then
            log "Publish started mid-scout — killing scout $CLAUDE_PID to free memory"
            kill "$CLAUDE_PID" 2>/dev/null; sleep 3
            kill -9 "$CLAUDE_PID" 2>/dev/null || true
            xcrun simctl shutdown "iPhone 17" 2>/dev/null || true
            break
        fi
        if [ -f "$SESSION_LOG" ]; then
            AGE=$(( $(date +%s) - $(stat -f %m "$SESSION_LOG") ))
            if [ "$AGE" -gt "$STALL_SECONDS" ]; then
                log "Stall (${AGE}s silent) — killing scout $CLAUDE_PID"
                kill "$CLAUDE_PID" 2>/dev/null; sleep 5
                kill -9 "$CLAUDE_PID" 2>/dev/null || true
                break
            fi
        fi
    done
    wait "$CLAUDE_PID" 2>/dev/null
    RC=$?
    RAN=$(( $(date +%s) - STARTED ))
    log "Scout ended rc=$RC after ${RAN}s"

    if [ "$RAN" -lt "$CRASH_WINDOW" ]; then
        fast_crashes=$((fast_crashes + 1))
        if [ "$fast_crashes" -ge "$MAX_FAST_CRASHES" ]; then
            log "$fast_crashes fast crashes — cooling off ${COOL_OFF}s"
            sleep "$COOL_OFF"
            fast_crashes=0
        fi
    else
        fast_crashes=0
    fi
    sleep "$IDLE_BETWEEN"
done
