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

# shellcheck source=lib/atomic-write.sh
source "$(dirname "$0")/lib/atomic-write.sh"

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
# Bumped 1800→3600 (2026-05-06): the 30-min threshold was killing genuinely
# productive deep investigation. Issue #641 alone burned 3 senior sessions
# because each stalled at 30 min mid-trace. 60 min is generous enough that
# only truly-hung sessions trip it. Combined with snapshot_orphan_wip(),
# even sessions that DO trip it leave a recoverable diff for the next.
STALE_THRESHOLD=3600  # 60 minutes — no heartbeat/log output = definitely dead
# Per-session stall thresholds (no commits/progress before nudge)
STALL_PLANNING=3600  # 1 hour
STALL_SENIOR=3600    # 1 hour (was 30 min — see STALE_THRESHOLD note)
STALL_JUNIOR=3600    # 1 hour
NUDGE_WAIT=300       # 5 minutes after nudge before killing
# Commit-rate stall: senior/junior that has produced 0 commits to main this long = stuck
COMMIT_STALL=10800   # 3 hours — genuinely-hard bugs sometimes take this long, but 0 commits past this is a tarpit
KILL_WAIT=10
CRASH_FILE="$HOME/drift-state/consecutive-crashes"
# Stable-run reset threshold (gbrain supervisor.ts pattern): if a session was
# alive for this long before crashing, treat it as a transient flake and
# reset the consecutive-crashes counter to 0. Prevents the "5-min flap" mode
# where 5 long-stable runs that each happened to crash at the end get
# escalated as if it were a broken config.
STABLE_RUN_THRESHOLD=300
# External-kill grace window. If `is_claude_alive` flips false but the
# session-heartbeat / log mtime is fresh within this many seconds, the
# death was almost certainly an external kill (launchctl kickstart, OOM
# killer, manual `kill`) rather than a real session crash. The watchdog
# logs it as such and does NOT increment the consecutive-crashes
# counter. Tunable per-host: LIVENESS_FRESH_SECONDS=N watchdog
LIVENESS_FRESH_SECONDS=${LIVENESS_FRESH_SECONDS:-60}
MONITOR_PID=""

PROMPT="run autopilot"
CLAUDE_PID=""
SESSION_STARTED_AT=0
CURRENT_LOG=""

mkdir -p "$LOG_DIR"

# Ignore SIGPIPE — observed root cause of recurring watchdog deaths. Without
# this, any pipeline that loses its reader (file rotation, launchd stdout
# buffer issue, etc.) propagates SIGPIPE to the watchdog shell and bash exits
# with 141. Each watchdog death triggers its own signal handler which kills
# the active senior session — that's the "sessions dying every 2 min"
# pattern observed 2026-04-28 (5 watchdog respawns / hour).
trap '' PIPE

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    # Direct writes — no `tee` pipeline. Was: `echo "$msg" | tee -a "$LOG"`.
    # The pipeline was the SIGPIPE vector: launchd captures stdout into a
    # rotated file, and an unfortunate combination of buffering + rotation
    # would close tee's stdout reader, propagate SIGPIPE up to the script,
    # and kill the watchdog mid-cycle.
    echo "$msg" >> "$WATCHDOG_LOG"
    echo "$msg"
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

# Phase 3c 2026-05-26: helper for staleness-driven session bands. Returns 0
# (true) when STAMP_FILE is missing or its mtime is older than $AGE_SECONDS.
# Used by the watchdog decision tree to fire /knowledge-curate when 7d
# stale or /admin-replies when 24h stale, instead of bundling those in the
# heavy /planning session.
_is_stale() {
    local STAMP_FILE="$1"
    local AGE_SECONDS="$2"
    if [[ ! -f "$STAMP_FILE" ]]; then return 0; fi
    local LAST_MTIME NOW AGE
    LAST_MTIME=$(stat -f %m "$STAMP_FILE" 2>/dev/null || stat -c %Y "$STAMP_FILE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    AGE=$(( NOW - LAST_MTIME ))
    [[ "$AGE" -ge "$AGE_SECONDS" ]]
}

# Phase 3c 2026-05-26: count open epic issues for the stuck-epic cap.
# Under strict-one-epic, planning should not fire while a prior epic is
# still open. The cap (2 cycles stuck) is enforced at the planning-due
# branch — see the planning-due check below. Returns the count via stdout
# so the caller can decide.
_count_open_epics() {
    gh issue list --state open --label epic --json number --jq length 2>/dev/null || echo 0
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
    # Copy session log to /tmp/planning-crash-log.txt for post-mortem (planning crashes only)
    if [[ "$EXIT_REASON" == "crash" || "$EXIT_REASON" == "stall" ]] && [[ -n "$CURRENT_LOG" ]] && [[ -f "$CURRENT_LOG" ]]; then
        cp "$CURRENT_LOG" "/tmp/planning-crash-log.txt" 2>/dev/null || true
        log "Crash log saved to /tmp/planning-crash-log.txt"
    fi
    "$WORK_DIR/scripts/session-compliance.sh" "$COMP_TYPE" "$COMP_MODEL" "$EXIT_REASON" 2>/dev/null || true
    log "Session compliance: $COMP_TYPE ($COMP_MODEL, $EXIT_REASON)"
}

snapshot_orphan_wip() {
    # Capture dirty state for an UNCLAIMED session before cleanup discards it.
    # Distinct from snapshot_wip_if_in_progress (which only fires when a claim
    # is active). Investigation work on issue #641 burned 3+ sessions because
    # each stall triggered `git checkout .` and the next session restarted
    # from zero. Save the orphan diff so the next senior can `git apply` it
    # and continue, even though the issue number isn't known.
    local SD="$HOME/drift-state"
    cd "$WORK_DIR" || return
    local REAL_EDITS
    REAL_EDITS=$(git status --porcelain 2>/dev/null \
        | { grep -vE 'command-center/heartbeat\.json|graphify-out/|\.xcodeproj/' || true; } \
        | wc -l | tr -d ' ')
    [[ "$REAL_EDITS" -eq 0 ]] && return

    mkdir -p "$SD/wip"
    local STAMP
    STAMP=$(date -u +%Y%m%dT%H%M%SZ)
    local PATCH="$SD/wip/orphan-${STAMP}.patch"
    git diff HEAD --binary > "${PATCH}.tmp" 2>/dev/null
    mv "${PATCH}.tmp" "$PATCH"

    local UNTRACKED
    UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null \
        | grep -vE 'command-center/heartbeat\.json|graphify-out/|\.xcodeproj/' || true)
    if [[ -n "$UNTRACKED" ]]; then
        echo "$UNTRACKED" | tar -czf "$SD/wip/orphan-${STAMP}.untracked.tar.gz.tmp" -T - 2>/dev/null
        mv "$SD/wip/orphan-${STAMP}.untracked.tar.gz.tmp" "$SD/wip/orphan-${STAMP}.untracked.tar.gz"
    fi

    # Newest-orphan symlink for easy discovery by next session-start.
    ln -sf "orphan-${STAMP}.patch" "$SD/wip/last-orphan.patch"

    log "Orphan WIP saved: $PATCH (${REAL_EDITS} dirty file(s)). Next session can: git apply $PATCH"
}

