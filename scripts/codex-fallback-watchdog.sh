#!/bin/bash
# Codex fallback lane — runs ONLY while Claude credit is exhausted (Fable AND
# Opus), so the machine keeps doing useful, SAFE work overnight instead of
# idling. Operator: "maybe try codex when you are out ... keep checking opus and
# fable ... use codex's best model." Codex works DriftCore pure-logic test
# coverage (what it's good at) in an ISOLATED worktree on branch codex/overnight,
# committing there only — a human reviews + merges in the morning. NEVER main.
#
# Trigger: the parity watchdog raises ~/drift-android-parity-logs/claude-exhausted.flag
# after repeated fast-crashes (credit out) and CLEARS it the moment a real Claude
# session runs again. This lane watches that flag — zero extra Claude cost.
set -uo pipefail

WORKTREE="/Users/ashishsadh/workspace/drift-codex-overnight"
TASK="/Users/ashishsadh/workspace/Drift/scripts/codex-overnight-task.md"
FLAG="$HOME/drift-android-parity-logs/claude-exhausted.flag"
LOG_DIR="$HOME/drift-codex-overnight-logs"
CONTROL_FILE="$HOME/drift-android-parity.txt"   # shares STOP with the parity loop
WATCHDOG_LOG="$LOG_DIR/watchdog.log"
CHECK_INTERVAL=180        # poll the flag every 3 min
CODEX_BIN="${CODEX_BIN:-/opt/homebrew/bin/codex}"

mkdir -p "$LOG_DIR"

# single instance
EXISTING=$(pgrep -f "codex-fallback-watchdog.sh" | grep -v $$ || true)
[ -n "$EXISTING" ] && { echo "$EXISTING" | xargs kill 2>/dev/null || true; sleep 1; }

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$WATCHDOG_LOG"; }
log "Codex fallback watchdog started (pid $$). Watches $FLAG"

while true; do
    CONTROL=$(tr -d '[:space:]' < "$CONTROL_FILE" 2>/dev/null || echo RUN)
    [ "$CONTROL" = "STOP" ] && { log "STOP — exiting."; exit 0; }

    if [ ! -f "$FLAG" ]; then
        # Claude is up (or never went down) — parity owns the work; stay idle.
        sleep "$CHECK_INTERVAL"; continue
    fi

    # Claude exhausted — do ONE Codex run, then re-check the flag (Claude may
    # have returned; parity clears the flag on its next successful session).
    SESSION_LOG="$LOG_DIR/session-$(date +%Y%m%d-%H%M%S).log"
    log "Claude exhausted flag present — running one Codex DriftCore task → $SESSION_LOG"
    (
        cd "$WORKTREE" || exit 1
        # Codex default model = its best coding model; high reasoning effort.
        exec "$CODEX_BIN" exec \
            --cd "$WORKTREE" \
            --dangerously-bypass-approvals-and-sandbox \
            -c model_reasoning_effort="high" \
            - < "$TASK"
    ) > "$SESSION_LOG" 2>&1
    RC=$?
    log "Codex run ended rc=$RC"
    # brief pause; if the flag is gone next loop, we stand down automatically
    sleep 30
done
