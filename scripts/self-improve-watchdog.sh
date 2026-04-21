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
CHECK_INTERVAL=60   # 1 minute — heartbeat: sprint refresh + health check
STALE_THRESHOLD=600  # 10 minutes — no log output = definitely dead
# Per-session stall thresholds (no commits/progress before nudge)
STALL_PLANNING=3600  # 1 hour
STALL_SENIOR=1800    # 30 minutes
STALL_JUNIOR=1800    # 30 minutes
NUDGE_WAIT=300       # 5 minutes after nudge before killing
# Commit-rate stall: senior/junior that has produced 0 commits to main this long = stuck
COMMIT_STALL=10800   # 3 hours — genuinely-hard bugs sometimes take this long, but 0 commits past this is a tarpit
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

get_model() {
    local SESSION_TYPE="$1"
    local DEFAULT="$2"
    local CONFIG="$HOME/drift-state/model-config"
    if [[ -f "$CONFIG" ]]; then
        local OVERRIDE=$(grep "^${SESSION_TYPE}=" "$CONFIG" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
        [[ -n "$OVERRIDE" ]] && echo "$OVERRIDE" && return
    fi
    echo "$DEFAULT"
}

read_control() {
    if [[ -f "$CONTROL_FILE" ]]; then
        tr -d '[:space:]' < "$CONTROL_FILE" | tr '[:lower:]' '[:upper:]'
    else
        echo "RUN"
    fi
}

run_compliance() {
    local EXIT_REASON="${1:-normal}"  # normal | crash | stall
    local COMP_TYPE
    COMP_TYPE=$(cat "$HOME/drift-state/cache-session-type" 2>/dev/null || echo "unknown")
    local COMP_MODEL
    COMP_MODEL=$(cat "$HOME/drift-state/last-model" 2>/dev/null || echo "unknown")
    "$WORK_DIR/scripts/session-compliance.sh" "$COMP_TYPE" "$COMP_MODEL" "$EXIT_REASON" 2>/dev/null || true
    log "Session compliance: $COMP_TYPE ($COMP_MODEL, $EXIT_REASON)"
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
    # Sprint service atomically clears all in-progress (state file + GitHub labels)
    "$WORK_DIR/scripts/sprint-service.sh" clear 2>/dev/null || true
    log "Sprint service: cleared in-progress state"

    # Remove stale TestFlight authorization — a crashed session may have left this set
    # without completing the publish. Next session gets a fresh authorization flow.
    rm -f "$HOME/drift-state/testflight-publish-authorized"
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

MONITOR_PID_FILE="$LOG_DIR/monitor.pid"

start_monitor() {
    stop_monitor
    local ISSUE_NUM=$(cat "$HOME/drift-state/live-status-issue" 2>/dev/null || echo "")
    if [[ -z "$ISSUE_NUM" ]] || ! gh issue view "$ISSUE_NUM" --json state --jq '.state' 2>/dev/null | grep -q "OPEN"; then
        ISSUE_NUM=$(gh issue create --title "Drift Live Status" --label live-status --body "Starting..." --json number --jq '.number' 2>/dev/null || echo "")
        [[ -n "$ISSUE_NUM" ]] && echo "$ISSUE_NUM" > "$HOME/drift-state/live-status-issue"
    fi
    if [[ -n "$ISSUE_NUM" ]] && [[ -n "$CURRENT_LOG" ]]; then
        "$WORK_DIR/scripts/session-monitor.sh" "$CURRENT_LOG" "$ISSUE_NUM" &
        MONITOR_PID=$!
        echo "$MONITOR_PID" > "$MONITOR_PID_FILE"
        log "Monitor started (PID $MONITOR_PID, issue #$ISSUE_NUM)"
    fi
}

stop_monitor() {
    # Kill by PID variable first, then by PID file (survives watchdog restart)
    if [[ -n "$MONITOR_PID" ]] && kill -0 "$MONITOR_PID" 2>/dev/null; then
        kill "$MONITOR_PID" 2>/dev/null || true
    fi
    local SAVED_PID=$(cat "$MONITOR_PID_FILE" 2>/dev/null || echo "")
    if [[ -n "$SAVED_PID" ]] && kill -0 "$SAVED_PID" 2>/dev/null; then
        kill "$SAVED_PID" 2>/dev/null || true
    fi
    # Also kill any orphaned monitors
    pkill -f "session-monitor.sh" 2>/dev/null || true
    MONITOR_PID=""
    rm -f "$MONITOR_PID_FILE"
}

refresh_compliance_cache() {
    local SD="$HOME/drift-state"
    cd "$WORK_DIR"

    # P0 bugs (all sessions care)
    gh issue list --state open --label P0 --json number,title \
        --jq '.[] | "#\(.number) \(.title)"' > "$SD/cache-p0-bugs" 2>/dev/null || true

    # Open bugs with screenshots (all sessions — must view before fixing)
    gh issue list --state open --label bug --json number,title,body \
        --jq '[.[] | select(.body | test("!\\["))] | .[] | "#\(.number) \(.title) — HAS SCREENSHOT"' \
        > "$SD/cache-bugs-with-screenshots" 2>/dev/null || true

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

    # Design docs awaiting approval (doc-ready but NOT approved — DO NOT IMPLEMENT)
    gh issue list --state open --label design-doc --label doc-ready --json number,title,labels \
        --jq '[.[] | select(.labels | map(.name) | index("approved") | not)] | .[] | "#\(.number) \(.title)"' \
        > "$SD/cache-awaiting-approval" 2>/dev/null || true

    # Approved design docs NOT yet implementing (need task creation first)
    gh issue list --state open --label design-doc --label approved --json number,title,labels \
        --jq '[.[] | select(.labels | map(.name) | index("implementing") | not)] | .[] | "#\(.number) \(.title)"' \
        > "$SD/cache-approved-designs" 2>/dev/null || true

    # In-progress issues (for mark-in-progress hook to detect stale ones)
    gh issue list --state open --label in-progress --json number \
        --jq '.[].number' > "$SD/cache-in-progress" 2>/dev/null || true

    # Product focus
    gh issue list --state open --label product-focus --json body \
        --jq '.[0].body // empty' | head -1 > "$SD/cache-product-focus" 2>/dev/null || true
}

start_claude() {
    local MODEL="sonnet"
    local SESSION_TYPE="junior"
    local SESSION_PROMPT="$PROMPT"

    # Refresh sprint state (single source of truth for session type)
    log "Refreshing sprint state..."
    "$WORK_DIR/scripts/sprint-service.sh" refresh 2>/dev/null || log "Warning: sprint-service refresh failed, using stale state"

    # 0. Resume interrupted planning session (crash recovery — takes priority over all routing)
    local EXISTING_PLAN
    EXISTING_PLAN=$(cat "$HOME/drift-state/planning-issue" 2>/dev/null | tr -d '[:space:]' || true)
    if [[ -n "$EXISTING_PLAN" ]]; then
        local PLAN_STATE
        PLAN_STATE=$(gh issue view "$EXISTING_PLAN" --json state --jq '.state' 2>/dev/null || echo "CLOSED")
        if [[ "$PLAN_STATE" == "OPEN" ]]; then
            MODEL=$(get_model planning opus)
            SESSION_TYPE="planning"
            SESSION_PROMPT="run sprint planning — close Issue #$EXISTING_PLAN when done"
            log "Resuming interrupted planning (Issue #$EXISTING_PLAN) — $MODEL"
        fi
    fi

    if [[ "$SESSION_TYPE" != "planning" ]]; then
    # 1. Planning due?
    if "$WORK_DIR/scripts/sprint-service.sh" planning-due 2>/dev/null; then
        MODEL=$(get_model planning opus)
        SESSION_TYPE="planning"
        # NOTE: last-review-time is stamped by `report-service.sh finish` when a
        # product-review branch is actually merged — NOT here. Writing it at
        # session spawn made `cmd_review_due` believe a review was done every
        # time a planner started, and reviews silently stopped getting written
        # (710-cycle gap observed 2026-04-21).
        log "Sprint planning due — $MODEL"

        local CYCLE=$(cat "$HOME/drift-state/cycle-counter" 2>/dev/null || echo "?")
        rm -f "$HOME/drift-state/planning-issue"
        local PLAN_ISSUE=$(gh issue create \
            --title "Sprint Planning — Cycle $CYCLE" \
            --label planning --label SENIOR --label in-progress \
            --body "## Planning Checklist
- [ ] Feedback drained — process-feedback.log reviewed, infra issues created
- [ ] Admin replies — responded to all admin comments on report PRs
- [ ] Product review — review-cycle-${CYCLE}.md PR merged to main
- [ ] Sprint tasks — 8+ sprint-task issues created
- [ ] Personas updated — appended \"What I learned\" to persona files
- [ ] Roadmap updated — applied agreed changes
- [ ] Sprint refreshed — scripts/sprint-service.sh refresh called" \
            --json number --jq '.number' 2>/dev/null || echo "")
        if [[ -n "$PLAN_ISSUE" ]]; then
            log "Created planning tracking Issue #$PLAN_ISSUE"
            echo "$PLAN_ISSUE" > "$HOME/drift-state/planning-issue"
            SESSION_PROMPT="run sprint planning — close Issue #$PLAN_ISSUE when done"
        else
            SESSION_PROMPT="run sprint planning"
        fi

    # 2. P0s, SENIOR tasks, or unhandled P1/P2 bugs? → senior session
    elif [[ "$("$WORK_DIR/scripts/sprint-service.sh" count --p0 2>/dev/null || echo 0)" -gt 0 ]] || \
         [[ "$("$WORK_DIR/scripts/sprint-service.sh" count --senior 2>/dev/null || echo 0)" -gt 0 ]] || \
         [[ "$("$WORK_DIR/scripts/sprint-service.sh" count --bugs 2>/dev/null || echo 0)" -gt 0 ]]; then
        MODEL=$(get_model senior opus)
        SESSION_TYPE="senior"
        SESSION_PROMPT="execute senior tasks and P0 bugs"
        log "P0/SENIOR/bug work available — $MODEL"

    # 3. Default: junior (sprint tasks → permanent tasks as fallback, 5-task budget enforced)
    else
        MODEL=$(get_model junior sonnet)
        SESSION_TYPE="junior"
        SESSION_PROMPT="execute junior tasks"
        log "No P0/SENIOR work — junior ($MODEL)"
    fi
    fi  # end if not resuming planning

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

    # Refresh compliance cache (P0 cache used by compliance-check.sh hook)
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
        --disallowedTools advisor \
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
                run_compliance "stall"
                cleanup_dirty_state
                log "DRAIN: done. Exiting."
                exit 0
            fi
        done
        # Session finished naturally — check log for crash vs normal exit
        if [[ -n "$CURRENT_LOG" ]] && grep -q '"type":"result"' "$CURRENT_LOG" 2>/dev/null; then
            run_compliance "normal"
        else
            run_compliance "crash"
        fi
    fi
    cleanup_dirty_state
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
                PAUSE_TIMEOUT=900
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
                        run_compliance "stall"
                        cleanup_dirty_state
                        log "DRAIN: killed stalled session. Exiting."
                        exit 0
                    fi
                done
                # Session finished naturally
                run_compliance "normal"
                cleanup_dirty_state
            else
                log "DRAIN: session already finished."
                cleanup_dirty_state
            fi
            log "DRAIN: done. Exiting."
            exit 0
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
                    run_compliance "normal"
                else
                        CRASHES=$(cat "$CRASH_FILE" 2>/dev/null || echo "0")
                    CRASHES=$((CRASHES + 1))
                    echo "$CRASHES" > "$CRASH_FILE"
                    log "Autopilot CRASHED (no result event). Crash #$CRASHES. Restarting..."
                    run_compliance "crash"
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
                run_compliance "stall"
                cleanup_dirty_state
                start_claude
            else
                log "Autopilot running normally (PID $CLAUDE_PID)."
                # Refresh sprint state + compliance cache every heartbeat
                "$WORK_DIR/scripts/sprint-service.sh" refresh 2>/dev/null || true
                refresh_compliance_cache

                # Mark TestFlight due when 3h elapsed — hook publishes on next commit
                _TF_LAST=$(cat "$HOME/drift-state/last-testflight-publish" 2>/dev/null || echo "0")
                _TF_ELAPSED=$(( $(date +%s) - _TF_LAST ))
                if [[ "$_TF_ELAPSED" -ge 10800 ]] && [[ ! -f "$HOME/drift-state/testflight-due" ]]; then
                    echo "$(date +%s)" > "$HOME/drift-state/testflight-due"
                    log "TestFlight publish due (${_TF_ELAPSED}s since last) — marked for next commit"
                fi

                # Check per-session stall threshold (no commits/progress)
                # Nudge first, then kill after NUDGE_WAIT seconds
                CURRENT_TYPE=$(cat "$HOME/drift-state/cache-session-type" 2>/dev/null || echo "junior")
                case "$CURRENT_TYPE" in
                    planning) SESSION_STALL=$STALL_PLANNING ;;
                    senior)   SESSION_STALL=$STALL_SENIOR ;;
                    *)        SESSION_STALL=$STALL_JUNIOR ;;
                esac
                NUDGE_FILE="$HOME/drift-state/watchdog-nudge-${CLAUDE_PID}"
                if is_log_stale_seconds "$SESSION_STALL"; then
                    if [[ ! -f "$NUDGE_FILE" ]]; then
                        log "Session appears stalled (no output in ${SESSION_STALL}s, type=$CURRENT_TYPE) — giving ${NUDGE_WAIT}s before restart."
                        touch "$NUDGE_FILE"
                    elif is_log_stale_seconds $(( SESSION_STALL + NUDGE_WAIT )); then
                        log "Session still stalled after nudge window — killing and restarting."
                        rm -f "$NUDGE_FILE"
                        kill_claude
                        run_compliance "stall"
                        cleanup_dirty_state
                        start_claude
                    else
                        log "Nudge window active — waiting for session to respond (type=$CURRENT_TYPE)."
                    fi
                else
                    rm -f "$NUDGE_FILE" 2>/dev/null || true
                fi

                # Commit-rate stall: busy-but-unproductive sessions (tool calls but no
                # shipped work). Planning sessions exempt — they create issues, not commits.
                # Only kicks in after COMMIT_STALL (3h) so genuinely hard bug hunts still finish.
                if [[ "$CURRENT_TYPE" != "planning" ]] && [[ -n "$CURRENT_LOG" ]] && [[ -f "$CURRENT_LOG" ]]; then
                    # Log filename is session_{type}_{epoch}.log
                    SESSION_EPOCH=$(basename "$CURRENT_LOG" | sed -E 's/^session_[a-z]+_([0-9]+)\.log$/\1/')
                    if [[ "$SESSION_EPOCH" =~ ^[0-9]+$ ]]; then
                        SESSION_AGE=$(( $(date +%s) - SESSION_EPOCH ))
                        if (( SESSION_AGE > COMMIT_STALL )); then
                            COMMITS_SINCE_START=$(cd "$WORK_DIR" && git log --oneline --since="@$SESSION_EPOCH" main 2>/dev/null | wc -l | tr -d ' ')
                            if [[ "$COMMITS_SINCE_START" == "0" ]]; then
                                log "PRODUCTIVITY STALL: $CURRENT_TYPE session age ${SESSION_AGE}s, 0 commits since start. Killing for fresh restart."
                                kill_claude
                                run_compliance "stall"
                                cleanup_dirty_state
                                start_claude
                            fi
                        fi
                    fi
                fi
            fi
            ;;
        *)
            log "Unknown control state: $STATE — treating as RUN"
            ;;
    esac
done
