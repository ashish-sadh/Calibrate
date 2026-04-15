#!/bin/bash
# Drift Control — Watchdog for Autopilot
# Manages autonomous Autopilot sessions. Restarts on crash/stall.
# Controlled via ~/drift-control.txt.
#
# Usage: ./scripts/self-improve-watchdog.sh
# Stop:  echo "STOP" > ~/drift-control.txt
# Pause: echo "PAUSE" > ~/drift-control.txt
# Drain: echo "DRAIN" > ~/drift-control.txt
# Run:   echo "RUN" > ~/drift-control.txt

set -euo pipefail

# Kill any existing watchdog (prevent duplicates)
EXISTING=$(pgrep -f "self-improve-watchdog.sh" | grep -v $$ || true)
if [ -n "$EXISTING" ]; then
    echo "$EXISTING" | xargs kill 2>/dev/null || true
    sleep 1
fi

WORK_DIR="/Users/ashishsadh/workspace/Drift"
CONTROL_FILE="$HOME/drift-control.txt"
LOG_DIR="$HOME/drift-self-improve-logs"
WATCHDOG_LOG="$LOG_DIR/watchdog.log"
PID_FILE="$LOG_DIR/claude.pid"
CHECK_INTERVAL=300  # 5 minutes
STALE_THRESHOLD=600  # 10 minutes (in seconds)
KILL_WAIT=10
CRASH_FILE="$HOME/drift-state/consecutive-crashes"
MONITOR_PID=""

PROMPT="run autopilot"
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

cleanup_dirty_state() {
    cd "$WORK_DIR"
    # Abort interrupted merges/rebases
    git merge --abort 2>/dev/null || true
    git rebase --abort 2>/dev/null || true
    # Drop stashes left by crashed sessions
    git stash drop 2>/dev/null || true

    local DIRTY=$(git status --porcelain 2>/dev/null | head -20)
    if [[ -n "$DIRTY" ]]; then
        log "Dirty state after session exit. Discarding incomplete changes:"
        log "$DIRTY"
        git checkout . 2>/dev/null || true
        git clean -fd --exclude=.claude/ 2>/dev/null || true
        log "Working tree cleaned."
    fi

    # Remove stale in-progress labels — no session is running, nothing is in-progress
    local IN_PROGRESS=$(gh issue list --state open --label in-progress --json number --jq '.[].number' 2>/dev/null || true)
    if [[ -n "$IN_PROGRESS" ]]; then
        for NUM in $IN_PROGRESS; do
            gh issue edit "$NUM" --remove-label in-progress 2>/dev/null || true
        done
        log "Removed in-progress from: $IN_PROGRESS"
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
        stop_monitor
    fi
    CLAUDE_PID=""
}

start_monitor() {
    stop_monitor
    # Get or create the live-status issue
    local ISSUE_NUM=$(cat "$HOME/drift-state/live-status-issue" 2>/dev/null || echo "")
    if [[ -z "$ISSUE_NUM" ]] || ! gh issue view "$ISSUE_NUM" --json state --jq '.state' 2>/dev/null | grep -q "OPEN"; then
        ISSUE_NUM=$(gh issue create --title "Drift Live Status" --label live-status --body "Starting..." --json number --jq '.number' 2>/dev/null || echo "")
        [[ -n "$ISSUE_NUM" ]] && echo "$ISSUE_NUM" > "$HOME/drift-state/live-status-issue"
    fi
    if [[ -n "$ISSUE_NUM" ]] && [[ -n "$CURRENT_LOG" ]]; then
        "$WORK_DIR/scripts/session-monitor.sh" "$CURRENT_LOG" "$ISSUE_NUM" &
        MONITOR_PID=$!
        log "Monitor started (PID $MONITOR_PID, issue #$ISSUE_NUM)"
    fi
}

stop_monitor() {
    if [[ -n "$MONITOR_PID" ]] && kill -0 "$MONITOR_PID" 2>/dev/null; then
        kill "$MONITOR_PID" 2>/dev/null || true
        log "Monitor stopped."
    fi
    MONITOR_PID=""
}

