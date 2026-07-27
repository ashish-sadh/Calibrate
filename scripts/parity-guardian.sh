#!/bin/bash
# Parity Guardian — the operator's "make sure you keep working" backstop.
# Runs every 20 min via launchd (com.drift.parity-guardian). Three duties:
#   1. Resurrect any dead lane watchdog (launchd usually does this; kickstart
#      covers the cases where it doesn't).
#   2. Detect a stalled system (control=RUN but no commits / publish lag) and
#      spawn a ONE-SHOT headless supervisor session (Fable→Opus) to remediate
#      — this replaces the interactive supervisor if that session ever dies.
#   3. Log every finding so the interactive supervisor can audit.
set -uo pipefail

WORK_DIR="/Users/ashishsadh/workspace/Drift"
CONTROL_FILE="$HOME/drift-android-parity.txt"
LOG="$HOME/drift-android-parity-logs/guardian.log"
GUARD_SESSION_LOG_DIR="$HOME/drift-android-parity-logs"
STALL_COMMIT_SEC=9000      # 2.5h with no commit while RUN = stalled
PUBLISH_LAG_SEC=5400       # 90 min unpublished user-visible work = lagging
GUARD_COOLDOWN_SEC=3600    # at most one guardian session per hour
COOLDOWN_STAMP="$GUARD_SESSION_LOG_DIR/.guardian-last-spawn"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

CONTROL=$(tr -d '[:space:]' < "$CONTROL_FILE" 2>/dev/null || echo RUN)
[ "$CONTROL" = "RUN" ] || { log "control=$CONTROL — guardian idle."; exit 0; }

# --- Duty 1: lanes alive ---
for SVC in com.drift.android-parity com.drift.android-parity-scout com.drift.android-parity-planner; do
    PAT="${SVC#com.drift.}"
    case "$PAT" in
        android-parity)          GREP="android-parity-watchdog.sh" ;;
        android-parity-scout)    GREP="android-parity-scout-watchdog.sh" ;;
        android-parity-planner)  GREP="android-parity-planner-watchdog.sh" ;;
    esac
    if ! pgrep -f "$GREP" > /dev/null; then
        log "LANE DOWN: $SVC — kickstarting"
        launchctl kickstart -k "gui/$(id -u)/$SVC" 2>>"$LOG" || launchctl load "$HOME/Library/LaunchAgents/$SVC.plist" 2>>"$LOG"
    fi
done

# --- Duty 2: stall detection ---
cd "$WORK_DIR" || exit 0
NOW=$(date +%s)
LAST_COMMIT=$(git log -1 --format=%ct 2>/dev/null || echo "$NOW")
COMMIT_AGE=$(( NOW - LAST_COMMIT ))

LAST_PUB=$(git log --grep="publish build" -1 --format=%ct 2>/dev/null || echo 0)
UNPUB=$(git log --since="@$LAST_PUB" --invert-grep --grep="publish build" --format=%ct -- drift-android SharedUI 2>/dev/null | tail -1)
PUB_LAG=0
[ -n "$UNPUB" ] && PUB_LAG=$(( NOW - UNPUB ))

STALLED=""
[ "$COMMIT_AGE" -gt "$STALL_COMMIT_SEC" ] && STALLED="no commit in $((COMMIT_AGE/60))min"
[ "$PUB_LAG" -gt "$PUBLISH_LAG_SEC" ] && STALLED="${STALLED:+$STALLED; }unpublished for $((PUB_LAG/60))min"

[ -z "$STALLED" ] && { log "healthy (commit ${COMMIT_AGE}s ago, publag ${PUB_LAG}s)"; exit 0; }

# --- Duty 3: spawn one-shot guardian supervisor (cooldown-gated) ---
LAST_SPAWN=$(cat "$COOLDOWN_STAMP" 2>/dev/null || echo 0)
if [ $(( NOW - LAST_SPAWN )) -lt "$GUARD_COOLDOWN_SEC" ]; then
    log "STALLED ($STALLED) but guardian in cooldown — skipping spawn"
    exit 0
fi
echo "$NOW" > "$COOLDOWN_STAMP"
log "STALLED: $STALLED — spawning one-shot guardian supervisor session"
(
    cd "$WORK_DIR" || exit 1
    export DRIFT_AUTONOMOUS=1
    export JAVA_HOME=/opt/homebrew/opt/openjdk
    export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
    exec "${CLAUDE_BIN:-$HOME/.local/bin/claude}" -p "You are the one-shot GUARDIAN supervisor for the Drift Android tiered parity autopilot (stall detected: $STALLED). Fix the stall and exit: 1) run scripts/android-parity-health.sh; 2) check the three lane watchdogs (android-parity-watchdog=Sonnet executor, scout=Fable tester, planner=Opus) — kickstart any dead one via launchctl; 3) if user-visible commits are unpublished >90min and no /tmp/drift-android-publish.lock, run scripts/android-publish.sh (kill gradle daemons first for memory); 4) check for zombie sessions/locks (stale /tmp/drift-android-publish.lock with no android-publish.sh process → remove; git tree with foreign WIP → leave alone); 5) if a lane keeps crash-looping, read its newest session log tail and fix the root cause if obvious (or PAUSE that consideration and note it); 6) append findings to ~/drift-android-parity-logs/guardian.log. Do NOT start feature work. Exit when the pipeline is moving again." \
        --dangerously-skip-permissions \
        --model claude-fable-5 \
        --fallback-model claude-opus-4-8 \
        --effort max \
        --output-format stream-json --verbose
) > "$GUARD_SESSION_LOG_DIR/guardian-session-$(date +%Y%m%d-%H%M%S).log" 2>&1 &
log "guardian session spawned (pid $!)"