cleanup_dirty_state() {
    cd "$WORK_DIR"
    # Abort interrupted merges/rebases
    git merge --abort 2>/dev/null || true
    git rebase --abort 2>/dev/null || true
    # Drop stashes left by crashed sessions
    git stash drop 2>/dev/null || true

    # Fix B: stale-branch sweep. If the prior session crashed mid-report-flow
    # (review/cycle-N or report/exec-DATE branch was created, work was done,
    # but `report-service.sh finish` never ran to switch back), HEAD is left
    # on the feature branch. Operator-mode sessions then accidentally land
    # commits on the stale branch instead of main. Switch back proactively.
    local CURRENT_BRANCH
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
    if [[ -n "$CURRENT_BRANCH" && "$CURRENT_BRANCH" != "main" ]]; then
        log "Stale branch: HEAD on $CURRENT_BRANCH (probably from a crashed report flow). Switching back to main."
        git checkout main 2>/dev/null || true
        git pull --ff-only origin main 2>/dev/null || true
    fi

    local DIRTY=$(git status --porcelain 2>/dev/null | head -20)
    if [[ -n "$DIRTY" ]]; then
        log "Dirty state after session exit. Discarding incomplete changes:"
        log "$DIRTY"
        # Save orphan WIP first — git checkout below would otherwise discard
        # legitimate investigation work for sessions that died before claim.
        snapshot_orphan_wip
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

    # Fix C: orphan WIP patch sweep. snapshot_wip_if_in_progress only cleans
    # patches when the current claim's tree goes empty. Patches for issues
    # that closed via `gh issue close` (bypassing cmd_done) or via watchdog
    # reconcile, OR claims that got unclaimed before commit, leak forever.
    # Observed 2026-04-28: 345.patch lingered for hours after #345 was
    # unclaimed without going through cmd_done. Sweep at startup: any patch
    # whose issue is closed → delete; any patch >7 days old → delete.
    local WIP_DIR="$HOME/drift-state/wip"
    if [[ -d "$WIP_DIR" ]]; then
        local now_ts
        now_ts=$(date +%s)
        for patch in "$WIP_DIR"/*.patch; do
            [[ -f "$patch" ]] || continue
            local num
            num=$(basename "$patch" .patch)
            [[ "$num" =~ ^[0-9]+$ ]] || continue
            local age_days
            age_days=$(( (now_ts - $(stat -f %m "$patch" 2>/dev/null || echo "$now_ts")) / 86400 ))
            if [[ "$age_days" -gt 7 ]]; then
                log "WIP cleanup: $patch is ${age_days}d old, removing."
                rm -f "$patch" "$WIP_DIR/${num}.untracked.tar.gz"
                continue
            fi
            local issue_state
            issue_state=$(gh issue view "$num" --json state --jq '.state' 2>/dev/null || echo "")
            if [[ "$issue_state" == "CLOSED" ]]; then
                log "WIP cleanup: #$num is CLOSED, removing $patch."
                rm -f "$patch" "$WIP_DIR/${num}.untracked.tar.gz"
            fi
        done
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

MONITOR_PID_FILE="$LOG_DIR/monitor.pid"

start_monitor() {
    stop_monitor
    local ISSUE_NUM=$(cat "$HOME/drift-state/live-status-issue" 2>/dev/null || echo "")
    if [[ -z "$ISSUE_NUM" ]] || ! gh issue view "$ISSUE_NUM" --json state --jq '.state' 2>/dev/null | grep -q "OPEN"; then
        local CREATE_OUT
        CREATE_OUT=$(gh issue create --title "Drift Live Status" --label live-status --body "Starting..." 2>/dev/null || echo "")
        ISSUE_NUM=$(echo "$CREATE_OUT" | grep -oE 'issues/[0-9]+' | grep -oE '[0-9]+' | tail -1 || echo "")
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

# Reconcile cadence stamps against what actually shipped on main. The
# planning/review/report gates all key off these stamps; a session that
# merges without going through the service script leaves its stamp stale
# and the gate fires forever. Idempotent — only bumps a stamp forward.
sync_stamps_from_main() {
    cd "$WORK_DIR" || return
    local SD="$HOME/drift-state"

    # Most recent review cycle merge → last-review-time
    local review_last
    review_last=$(git log origin/main --format='%ct' --grep='^review-cycle-' -1 2>/dev/null || echo "")
    if [[ -n "$review_last" ]]; then
        local review_stamp
        review_stamp=$(cat "$SD/last-review-time" 2>/dev/null || echo "0")
        if (( review_last > review_stamp )); then
            atomic_write "$SD/last-review-time" "$review_last"
            log "Self-heal: bumped last-review-time $review_stamp → $review_last (from merged review commit)"
        fi
    fi

    # Self-heal last-review-cycle (telemetry only as of cycle 10950 — the actual
    # review trigger is now wall-clock via last-review-time, not cycle count).
    # We still stamp this so the "cycles since last review" telemetry in
    # planning-context / exec briefings reads as a recent number instead of "47
    # cycles since cycle 0" on a fresh state.
    local cycle_now
    cycle_now=$(cat "$SD/cycle-counter" 2>/dev/null || echo "0")
    if [[ ! -s "$SD/last-review-cycle" ]] && (( cycle_now > 0 )); then
        atomic_write "$SD/last-review-cycle" "$cycle_now"
        log "Self-heal: stamped last-review-cycle = $cycle_now (telemetry only — wall-clock trigger lives on last-review-time)"
    fi

    # Most recent exec report merge → last-report-time. Matches the squash-
    # merge subject `Daily Briefing — YYYY-MM-DD` (with optional `chore:` prefix)
    # plus the legacy `report/exec-` merge-commit form.
    local exec_last
    exec_last=$(git log origin/main --format='%ct' --grep='Daily Briefing\|report/exec-' -1 2>/dev/null || echo "")
    if [[ -n "$exec_last" ]]; then
        local exec_stamp
        exec_stamp=$(cat "$SD/last-report-time" 2>/dev/null || echo "0")
        if (( exec_last > exec_stamp )); then
            atomic_write "$SD/last-report-time" "$exec_last"
            log "Self-heal: bumped last-report-time $exec_stamp → $exec_last (from merged exec commit)"
        fi
    fi

    # Planning issue closed since we last checked → last-planning-time
    local plan_issue
    plan_issue=$(cat "$SD/planning-issue" 2>/dev/null || echo "")
    if [[ -n "$plan_issue" ]]; then
        local plan_state
        plan_state=$(gh issue view "$plan_issue" --json state --jq '.state' 2>/dev/null || echo "")
        if [[ "$plan_state" == "CLOSED" ]]; then
            atomic_write "$SD/last-planning-time" "$(date +%s)"
            rm -f "$SD/planning-issue" "$SD/planning-resume-count-$plan_issue"
            log "Self-heal: planning Issue #$plan_issue is CLOSED — stamped last-planning-time and cleared tracking file"
        fi
    fi

    # Most recent TestFlight build commit → last-testflight-publish. Same
    # pattern as review/exec — the hook's step-5a stamp is fragile, we
    # derive from git instead.
    local tf_last
    tf_last=$(git log origin/main --format='%ct' --grep='^chore: TestFlight build' -1 2>/dev/null || echo "")
    if [[ -n "$tf_last" ]]; then
        local tf_stamp
        tf_stamp=$(cat "$SD/last-testflight-publish" 2>/dev/null || echo "0")
        if (( tf_last > tf_stamp )); then
            atomic_write "$SD/last-testflight-publish" "$tf_last"
            log "Self-heal: bumped last-testflight-publish $tf_stamp → $tf_last (from TestFlight commit)"
        fi
    fi
}

# Reconcile sprint-state.json against GitHub. If our local in_progress slot
# points to a task that's already CLOSED on GitHub, the session closed it
# without calling sprint-service.sh done — the slot stays stuck, blocking
# the next claim. Running `done` again is safe (idempotent on comment/close/
# label strip) and also applies the budget increment we missed.
reconcile_in_progress() {
    local SD="$HOME/drift-state"
    local STATE_FILE="$SD/sprint-state.json"
    [[ -f "$STATE_FILE" ]] || return
    local IN_PROGRESS
    IN_PROGRESS=$(jq -r '.in_progress // empty' "$STATE_FILE" 2>/dev/null || echo "")
    [[ -z "$IN_PROGRESS" || "$IN_PROGRESS" == "null" ]] && return

    local STATE
    STATE=$(gh issue view "$IN_PROGRESS" --json state --jq '.state' 2>/dev/null || echo "")
    if [[ "$STATE" == "CLOSED" ]]; then
        log "Self-heal: in_progress #$IN_PROGRESS is CLOSED on GitHub — reconciling via done"
        "$WORK_DIR/scripts/sprint-service.sh" done "$IN_PROGRESS" "reconcile" >/dev/null 2>&1 || true
    fi
}

# Stale-claim detection — flag issues claimed >threshold ago with no progress.
#
# "Progress" = either a commit referencing #N in its message, or any new
# comment on the issue, both since claim_started. If neither happened in
# the last hour (default), the claim is presumed stuck — auto-flag the
# issue with `needs-review` (which excludes it from `next --senior/junior`),
# comment, and unclaim locally so the next session can move on.
#
# Solves two failure modes:
#   1. Sessions getting stuck on impossible tasks (e.g. #469 telemetry
#      analysis with no telemetry). They thrash for an hour, get flagged,
#      human reviews, closes as wontfix.
#   2. Hung/wandering sessions that bypass the claim hook somehow — no
#      commits, no comments, just exploration → flagged.
#
# Threshold: DRIFT_CLAIM_STALE_THRESHOLD_SECS env var, default 5400 (90 min).
# Was 3600 (60 min) — bumped after #426 false-positive: session shipped 7
# real edits over 60 min, hit Anthropic API stream timeout right at the 1h
# mark, never committed, got auto-flagged at 61 min. Complex senior tasks
# (multi-file refactor, new tool with tests) legitimately need 60-90 min
# before first commit. The 90-min threshold gives breathing room while
# still catching genuinely stuck claims within 1.5h.
check_stale_claim() {
    local SD="$HOME/drift-state"
    local STATE_FILE="$SD/sprint-state.json"
    [[ -f "$STATE_FILE" ]] || return

    local NUM CLAIM_TS
    NUM=$(jq -r '.in_progress // empty' "$STATE_FILE" 2>/dev/null || echo "")
    [[ -z "$NUM" || "$NUM" == "null" ]] && return
    CLAIM_TS=$(jq -r '.claim_started // empty' "$STATE_FILE" 2>/dev/null || echo "")
    [[ -z "$CLAIM_TS" || "$CLAIM_TS" == "null" ]] && return  # legacy claim, skip

    local NOW AGE THRESHOLD
    NOW=$(date +%s)
    AGE=$(( NOW - CLAIM_TS ))
    THRESHOLD=${DRIFT_CLAIM_STALE_THRESHOLD_SECS:-5400}
    (( AGE < THRESHOLD )) && return

    # Any commit referencing #N in its message since claim_started?
    local COMMITS
    COMMITS=$(cd "$WORK_DIR" && git log --since="@$CLAIM_TS" --grep="#$NUM" --oneline 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$COMMITS" -gt 0 ]]; then
        return
    fi

    # Any real edits in the working tree? — third progress signal alongside
    # commits + comments. A session 60 min into a multi-file change with no
    # commit yet should not be flagged. Filter out auto-managed paths so
    # heartbeat/graphify churn alone doesn't count as progress (those run
    # in the watchdog itself, unrelated to session work).
    # Bug history: #426 + #418 both lost real work because the auto-flag
    # fired despite legitimate file edits sitting in the working tree.
    local REAL_EDITS
    REAL_EDITS=$(cd "$WORK_DIR" && git status --porcelain 2>/dev/null \
        | grep -vE 'command-center/heartbeat\.json|graphify-out/|\.xcodeproj/' \
        | wc -l | tr -d ' ')
    if [[ "$REAL_EDITS" -gt 0 ]]; then
        return
    fi

    # Any new comment on the issue since claim_started? (RFC3339 → epoch via python)
    local LATEST_COMMENT_TS
    LATEST_COMMENT_TS=$(gh issue view "$NUM" --json comments \
        --jq '[.comments[].createdAt] | sort | last // ""' 2>/dev/null \
        | python3 -c "
import sys
from datetime import datetime
s = sys.stdin.read().strip().strip('\"')
if not s: print(0); sys.exit()
try:
    print(int(datetime.fromisoformat(s.replace('Z','+00:00')).timestamp()))
except Exception:
    print(0)
" 2>/dev/null || echo "0")
    if [[ "$LATEST_COMMENT_TS" -gt "$CLAIM_TS" ]]; then
        return
    fi

    # Stale — flag it. `needs-review` is the only label needed: it gates
    # next --senior/junior so the queue stops returning this issue, and
    # signals "human, look at this" semantically. Earlier version also
    # added `blocked` but that was redundant decoration AND created an
    # atomicity bug — `gh issue edit --add-label X --add-label Y` is
    # atomic, so when `blocked` didn't exist in the repo the whole call
    # failed silently and `needs-review` never landed. (Observed 2026-04-26
    # on #449: 7 auto-flag attempts in 10h, none actually labeled.)
    log "Stale-claim: #$NUM claimed ${AGE}s ago (threshold ${THRESHOLD}s), no commits referencing #$NUM, no new comments. Auto-flagging."
    if ! gh issue edit "$NUM" --add-label needs-review 2>>"$HOME/drift-state/gh-errors.log"; then
        log "Stale-claim: WARN — failed to add needs-review label on #$NUM (see gh-errors.log)"
    fi
    gh issue comment "$NUM" --body "Auto-flagged stale claim — claimed for ${AGE}s with no commits referencing #${NUM} and no new activity. Review and unblock, close, or reassign." >/dev/null 2>&1 || true
    "$WORK_DIR/scripts/sprint-service.sh" unclaim "$NUM" >/dev/null 2>&1 || true
}

# Periodic WIP snapshot — every tick, if there's a claimed issue and the
# working tree has real edits, save the current diff to
# ~/drift-state/wip/<N>.patch (overwrite). On crash, session-compliance
# reads this file to label the issue resumable + post the recovery path.
# On clean exit (cmd_done), sprint-service.sh deletes the patch. Keeps
# WIP recoverable to within ~30 sec without git branch ceremony.
snapshot_wip_if_in_progress() {
    local SD="$HOME/drift-state"
    local STATE_FILE="$SD/sprint-state.json"
    [[ -f "$STATE_FILE" ]] || return

    local NUM
    NUM=$(jq -r '.in_progress // empty' "$STATE_FILE" 2>/dev/null || echo "")
    [[ -z "$NUM" || "$NUM" == "null" ]] && return

    # Design-doc work has no working-tree state to snapshot — the deliverable
    # is a PR with the doc, not local edits. Skip WIP capture entirely.
    # Also avoids the path-with-slash bug ("design/561" → wip/design/561.patch
    # whose subdir wasn't mkdir'd) that crash-looped the watchdog on 2026-05-01.
    [[ "$NUM" == */* ]] && return

    cd "$WORK_DIR" || return
    local REAL_EDITS
    # Tame grep's exit-1-on-no-match (which would propagate through pipefail
    # and kill the watchdog) by wrapping grep specifically with `|| true`.
    # Earlier defensive wrap `{ ... } || echo 0` produced "0\n0" because the
    # inner block had already printed "0" before failing — broke the
    # arithmetic test below.
    REAL_EDITS=$(git status --porcelain 2>/dev/null \
        | { grep -vE 'command-center/heartbeat\.json|graphify-out/|\.xcodeproj/' || true; } \
        | wc -l | tr -d ' ')
    if [[ "$REAL_EDITS" -eq 0 ]]; then
        # No real edits — remove any stale patch (issue was claimed, work
        # got committed since last tick, patch no longer reflects WIP)
        rm -f "$SD/wip/${NUM}.patch"
        return
    fi

    mkdir -p "$SD/wip"

    # Tracked changes → standard `git apply`-compatible patch (binary-safe).
    git diff HEAD --binary > "$SD/wip/${NUM}.patch.tmp" 2>/dev/null
    mv "$SD/wip/${NUM}.patch.tmp" "$SD/wip/${NUM}.patch"

    # Untracked files → tarball (git diff doesn't capture them). Filter out
    # noise paths the same way as the edit-detection above.
    local UNTRACKED
    UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null \
        | grep -vE 'command-center/heartbeat\.json|graphify-out/|\.xcodeproj/' || true)
    if [[ -n "$UNTRACKED" ]]; then
        echo "$UNTRACKED" | tar -czf "$SD/wip/${NUM}.untracked.tar.gz.tmp" -T - 2>/dev/null
        mv "$SD/wip/${NUM}.untracked.tar.gz.tmp" "$SD/wip/${NUM}.untracked.tar.gz"
    else
        rm -f "$SD/wip/${NUM}.untracked.tar.gz"
    fi
}