refresh_compliance_cache() {
    local SD="$HOME/drift-state"
    cd "$WORK_DIR"

    # P0 bugs (all sessions care)
    gh issue list --state open --label P0 --json number,title \
        --jq '.[] | "#\(.number) \(.title)"' > "$SD/cache-p0-bugs" 2>/dev/null || true

    # P0 feature requests without sprint tasks (senior cares)
    gh issue list --state open --label feature-request --label P0 --json number,title \
        --jq '.[] | "#\(.number) \(.title)"' > "$SD/cache-p0-features" 2>/dev/null || true

    # Design doc PRs with comments needing reply (senior cares)
    gh pr list --label design-doc --state open --json number,title,comments \
        --jq '.[] | select(.comments > 0) | "#\(.number) \(.title) (\(.comments) comments)"' \
        > "$SD/cache-design-reviews" 2>/dev/null || true

    # Pending design docs — issues with design-doc label but no doc-ready (senior cares)
    gh issue list --state open --label design-doc --json number,title,labels \
        --jq '[.[] | select(.labels | map(.name) | index("doc-ready") | not)] | .[] | "#\(.number) \(.title)"' \
        > "$SD/cache-pending-designs" 2>/dev/null || true

    # Admin feedback on report PRs (senior/planning cares)
    gh pr list --label report --state all --json number,title,comments \
        --jq '.[] | select(.comments > 0) | "#\(.number) \(.title) (\(.comments) comments)"' \
        | head -5 > "$SD/cache-admin-feedback" 2>/dev/null || true

    # Product focus
    gh issue list --state open --label product-focus --json body \
        --jq '.[0].body // empty' | head -1 > "$SD/cache-product-focus" 2>/dev/null || true

    # Session type (written by start_claude, but refresh here too)
    # last-model is already written by start_claude
}

start_claude() {
    local MODEL="sonnet"
    local SESSION_TYPE="junior"
    local SESSION_PROMPT="$PROMPT"
    local NOW=$(date +%s)

    # 1. Sprint planning due? (every 6 hours)
    if [[ "$(( (NOW - $(cat "$HOME/drift-state/last-review-time" 2>/dev/null || echo "0")) / 3600 ))" -ge 6 ]]; then
        local LAST_REVIEW=$(cat "$HOME/drift-state/last-review-time" 2>/dev/null || echo "0")
        local HOURS_SINCE=$(( (NOW - LAST_REVIEW) / 3600 ))
        MODEL="opus"
        SESSION_TYPE="planning"
        echo "$NOW" > "$HOME/drift-state/last-review-time"  # Guaranteed update
        log "Sprint planning due (${HOURS_SINCE}h since last) — Opus"

        # Create tracking Issue so Command Center shows planning in progress
        local CYCLE=$(cat "$HOME/drift-state/cycle-counter" 2>/dev/null || echo "?")
        local PLAN_ISSUE=$(gh issue create \
            --title "Sprint Planning — Cycle $CYCLE" \
            --label sprint-task --label SENIOR --label in-progress \
            --body "Automated sprint planning session. Includes: product review, competitive analysis, sprint-task creation, persona updates, roadmap updates." \
            --json number --jq '.number' 2>/dev/null || echo "")
        if [[ -n "$PLAN_ISSUE" ]]; then
            log "Created planning tracking Issue #$PLAN_ISSUE"
            SESSION_PROMPT="run sprint planning — close Issue #$PLAN_ISSUE when done"
        else
            log "Warning: failed to create planning tracking Issue"
            SESSION_PROMPT="run sprint planning"
        fi

    # 2. SENIOR sprint-tasks or P0 bugs? → Opus (alternating with Sonnet)
    else
        local SENIOR=$(gh issue list --state open --label sprint-task --label SENIOR --json number --jq 'length' 2>/dev/null || echo "0")
        local P0=$(gh issue list --state open --label P0 --json number --jq 'length' 2>/dev/null || echo "0")
        local LAST_MODEL=$(cat "$HOME/drift-state/last-model" 2>/dev/null || echo "sonnet")

        if [[ "$SENIOR" -gt 0 ]] || [[ "$P0" -gt 0 ]]; then
            if [[ "$LAST_MODEL" == "opus" ]] && [[ "$P0" -eq 0 ]]; then
                # Opus just ran and no P0s left — give Sonnet a turn
                MODEL="sonnet"
                SESSION_TYPE="junior"
                SESSION_PROMPT="execute junior tasks"
                log "Alternating to Sonnet (${SENIOR} senior, no P0s remaining)"
            else
                MODEL="opus"
                SESSION_TYPE="senior"
                SESSION_PROMPT="execute senior tasks and P0 bugs"
                log "SENIOR/P0 work available (${SENIOR} senior, ${P0} P0) — Opus"
            fi
        else
            # 3. Default: Sonnet always-on (junior tasks + permanent tasks)
            MODEL="sonnet"
            SESSION_TYPE="junior"
            SESSION_PROMPT="execute junior tasks"
            log "No senior/P0 work — Sonnet (always-on)"
        fi
    fi

    echo "$MODEL" > "$HOME/drift-state/last-model"
    echo "$SESSION_TYPE" > "$HOME/drift-state/cache-session-type"
    CURRENT_LOG="$LOG_DIR/session_${SESSION_TYPE}_$(date +%s).log"

    # Check rate limit before starting
    local RATE_MSG=$("$WORK_DIR/scripts/check-rate-limit.sh" 2>/dev/null)
    local RATE_EXIT=$?
    if [[ "$RATE_EXIT" -eq 2 ]]; then
        log "Rate limit critical: $RATE_MSG. Delaying 5 min."
        sleep 300
    elif [[ "$RATE_EXIT" -eq 1 ]]; then
        log "Rate limit warning: $RATE_MSG"
    fi

    # Warm compliance cache before session starts
    refresh_compliance_cache

    log "Starting autopilot ($SESSION_TYPE, model=$MODEL, log: $CURRENT_LOG)"
    cd "$WORK_DIR"

    # Opus gets Sonnet fallback for API overload. Sonnet gets no fallback.
    local FALLBACK=""
    [[ "$MODEL" == "opus" ]] && FALLBACK="--fallback-model sonnet"

    DRIFT_AUTONOMOUS=1 claude -p "$SESSION_PROMPT" \
        --dangerously-skip-permissions \
        --model "$MODEL" \
        $FALLBACK \
        --effort max \
        --output-format stream-json \
        --verbose \
        > "$CURRENT_LOG" 2>&1 &
    CLAUDE_PID=$!
    echo "$CLAUDE_PID" > "$PID_FILE"
    log "Autopilot started with PID $CLAUDE_PID (model=$MODEL)"

    # Start Haiku monitor
    start_monitor
}

