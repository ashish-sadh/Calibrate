#!/bin/bash
# Drift Self-Improvement Watchdog
# Alternates between self-improvement and code-improvement loops.
# Restarts claude if it dies or stalls. Controlled via ~/drift-control.txt.
#
# Usage: ./scripts/self-improve-watchdog.sh
# Stop:  echo "STOP" > ~/drift-control.txt
# Pause: echo "PAUSE" > ~/drift-control.txt
# Run:   echo "RUN" > ~/drift-control.txt

set -euo pipefail

WORK_DIR="/Users/ashishsadh/workspace/Drift"
CONTROL_FILE="$HOME/drift-control.txt"
LOG_DIR="$HOME/drift-self-improve-logs"
WATCHDOG_LOG="$LOG_DIR/watchdog.log"
CHECK_INTERVAL=1800  # 30 minutes
STALE_THRESHOLD=1500 # 25 minutes (in seconds)
KILL_WAIT=10

PROMPTS=("run self-improvement" "run code-improvement")
CURRENT=0
CLAUDE_PID=""
CURRENT_LOG=""

mkdir -p "$LOG_DIR"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$WATCHDOG_LOG"
}

read_control() {
    if [[ -f "$CONTROL_FILE" ]]; then
        tr -d '[:space:]' < "$CONTROL_FILE" | tr '[:lower:]' '[:upper:]'
    else
        echo "RUN"
    fi
}

kill_claude() {
    if [[ -n "$CLAUDE_PID" ]] && kill -0 "$CLAUDE_PID" 2>/dev/null; then
        log "Sending SIGTERM to claude (PID $CLAUDE_PID)..."
        kill "$CLAUDE_PID" 2>/dev/null || true
        local waited=0
        while kill -0 "$CLAUDE_PID" 2>/dev/null && (( waited < KILL_WAIT )); do
            sleep 1
            (( waited++ ))
        done
        if kill -0 "$CLAUDE_PID" 2>/dev/null; then
            log "SIGTERM didn't work, sending SIGKILL..."
            kill -9 "$CLAUDE_PID" 2>/dev/null || true
        fi
        log "Claude process stopped."
    fi
    CLAUDE_PID=""
}

start_claude() {
    local prompt="${PROMPTS[$CURRENT]}"
    local label="${prompt// /-}"
    CURRENT_LOG="$LOG_DIR/session_${label}_$(date +%s).log"

    log "Starting claude: \"$prompt\" (log: $CURRENT_LOG)"
    cd "$WORK_DIR"
    claude -p "$prompt" \
        --dangerously-skip-permissions \
        --model opus \
        --effort max \
        > "$CURRENT_LOG" 2>&1 &
    CLAUDE_PID=$!
    log "Claude started with PID $CLAUDE_PID"

    # Alternate for next time
    CURRENT=$(( (CURRENT + 1) % 2 ))
}

is_claude_alive() {
    [[ -n "$CLAUDE_PID" ]] && kill -0 "$CLAUDE_PID" 2>/dev/null
}

is_log_stale() {
    if [[ -z "$CURRENT_LOG" ]] || [[ ! -f "$CURRENT_LOG" ]]; then
        return 1  # No log yet, not stale
    fi
    local now
    now=$(date +%s)
    local last_mod
    last_mod=$(stat -f %m "$CURRENT_LOG" 2>/dev/null || echo "$now")
    local age=$(( now - last_mod ))
    (( age > STALE_THRESHOLD ))
}

cleanup() {
    log "Watchdog shutting down (signal received)..."
    kill_claude
    exit 0
}

trap cleanup SIGINT SIGTERM

# Initialize control file if missing
if [[ ! -f "$CONTROL_FILE" ]]; then
    echo "RUN" > "$CONTROL_FILE"
fi

log "========================================="
log "Watchdog started"
log "Control file: $CONTROL_FILE"
log "Check interval: ${CHECK_INTERVAL}s"
log "========================================="

# Initial start
STATE=$(read_control)
if [[ "$STATE" == "RUN" ]]; then
    start_claude
elif [[ "$STATE" == "PAUSE" ]]; then
    log "Control file says PAUSE — waiting..."
elif [[ "$STATE" == "STOP" ]]; then
    log "Control file says STOP — exiting."
    exit 0
fi

# Main watchdog loop
while true; do
    sleep "$CHECK_INTERVAL"

    STATE=$(read_control)
    log "Check cycle — control: $STATE, claude PID: ${CLAUDE_PID:-none}"

    case "$STATE" in
        STOP)
            log "STOP requested. Shutting down."
            kill_claude
            exit 0
            ;;
        PAUSE)
            if is_claude_alive; then
                log "PAUSE requested. Killing claude."
                kill_claude
            fi
            log "Paused. Waiting for RUN..."
            continue
            ;;
        RUN)
            # Check if claude is dead
            if ! is_claude_alive; then
                log "Claude process exited. Restarting with next prompt..."
                start_claude
            # Check if claude is stalled
            elif is_log_stale; then
                log "Claude appears stalled (log not updated in ${STALE_THRESHOLD}s). Restarting..."
                kill_claude
                start_claude
            else
                log "Claude running normally (PID $CLAUDE_PID)."
            fi
            ;;
        *)
            log "Unknown control state: $STATE — treating as RUN"
            ;;
    esac
done