# Strip orphan in-progress labels — a closed issue should never carry
# in-progress (always wrong), and an open sprint-task we're not working on
# shouldn't either. Planning and design-doc issues have their own lifecycle
# so we only touch issues labeled sprint-task.
sweep_stale_in_progress_labels() {
    local SD="$HOME/drift-state"
    local current
    current=$(jq -r '.in_progress // empty' "$SD/sprint-state.json" 2>/dev/null || echo "")

    # Closed issues with in-progress — always stale
    local closed_stale
    closed_stale=$(gh issue list --state closed --label in-progress --limit 20 \
        --json number --jq '.[].number' 2>/dev/null || echo "")
    for num in $closed_stale; do
        [[ -n "$num" ]] || continue
        gh issue edit "$num" --remove-label in-progress >/dev/null 2>&1 \
            && log "Self-heal: stripped in-progress from closed #$num"
    done

    # Open sprint-tasks with in-progress that we're not working on
    local open_stale
    open_stale=$(gh issue list --state open --label in-progress --label sprint-task --limit 20 \
        --json number --jq '.[].number' 2>/dev/null || echo "")
    for num in $open_stale; do
        [[ -n "$num" ]] || continue
        # Re-read current right before strip — protects against the race where
        # a session claims #N during this sweep loop. Without this, the sweep
        # could strip a fresh claim using the stale `current` snapshot from
        # the top of the function. (User reported "issues get into in-progress
        # and then watchdog removes etc" — this race was a contributor.)
        local current_now
        current_now=$(jq -r '.in_progress // empty' "$SD/sprint-state.json" 2>/dev/null || echo "")
        if [[ "$num" != "$current_now" ]]; then
            gh issue edit "$num" --remove-label in-progress >/dev/null 2>&1 \
                && log "Self-heal: stripped orphan in-progress from open sprint-task #$num (current=${current_now:-none})"
        fi
    done
}