is_claude_alive() {
    [[ -n "$CLAUDE_PID" ]] && kill -0 "$CLAUDE_PID" 2>/dev/null
}

is_log_stale() {
    is_log_stale_seconds "$STALE_THRESHOLD"
}

is_log_stale_seconds() {
    local threshold=$1
    if [[ -z "$CURRENT_LOG" ]] || [[ ! -f "$CURRENT_LOG" ]]; then
        return 1  # No log yet, not stale
    fi
    local now
    now=$(date +%s)
    local last_mod
    last_mod=$(stat -f %m "$CURRENT_LOG" 2>/dev/null || echo "$now")
    local age=$(( now - last_mod ))
    (( age > threshold ))
}

cleanup() {
    local state
    state=$(read_control)
    if [[ "$state" == "DRAIN" ]]; then
        log "Watchdog shutting down (signal received) — DRAIN active, leaving claude running."
    else
        log "Watchdog shutting down (signal received)..."
        kill_claude
    fi
    exit 0
}

trap cleanup SIGINT SIGTERM

# Initialize control file if missing
if [[ ! -f "$CONTROL_FILE" ]]; then
    echo "RUN" > "$CONTROL_FILE"
fi

log "========================================="
log "Drift Control watchdog started"
log "Control file: $CONTROL_FILE"
log "Check interval: ${CHECK_INTERVAL}s"
log "========================================="

# Adopt existing claude process from PID file if still alive
if [[ -f "$PID_FILE" ]]; then
    SAVED_PID=$(cat "$PID_FILE")
    if kill -0 "$SAVED_PID" 2>/dev/null; then
        CLAUDE_PID="$SAVED_PID"
        CURRENT_LOG=$(ls -t "$LOG_DIR"/session_*.log 2>/dev/null | head -1)
        log "Adopted existing autopilot (PID $CLAUDE_PID, log: $CURRENT_LOG)"
    else
        log "Stale PID file (PID $SAVED_PID dead). Will start fresh."
        rm -f "$PID_FILE"
    fi
fi

# Initial start
STATE=$(read_control)
if [[ "$STATE" == "RUN" ]]; then
    # Ensure override is CONTINUE
    sed -i '' 's/_Override:_ STOP/_Override:_ CONTINUE/' "$WORK_DIR/program.md" 2>/dev/null || true
    if [[ -z "$CLAUDE_PID" ]]; then
        cleanup_dirty_state
        start_claude
    else
        log "Autopilot already running (adopted). Skipping initial start."
    fi
elif [[ "$STATE" == "PAUSE" ]]; then
    log "Control file says PAUSE — waiting..."
elif [[ "$STATE" == "STOP" ]]; then
    log "Control file says STOP — exiting."
    exit 0
elif [[ "$STATE" == "DRAIN" ]]; then
    log "Control file says DRAIN at startup."
    sed -i '' 's/_Override:_ CONTINUE/_Override:_ STOP/' "$WORK_DIR/program.md" 2>/dev/null || true
    DRAIN_STALE=600
    if is_claude_alive; then
        log "DRAIN: waiting for session to finish (PID $CLAUDE_PID)..."
        while is_claude_alive; do
            sleep 60
            if is_log_stale_seconds "$DRAIN_STALE"; then
                log "DRAIN: no log output in ${DRAIN_STALE}s — killing stalled process."
                kill_claude
                break
            fi
        done
    fi
    log "DRAIN: done. Exiting."
    exit 0