# Push heartbeat.json to the `heartbeat-data` side branch so the deployed
# Command Center can fetch fresh data without polluting main's git log.
# Uses git plumbing (hash-object / mktree / commit-tree / update-ref) so
# the working tree on main stays untouched — no `git add`, no commit on
# main, no race with concurrent sessions.
#
# Cadence: throttle to once per 10 min. No piggyback rule (the branch is
# hidden, so there's no benefit to extra freshness on HEAD moves).
#
# History on the side branch keeps growing but is hidden from `git log main`
# and from anyone who didn't ask for it. Storage is negligible (one small
# JSON blob per commit, deduped by git's pack).
#
# Was #758: prior version (`commit_heartbeat_if_due`) committed to main
# producing ~5 heartbeats per real commit in `git log`. See #758 + the
# revert commit 5d734a69 for the history of the trade-off.
commit_heartbeat_to_branch() {
    local hb="$WORK_DIR/command-center/heartbeat.json"
    [[ -f "$hb" ]] || return

    cd "$WORK_DIR" || return

    local SD="$HOME/drift-state"
    local stamp_ts="$SD/last-heartbeat-commit"
    local stamp_blob="$SD/last-heartbeat-blob"

    local now
    now=$(date +%s)
    local last_commit
    last_commit=$(cat "$stamp_ts" 2>/dev/null || echo "0")
    local elapsed=$(( now - last_commit ))

    # Throttle: at most once per 10 min.
    (( elapsed < 600 )) && return

    # Skip if the file content hasn't changed since last push.
    local blob
    blob=$(git hash-object -w "$hb" 2>/dev/null || echo "")
    [[ -z "$blob" ]] && return
    local last_blob
    last_blob=$(cat "$stamp_blob" 2>/dev/null || echo "")
    if [[ "$blob" == "$last_blob" ]]; then
        echo "$now" > "$stamp_ts"
        return
    fi

    # Build tree: command-center/heartbeat.json
    local sub_tree
    sub_tree=$(printf "100644 blob %s\theartbeat.json\n" "$blob" | git mktree 2>/dev/null) || return
    local top_tree
    top_tree=$(printf "040000 tree %s\tcommand-center\n" "$sub_tree" | git mktree 2>/dev/null) || return

    # Parent: local ref if it exists, else remote, else orphan.
    local parent_arg=""
    local parent
    parent=$(git rev-parse --verify --quiet refs/heads/heartbeat-data 2>/dev/null \
          || git rev-parse --verify --quiet refs/remotes/origin/heartbeat-data 2>/dev/null \
          || echo "")
    [[ -n "$parent" ]] && parent_arg="-p $parent"

    local commit
    # shellcheck disable=SC2086  # parent_arg is intentionally unquoted
    commit=$(git commit-tree "$top_tree" $parent_arg -m "chore: heartbeat snapshot" 2>/dev/null) || return
    [[ -z "$commit" ]] && return

    git update-ref refs/heads/heartbeat-data "$commit" 2>/dev/null || return

    if git push origin "refs/heads/heartbeat-data:refs/heads/heartbeat-data" >/dev/null 2>&1; then
        echo "$now" > "$stamp_ts"
        echo "$blob" > "$stamp_blob"
        log "Heartbeat snapshot pushed to heartbeat-data branch (elapsed=${elapsed}s)"
    fi
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

    # 0. Resume interrupted planning session (crash recovery — takes priority over all routing).
    # Guards (added after #720 ran 5 resumes in 14h on a malformed tracking issue):
    #   - Cap consecutive resumes at 10 per planning issue. Past that, auto-close
    #     the tracking issue and skip planning for 24h cooldown. 10 leaves room
    #     for transient stalls (network / 5xx / single-session distractions);
    #     genuinely-stuck planning hits the cap and bails rather than looping
    #     forever. (Original was 3 — too aggressive given planning's 13-step
    #     complexity and frequent network-y stall causes.)
    #   - Sanity-check the tracking issue body has the standard Planning Checklist.
    #     If a previous gh-create failed silently and a session created a
    #     malformed tracking issue (#720 pattern), reset the file and re-create.
    local EXISTING_PLAN
    EXISTING_PLAN=$(cat "$HOME/drift-state/planning-issue" 2>/dev/null | tr -d '[:space:]' || true)
    if [[ -n "$EXISTING_PLAN" ]]; then
        local PLAN_STATE
        PLAN_STATE=$(gh issue view "$EXISTING_PLAN" --json state --jq '.state' 2>/dev/null || echo "CLOSED")
        if [[ "$PLAN_STATE" == "OPEN" ]]; then
            # Resume count bound (added 2026-05-11). One resume = one increment.
            local RESUME_FILE="$HOME/drift-state/planning-resume-count-$EXISTING_PLAN"
            local RESUME_COUNT
            RESUME_COUNT=$(cat "$RESUME_FILE" 2>/dev/null || echo "0")
            RESUME_COUNT=$((RESUME_COUNT + 1))
            echo "$RESUME_COUNT" > "$RESUME_FILE"
            if [[ "$RESUME_COUNT" -gt 10 ]]; then
                log "Planning #$EXISTING_PLAN stuck after $RESUME_COUNT resume attempts — auto-closing, skipping for 24h cooldown."
                gh issue close "$EXISTING_PLAN" --comment "Auto-closed by watchdog: $RESUME_COUNT consecutive stalls/resumes. Planning will re-trigger on next 24h window." 2>/dev/null || true
                rm -f "$HOME/drift-state/planning-issue" "$RESUME_FILE"
                # Stamp last-planning-time so planning-due returns false for 24h
                echo "$(date +%s)" > "$HOME/drift-state/last-planning-time"
                EXISTING_PLAN=""
            else
                # Body sanity check — a properly-created tracking issue has the
                # standard "## Planning Checklist" header. Malformed issues
                # (created by a session after gh-create failed) lack it.
                local PLAN_BODY
                PLAN_BODY=$(gh issue view "$EXISTING_PLAN" --json body --jq '.body' 2>/dev/null || echo "")
                if ! echo "$PLAN_BODY" | grep -q "## Planning Checklist"; then
                    log "Planning #$EXISTING_PLAN has malformed body (no Planning Checklist) — closing as broken, re-creating below."
                    gh issue close "$EXISTING_PLAN" --comment "Auto-closed: malformed tracking issue (no Planning Checklist header). Re-creating from watchdog template." 2>/dev/null || true
                    rm -f "$HOME/drift-state/planning-issue" "$RESUME_FILE"
                    EXISTING_PLAN=""
                else
                    MODEL=$(get_model planning opus)
                    SESSION_TYPE="planning"
                    SESSION_PROMPT="run sprint planning — close Issue #$EXISTING_PLAN when done. RESUME CHECK first: run \`scripts/planning-service.sh remaining\` and skip already-completed steps."
                    # Resume path: stamp in-progress-issue so stuck-detector
                    # + is-clean-state see the active claim. Same as the
                    # fresh-create branch below; this fixes the case where a
                    # planning session is resumed after watchdog restart and
                    # ran observability-blind for the entire resume window.
                    echo "$EXISTING_PLAN" > "$HOME/drift-state/in-progress-issue"
                    log "Resuming interrupted planning (Issue #$EXISTING_PLAN, attempt $RESUME_COUNT/10) — $MODEL"
                fi
            fi
        fi
    fi

    # 0.5. TestFlight publish slot (only under DRIFT_USE_SKILLS, gated by
    # is-clean-state). Runs BEFORE planning/senior/junior so it never
    # collides with an in-flight session — the watchdog only runs ONE
    # claude -p at a time, so slotting TF into that queue gives us zero
    # concurrency on xcodebuild + the main branch commit window.
    #
    # Why not launchd cron: launchd fires fire-and-forget; a senior
    # session running `xcodebuild test` while launchd-driven TF runs
    # `xcodebuild archive` could deadlock the simulator (CLAUDE.md rule)
    # or race on the main branch commit. Watchdog-driven scheduling
    # solves both via existing single-session serialization.
    local USE_SKILLS_CHECK="${DRIFT_USE_SKILLS:-}"
    if [[ -z "$USE_SKILLS_CHECK" ]] && [[ -f "$HOME/drift-state/use-skills.flag" ]]; then
        USE_SKILLS_CHECK=$(cat "$HOME/drift-state/use-skills.flag" 2>/dev/null | tr -d '[:space:]')
    fi
    USE_SKILLS_CHECK="${USE_SKILLS_CHECK:-0}"

    if [[ "$USE_SKILLS_CHECK" == "1" ]] && [[ "$SESSION_TYPE" != "planning" ]]; then
        local TF_LAST TF_AGE
        TF_LAST=$(cat "$HOME/drift-state/last-testflight-publish" 2>/dev/null || echo 0)
        TF_AGE=$(( $(date +%s) - TF_LAST ))
        # 10800s = 3h cadence (TestFlight publish-window minimum)
        if [[ "$TF_AGE" -ge 10800 ]] && "$WORK_DIR/scripts/is-clean-state.sh" > /dev/null 2>&1; then
            # Phase 3e 2026-05-26: archive-failed cooldown gate. The skill self-
            # checks but haiku is inconsistent — observed 2026-05-26 21:50 a TF
            # session bypass its own cooldown self-check and proceed to archive
            # (which fails again). Gate at the watchdog layer too so we don't
            # spawn 5+ TF sessions/hour while cooldown is active.
            local _TF_FAIL_AT _TF_COOLDOWN_AGE
            _TF_FAIL_AT=$(cat "$HOME/drift-state/testflight-archive-failed" 2>/dev/null || echo "0")
            _TF_COOLDOWN_AGE=$(( $(date +%s) - _TF_FAIL_AT ))
            if [[ "$_TF_FAIL_AT" -gt 0 ]] && [[ "$_TF_COOLDOWN_AGE" -lt 86400 ]]; then
                local _remaining=$(( 86400 - _TF_COOLDOWN_AGE ))
                log "TestFlight skipped — archive-failed cooldown active (${_remaining}s remaining, expires $(date -r $(( _TF_FAIL_AT + 86400 ))))"
            else
                MODEL="haiku"
                SESSION_TYPE="testflight"
                SESSION_PROMPT="/testflight-publish"
                log "TestFlight slot — ${TF_AGE}s since last + state clean — spawning /testflight-publish (haiku)"
                # Write the auth flag the guard-testflight.sh hook expects.
                mkdir -p "$HOME/drift-state"
                touch "$HOME/drift-state/testflight-publish-authorized"
            fi
        fi
    fi

    if [[ "$SESSION_TYPE" != "planning" ]] && [[ "$SESSION_TYPE" != "testflight" ]]; then

    # Phase 3c 2026-05-26: stuck-epic 2-cycle cap. Under strict-one-epic
    # mode, planning should not fire while a prior epic is still open. The
    # cap is 2 planning-due cycles: cycle 1 + 2 bump a counter and skip
    # planning; cycle 3 fires planning anyway (override mode) so a
    # tarpit'd epic can't deadlock the queue forever.
    local SHOULD_FIRE_PLANNING=0
    if "$WORK_DIR/scripts/sprint-service.sh" planning-due 2>/dev/null; then
        local OPEN_EPICS STUCK_CYCLES
        OPEN_EPICS=$(_count_open_epics)
        STUCK_CYCLES=$(cat "$HOME/drift-state/stuck-epic-cycles" 2>/dev/null || echo 0)
        if [[ "$OPEN_EPICS" -eq 0 ]] || [[ "$STUCK_CYCLES" -ge 2 ]]; then
            SHOULD_FIRE_PLANNING=1
            rm -f "$HOME/drift-state/stuck-epic-cycles"
            if [[ "$STUCK_CYCLES" -ge 2 ]]; then
                # Fire planning in override mode — the prior epic stayed
                # open across 2 cycles; planning must split / wontfix /
                # mark needs-human.
                touch "$HOME/drift-state/planning-override-stuck-epic"
                log "Planning due AND stuck-epic cap reached (cycles=$STUCK_CYCLES, open epics=$OPEN_EPICS) — firing planning in override mode"
            fi
        else
            STUCK_CYCLES=$((STUCK_CYCLES + 1))
            echo "$STUCK_CYCLES" > "$HOME/drift-state/stuck-epic-cycles"
            log "Planning due but $OPEN_EPICS open epic(s); stuck-cycles=$STUCK_CYCLES (<2 cap) — skipping planning, falling through"
        fi
    fi

    # 1. Planning due (and stuck-epic cap allows firing)?
    if [[ "$SHOULD_FIRE_PLANNING" -eq 1 ]]; then
        MODEL=$(get_model planning opus)
        SESSION_TYPE="planning"
        # NOTE: last-review-time is stamped by `report-service.sh finish` when a
        # product-review branch is actually merged — NOT here. Writing it at
        # session spawn made `cmd_review_due` believe a review was done every
        # time a planner started, and reviews silently stopped getting written
        # (710-cycle gap observed 2026-04-21).
        log "Sprint planning firing — $MODEL"

        local CYCLE=$(cat "$HOME/drift-state/commit-counter" 2>/dev/null || echo "?")
        rm -f "$HOME/drift-state/planning-issue"
        local PLAN_BODY="## Planning Checklist
- [ ] Feedback drained — process-feedback.log reviewed, infra issues created
- [ ] Admin replies — responded to all admin comments on report PRs
- [ ] Product review — review-cycle-${CYCLE}.md PR merged to main
- [ ] Sprint tasks — 8+ sprint-task issues created
- [ ] Personas updated — appended \"What I learned\" to persona files
- [ ] Roadmap updated — applied agreed changes
- [ ] Sprint refreshed — scripts/sprint-service.sh refresh called
- [ ] Bug triage — P0/P1/P2 bugs reviewed, needs-review or approved labels applied
- [ ] Design docs — pending design-doc issues noted, doc-ready ones reviewed
- [ ] Feature requests — untriaged FRs reviewed, deferred or sprint-tasked
- [ ] State assessed — Docs/state.md checked, build/test counts verified"
        # Retry gh issue create up to 3 times — observed silent failures during
        # GitHub 5xx led to #720 (sessions self-created a malformed tracking
        # issue when watchdog's create failed). Don't fall through silently.
        # `gh issue create` does NOT support --json — that flag is only on
        # read commands (`view`, `list`). On success it prints the issue
        # URL; on failure it prints usage text to stderr. Capture both via
        # 2>&1, then extract the trailing number from the URL. The `|| true`
        # on the grep pipeline is mandatory: under `set -euo pipefail`, an
        # empty grep return-code propagates and kills the watchdog silently.
        local PLAN_ISSUE="" PLAN_OUT="" GH_ERR=""
        for attempt in 1 2 3; do
            PLAN_OUT=$(gh issue create \
                --title "Sprint Planning — Cycle $CYCLE" \
                --label planning --label SENIOR --label in-progress \
                --body "$PLAN_BODY" 2>&1) || GH_ERR="$PLAN_OUT"
            PLAN_ISSUE=$(echo "$PLAN_OUT" | grep -oE 'issues/[0-9]+' | grep -oE '[0-9]+' | tail -1 || true)
            [[ -n "$PLAN_ISSUE" ]] && break
            log "Planning tracking-issue create attempt $attempt/3 failed: ${GH_ERR:-$PLAN_OUT} — retrying in $((attempt * 5))s"
            sleep $((attempt * 5))
        done
        if [[ -n "$PLAN_ISSUE" ]]; then
            log "Created planning tracking Issue #$PLAN_ISSUE"
            echo "$PLAN_ISSUE" > "$HOME/drift-state/planning-issue"
            # Phase 3c follow-up 2026-05-26: also stamp in-progress-issue so
            # stuck-detector + is-clean-state + drift-mcp state.* all see the
            # tracked issue. Without this, planning's no-comment-update guard
            # silently no-ops (observed live: planning ran 85+ min with 0
            # comments and the SINCE_PLAN counter never fired).
            echo "$PLAN_ISSUE" > "$HOME/drift-state/in-progress-issue"
            SESSION_PROMPT="run sprint planning — close Issue #$PLAN_ISSUE when done"
        else
            log "ERROR: Planning tracking-issue create failed after 3 attempts. Aborting planning spawn — will retry next watchdog cycle."
            # Don't spawn planning without a tracking issue — the session will
            # create its own (malformed) one, which triggered the #720 loop.
            # Roll back the routing decision so a sprint session can run instead.
            SESSION_TYPE="junior"
            MODEL=$(get_model junior sonnet)
            SESSION_PROMPT="execute junior tasks"
        fi

    # 1.5/1.6. Staleness-driven ceremony skills (phase 3c 2026-05-26).
    # Replaces the in-line admin-replies + knowledge-curate that used to
    # run inside /planning step 3 + step 8. Stamp files
    # `~/drift-state/last-{knowledge-curate,admin-replies}-at` track last
    # successful run. Each band fires AT MOST ONCE per stamp interval so
    # they can't push epic/senior work down indefinitely.
    elif _is_stale "$HOME/drift-state/last-knowledge-curate-at" 604800; then
        # 7d (604800s) cadence — sediments persona files + roadmap +
        # decisions.md prunes. Headless invocation of the existing skill.
        MODEL=$(get_model junior sonnet)
        SESSION_TYPE="knowledge-curate"
        SESSION_PROMPT="/knowledge-curate"
        log "Knowledge-curate stale (≥7d) — junior ($MODEL)"

    elif _is_stale "$HOME/drift-state/last-admin-replies-at" 86400; then
        # 24h (86400s) cadence — replies to admin comments on report
        # PRs. Was bundled into /planning step 3; now its own skill so
        # planning can stay focused on the next epic.
        MODEL=$(get_model junior sonnet)
        SESSION_TYPE="admin-replies"
        SESSION_PROMPT="/admin-replies"
        log "Admin-replies stale (≥24h) — junior ($MODEL)"

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
        # Phase 3b 2026-05-26: when routine-fix is the work-of-record, log
        # it so the watchdog history shows "routine drumbeat" vs "no work."
        # The session prompt stays generic — junior's SKILL step 4.5 spots
        # the routine-fix label on claim and synthesizes the Done-When.
        local ROUTINE_COUNT
        ROUTINE_COUNT=$("$WORK_DIR/scripts/sprint-service.sh" count --routine-fix 2>/dev/null || echo 0)
        if [[ "$ROUTINE_COUNT" -gt 0 ]]; then
            SESSION_PROMPT="execute routine-fix worker tasks"
            log "Routine-fix queue: $ROUTINE_COUNT — junior ($MODEL)"
        else
            SESSION_PROMPT="execute junior tasks"
            log "No P0/SENIOR work — junior ($MODEL)"
        fi
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

    # Seed the heartbeat at spawn so is_log_stale_seconds doesn't flag
    # "stale" based on the previous session's trailing stamp before the
    # new session has made its first tool call.
    date +%s > "$HOME/drift-state/session-heartbeat"

    # Opus gets Sonnet fallback for API overload. Sonnet gets no fallback.
    local FALLBACK=""
    [[ "$MODEL" == "opus" ]] && FALLBACK="--fallback-model sonnet"

    # Skills cutover: when DRIFT_USE_SKILLS=1 (env var OR file flag), spawn
    # with a slash-command prompt that resolves to .claude/skills/<skill>/SKILL.md
    # instead of the giant SESSION_PROMPT. Per-phase context shrinks ~60-70%.
    #
    # SESSION_TYPE → /skill mapping:
    #   planning → /planning  (Opus)
    #   senior   → /senior    (Opus)
    #   junior   → /junior    (Sonnet)
    #
    # Flag source priority: env DRIFT_USE_SKILLS first, then file
    # ~/drift-state/use-skills.flag (1 = on). Using a file flag means
    # launchd-managed watchdog respawns inherit the choice without env
    # mutation. Flip on:  echo 1 > ~/drift-state/use-skills.flag
    # Flip off:           rm -f  ~/drift-state/use-skills.flag
    local USE_SKILLS="${DRIFT_USE_SKILLS:-}"
    if [[ -z "$USE_SKILLS" ]] && [[ -f "$HOME/drift-state/use-skills.flag" ]]; then
        USE_SKILLS=$(cat "$HOME/drift-state/use-skills.flag" 2>/dev/null | tr -d '[:space:]')
    fi
    USE_SKILLS="${USE_SKILLS:-0}"

    local PROMPT_ARG
    local MCP_CONFIG_ARG=""
    if [[ "$USE_SKILLS" == "1" ]]; then
        case "$SESSION_TYPE" in
            planning)        PROMPT_ARG="/planning" ;;
            senior)          PROMPT_ARG="/senior" ;;
            junior)          PROMPT_ARG="/junior" ;;
            testflight)      PROMPT_ARG="/testflight-publish" ;;
            admin-replies)   PROMPT_ARG="/admin-replies" ;;
            knowledge-curate) PROMPT_ARG="/knowledge-curate" ;;
            *)
                log "DRIFT_USE_SKILLS=1 but unknown SESSION_TYPE=$SESSION_TYPE — falling back to legacy prompt"
                PROMPT_ARG="$SESSION_PROMPT"
                ;;
        esac
        # Pass the drift-mcp config so typed tools (sprint_*, design_*,
        # issues_*, state_*, verify_*, testflight_*) are available. The new
        # skill bodies expect these.
        if [[ -f "$WORK_DIR/.claude/mcp-config.json" ]]; then
            MCP_CONFIG_ARG="--mcp-config $WORK_DIR/.claude/mcp-config.json"
        fi
        log "Skill-based spawn: $PROMPT_ARG (model=$MODEL, mcp=$([ -n "$MCP_CONFIG_ARG" ] && echo on || echo off))"
    else
        PROMPT_ARG="$SESSION_PROMPT"
    fi

    # DRIFT_STUCK_DETECTOR_ENFORCE: read from file flag (lets us toggle
    # without restarting watchdog/launchd). When 1, stuck-detector.sh kills
    # sessions that go ≥30 calls without diff growth, ≥20 calls without
    # plan/progress comment update, or ≥5 reads of the same file.
    local STUCK_ENFORCE=""
    if [[ -f "$HOME/drift-state/stuck-detector-enforce.flag" ]]; then
        STUCK_ENFORCE=$(cat "$HOME/drift-state/stuck-detector-enforce.flag" 2>/dev/null | tr -d '[:space:]')
    fi
    STUCK_ENFORCE="${STUCK_ENFORCE:-0}"

    DRIFT_AUTONOMOUS=1 \
    DRIFT_USE_SKILLS="$USE_SKILLS" \
    DRIFT_SESSION_TYPE="$SESSION_TYPE" \
    DRIFT_STUCK_DETECTOR_ENFORCE="$STUCK_ENFORCE" \
    claude -p "$PROMPT_ARG" \
        $MCP_CONFIG_ARG \
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
    # Stamp the spawn time for stable-run-reset crash recovery (gbrain pattern):
    # if a session ran for STABLE_RUN_THRESHOLD seconds before crashing, we
    # forgive prior crash history — distinguishes "broken config" (instant
    # crash, stays stuck) from "transient flake" (long stable run, then crash).
    SESSION_STARTED_AT=$(date +%s)
    log "Autopilot started with PID $CLAUDE_PID (model=$MODEL)"

    # Start Haiku monitor
    start_monitor
}

is_claude_alive() {
    [[ -n "$CLAUDE_PID" ]] && kill -0 "$CLAUDE_PID" 2>/dev/null
}

# Did the session emit a heartbeat or log line within the last `threshold`
# seconds? Used by the crash-handler to distinguish "killed externally"
# (PID gone but log was fresh moments before death) from "real crash"
# (PID gone, log stale, no recent progress).
log_or_heartbeat_fresh() {
    local threshold=$1
    local now
    now=$(date +%s)
    local hb_file="$HOME/drift-state/session-heartbeat"
    if [[ -f "$hb_file" ]]; then
        local hb_ts
        hb_ts=$(cat "$hb_file" 2>/dev/null || echo 0)
        if (( (now - hb_ts) <= threshold )); then
            return 0
        fi
    fi
    if [[ -n "$CURRENT_LOG" ]] && [[ -f "$CURRENT_LOG" ]]; then
        local log_mtime
        log_mtime=$(stat -f %m "$CURRENT_LOG" 2>/dev/null || echo 0)
        if (( (now - log_mtime) <= threshold )); then
            return 0
        fi
    fi
    return 1
}

is_log_stale() {
    is_log_stale_seconds "$STALE_THRESHOLD"
}

is_log_stale_seconds() {
    local threshold=$1
    local now
    now=$(date +%s)

    # Primary signal: session-heartbeat — written by a PreToolUse hook on
    # every tool call. More reliable than log mtime because the stream-json
    # log buffer can go quiet for long generation bursts (writing a big
    # file, extended thinking) even when the session is actively working.
    local hb_file="$HOME/drift-state/session-heartbeat"
    if [[ -f "$hb_file" ]]; then
        local hb_ts
        hb_ts=$(cat "$hb_file" 2>/dev/null || echo "$now")
        local hb_age=$(( now - hb_ts ))
        if (( hb_age <= threshold )); then
            return 1  # heartbeat fresh — alive
        fi
    fi

    # Fallback: log mtime. Keeps the behaviour for sessions that haven't
    # stamped a heartbeat yet (startup, test runners that never reach the
    # first tool call).
    if [[ -z "$CURRENT_LOG" ]] || [[ ! -f "$CURRENT_LOG" ]]; then
        return 1
    fi
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
        # Recover SESSION_STARTED_AT from the log file. Without this, the
        # stable-run-reset crash math computes `now - 0 = bogus huge number`
        # and logs e.g. "session age 1777186865s" (a 56-year-old session).
        # Strategy: parse the timestamp embedded in the log filename
        # (`session_{type}_{epoch}.log`); fall back to file mtime; fall back
        # to "now" if neither is available.
        if [[ -n "$CURRENT_LOG" ]]; then
            SESSION_STARTED_AT=$(echo "$CURRENT_LOG" | sed -nE 's|.*/session_[^_]+_([0-9]+)\.log$|\1|p')
            if [[ -z "$SESSION_STARTED_AT" ]]; then
                SESSION_STARTED_AT=$(stat -f %m "$CURRENT_LOG" 2>/dev/null || stat -c %Y "$CURRENT_LOG" 2>/dev/null || date +%s)
            fi
        else
            SESSION_STARTED_AT=$(date +%s)
        fi
        log "Adopted existing autopilot (PID $CLAUDE_PID, started $(($(date +%s) - SESSION_STARTED_AT))s ago, log: $CURRENT_LOG)"
    else
        log "Stale PID file (PID $SAVED_PID dead). Will start fresh."
        rm -f "$PID_FILE"
    fi
fi

# Initial start
STATE=$(read_control)
if [[ "$STATE" == "RUN" ]]; then
    if [[ -z "$CLAUDE_PID" ]]; then
        # Snapshot WIP BEFORE cleanup. If the prior watchdog died with a live
        # session that left uncommitted work in the tree, this is our only
        # chance to capture it — `cleanup_dirty_state` below will git-checkout
        # everything 5 lines later. Observed regression on #515: prior session
        # died, watchdog respawned via launchd, fired cleanup straight away,
        # the resumable patch only contained heartbeat.json + project.pbxproj
        # noise because the real code edits had been wiped.
        snapshot_wip_if_in_progress
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

    # Snapshot runs every tick regardless of state so the activity graph
    # keeps advancing even while paused — flatlining is then a signal
    # that nothing is running, not that the snapshot is stale.
    # heartbeat.json is intentionally NOT committed — it's written to disk
    # and the command-center reads it locally. Standalone heartbeat commits
    # polluted git log; removed per #642.
    "$WORK_DIR/scripts/heartbeat-snapshot.sh" 2>/dev/null || true

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
                log "PAUSE requested. Waiting for graceful exit (pause-gate.sh hard-blocks claim)..."
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
            log "DRAIN: waiting for current session to finish (pause-gate.sh hard-blocks new claims)."
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
            # stuck-detector handoff: the PostToolUse hook writes a kill
            # marker when it detects no diff growth + no plan-comment update
            # within thresholds. The watchdog actually kills (the hook can't
            # kill its own session because it's a child of it).
            STUCK_KILL_FILE="$HOME/drift-state/stuck-session-kill"
            if [[ -f "$STUCK_KILL_FILE" ]]; then
                STUCK_REASON=$(jq -r '.reason // "unknown"' "$STUCK_KILL_FILE" 2>/dev/null || echo "unknown")
                STUCK_SID=$(jq -r '.session_id // ""' "$STUCK_KILL_FILE" 2>/dev/null || echo "")
                if is_claude_alive; then
                    log "Stuck-detector fired ($STUCK_REASON, session=$STUCK_SID). Killing autopilot."
                    # Mark the in-progress issue as abandoned before killing
                    if [[ -f "$HOME/drift-state/in-progress-issue" ]]; then
                        IN_PROGRESS=$(cat "$HOME/drift-state/in-progress-issue" 2>/dev/null)
                        if [[ -n "$IN_PROGRESS" ]]; then
                            "$WORK_DIR/scripts/sprint-service.sh" abandon "$IN_PROGRESS" --reason "stuck_detector: $STUCK_REASON" 2>/dev/null || true
                        fi
                    fi
                    kill_claude
                fi
                rm -f "$STUCK_KILL_FILE"
            fi

            # Reconcile state before touching anything else — catches stamps
            # that a prior session left stale, GitHub-closed tasks still
            # locking our in_progress slot, and orphan in-progress labels.
            sync_stamps_from_main
            reconcile_in_progress
            check_stale_claim
            snapshot_wip_if_in_progress
            sweep_stale_in_progress_labels
            # heartbeat.json is pushed to the `heartbeat-data` side branch
            # (#758) so the deployed Command Center can fetch fresh data
            # without polluting main's git log. The deployed UI fetches
            # from `heartbeat-data/command-center/heartbeat.json`.
            commit_heartbeat_to_branch
            # Check if autopilot is dead
            if ! is_claude_alive; then
                stop_monitor
                if [[ -n "$CURRENT_LOG" ]] && grep -q '"type":"result"' "$CURRENT_LOG" 2>/dev/null; then
                    log "Autopilot completed normally. Restarting..."
                    atomic_write "$CRASH_FILE" "0"
                    run_compliance "normal"
                elif log_or_heartbeat_fresh "$LIVENESS_FRESH_SECONDS"; then
                    # PID gone but heartbeat / log mtime was fresh within
                    # LIVENESS_FRESH_SECONDS — this is almost certainly an
                    # external kill (launchctl kickstart, OOM killer, manual
                    # `kill`, watchdog self-restart cascading SIGKILL to
                    # children) rather than a session crash. Without this
                    # branch the supervisor counts every restart-induced
                    # death as a session crash, polluting the consecutive-
                    # crashes counter and posting bogus "Resumable: crashed
                    # session" comments to the open issue. Observed
                    # 2026-05-20 against #831 after launchctl kickstart -k.
                    log "Autopilot PID gone but heartbeat/log fresh within ${LIVENESS_FRESH_SECONDS}s — treating as external kill, not a session crash. Crash count NOT incremented."
                    atomic_write "$CRASH_FILE" "0"
                    run_compliance "external_kill"
                else
                    # Stable-run reset: if the session was alive for at least
                    # STABLE_RUN_THRESHOLD seconds, this crash is most likely
                    # transient (network, simulator deadlock, etc.) — forgive
                    # prior crash history.
                    NOW=$(date +%s)
                    SESSION_AGE=$(( NOW - SESSION_STARTED_AT ))
                    PREV_CRASHES=$(cat "$CRASH_FILE" 2>/dev/null || echo "0")
                    if (( SESSION_AGE >= STABLE_RUN_THRESHOLD )) && (( PREV_CRASHES > 0 )); then
                        log "Stable-run reset: session ran ${SESSION_AGE}s before crash (≥ ${STABLE_RUN_THRESHOLD}s). Forgiving $PREV_CRASHES prior crash(es)."
                        PREV_CRASHES=0
                    fi
                    CRASHES=$((PREV_CRASHES + 1))
                    atomic_write "$CRASH_FILE" "$CRASHES"
                    log "Autopilot CRASHED (no result event, session age ${SESSION_AGE}s). Crash #$CRASHES. Restarting..."
                    run_compliance "crash"

                    # Planning-specific anti-loop: when a planning session
                    # crashes (e.g. on Anthropic API socket drops), the
                    # watchdog re-creates a planning tracking issue on every
                    # respawn because last-planning-time isn't stamped until
                    # planning completes. Result: indefinite retry burning
                    # ~$1.50 per attempt with senior/junior queue starved.
                    # Observed 2026-05-19 cycle 12472: 5 consecutive planning
                    # API-error crashes before manual intervention.
                    #
                    # Fix: after 3 consecutive crashes specifically on
                    # planning, stamp last-planning-time so planning-due
                    # returns false for 24h, freeing the queue for senior /
                    # junior work. Operator restores planning by deleting
                    # the stamp when API stabilizes.
                    # SESSION_TYPE is `local` inside start_claude (line 690+)
                    # and doesn't propagate to this main-loop scope. The
                    # canonical record lives in cache-session-type, which
                    # start_claude atomically stamps at line 860 before
                    # every session boots. Reading it here keeps the
                    # planning anti-loop check working without `set -u`
                    # killing the watchdog on an unbound `$SESSION_TYPE`.
                    # Observed 2026-05-20 against #831: senior session
                    # ran a real diff, watchdog crashed in this branch on
                    # the unbound var, restarted, looked like senior was
                    # crash-looping when really the supervisor was.
                    local LAST_SESSION_TYPE
                    LAST_SESSION_TYPE=$(cat "$HOME/drift-state/cache-session-type" 2>/dev/null || echo "")
                    if [[ "$LAST_SESSION_TYPE" == "planning" ]] && [[ "$CRASHES" -ge 3 ]]; then
                        log "Planning crashed $CRASHES times consecutively. Stamping last-planning-time to defer for 24h. Clear ~/drift-state/last-planning-time to retry sooner."
                        date +%s > "$HOME/drift-state/last-planning-time"
                        if [[ -f "$HOME/drift-state/planning-issue" ]]; then
                            local _STALE_PLAN=$(cat "$HOME/drift-state/planning-issue" 2>/dev/null | tr -d '[:space:]' || true)
                            if [[ -n "$_STALE_PLAN" ]]; then
                                gh issue close "$_STALE_PLAN" --comment "Auto-closed: $CRASHES consecutive planning crashes (likely API instability). last-planning-time stamped to defer 24h; senior/junior queue can now advance." 2>/dev/null || true
                            fi
                            rm -f "$HOME/drift-state/planning-issue" "$HOME/drift-state/planning-resume-count-$_STALE_PLAN"
                        fi
                        atomic_write "$CRASH_FILE" "0"
                    elif [[ "$CRASHES" -ge 3 ]]; then
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
                    # Gate: archive is known-broken + P0 bugs still open → skip to avoid guaranteed-failure loop
                    if [[ -f "$HOME/drift-state/testflight-archive-failed" ]] && [[ -s "$HOME/drift-state/cache-p0-bugs" ]]; then
                        _P0_BUGS=$(cat "$HOME/drift-state/cache-p0-bugs")
                        log "TestFlight skipped — archive-failure flag set and P0 bugs open: $_P0_BUGS"
                    else
                        echo "$(date +%s)" > "$HOME/drift-state/testflight-due"
                        log "TestFlight publish due (${_TF_ELAPSED}s since last) — marked for next commit"
                    fi
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