fi

# Main watchdog loop
# Sleep in 30s chunks so we pick up control file changes quickly
# Full health check (stale log, restart) only every CHECK_INTERVAL
ELAPSED=0
while true; do
    sleep 30
    ELAPSED=$(( ELAPSED + 30 ))

    STATE=$(read_control)

    # React to STOP/PAUSE/DRAIN immediately (every 30s)
    if [[ "$STATE" != "RUN" ]]; then
        log "Check cycle — control: $STATE, autopilot PID: ${CLAUDE_PID:-none}"
    fi

    # Skip full health check until CHECK_INTERVAL elapsed
    if [[ "$STATE" == "RUN" ]] && (( ELAPSED < CHECK_INTERVAL )); then
        continue
    fi
    ELAPSED=0

    if [[ "$STATE" == "RUN" ]]; then
        log "Check cycle — control: $STATE, autopilot PID: ${CLAUDE_PID:-none}"
    fi

    case "$STATE" in
        STOP)
            log "STOP requested. Shutting down."
            kill_claude
            exit 0
            ;;
        PAUSE)
            if is_claude_alive; then
                log "PAUSE requested. Setting override and waiting for graceful exit..."
                sed -i '' 's/_Override:_ CONTINUE/_Override:_ STOP/' "$WORK_DIR/program.md" 2>/dev/null || true
                PAUSE_WAIT=0
                PAUSE_TIMEOUT=300
                while is_claude_alive && (( PAUSE_WAIT < PAUSE_TIMEOUT )); do
                    sleep 10
                    (( PAUSE_WAIT += 10 ))
                    if is_log_stale_seconds 120; then
                        log "PAUSE: session stalled (no output in 120s). Force killing."
                        break
                    fi
                done
                if is_claude_alive; then
                    log "PAUSE: graceful timeout (${PAUSE_TIMEOUT}s). Force killing."
                    kill_claude
                else
                    log "PAUSE: session exited gracefully."
                fi
            fi
            log "Paused. Waiting for RUN..."
            continue
            ;;
        DRAIN)
            sed -i '' 's/_Override:_ CONTINUE/_Override:_ STOP/' "$WORK_DIR/program.md" 2>/dev/null || true
            log "DRAIN: set _Override: STOP in program.md"
            if is_claude_alive; then
                log "DRAIN: waiting for session to finish (PID $CLAUDE_PID)..."
                DRAIN_STALE=600
                while is_claude_alive; do
                    sleep 60
                    if is_log_stale_seconds "$DRAIN_STALE"; then
                        log "DRAIN: no log output in ${DRAIN_STALE}s — killing stalled process."
                        kill_claude
                        break
                    fi
                done
                log "DRAIN: session finished. Exiting."
                exit 0
            else
                log "DRAIN: session already finished. Exiting."
                exit 0
            fi
            ;;
        RUN)
            # Ensure override is CONTINUE
            sed -i '' 's/_Override:_ STOP/_Override:_ CONTINUE/' "$WORK_DIR/program.md" 2>/dev/null || true
            # Check if autopilot is dead
            if ! is_claude_alive; then
                stop_monitor
                if [[ -n "$CURRENT_LOG" ]] && grep -q '"type":"result"' "$CURRENT_LOG" 2>/dev/null; then
                    log "Autopilot completed normally. Restarting..."
                    echo "0" > "$CRASH_FILE"
                else
                    local CRASHES=$(cat "$CRASH_FILE" 2>/dev/null || echo "0")
                    CRASHES=$((CRASHES + 1))
                    echo "$CRASHES" > "$CRASH_FILE"
                    log "Autopilot CRASHED (no result event). Crash #$CRASHES. Restarting..."
                    if [[ "$CRASHES" -ge 3 ]]; then
                        log "WARNING: $CRASHES consecutive crashes. Backing off 5 min."
                        sleep 300
                    fi
                fi
                cleanup_dirty_state
                start_claude
            # Check if autopilot is stalled
            elif is_log_stale; then
                log "Autopilot stalled (log not updated in ${STALE_THRESHOLD}s). Restarting..."
                kill_claude
                cleanup_dirty_state
                start_claude
            else
                log "Autopilot running normally (PID $CLAUDE_PID)."
                # Refresh compliance cache for the PreToolUse hook to read
                refresh_compliance_cache
            fi
            ;;
        *)
            log "Unknown control state: $STATE — treating as RUN"
            ;;
    esac
done
