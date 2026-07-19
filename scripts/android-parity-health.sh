#!/bin/bash
# One-glance health check for the Android-parity loop. Exit 0 = healthy.
# Run manually or via the launchd health job (which notifies on failure).
set -uo pipefail
LOG_DIR="$HOME/drift-android-parity-logs"
WORK_DIR="/Users/ashishsadh/workspace/Drift"
PROBLEMS=()

# 1. Watchdog process alive?
if pgrep -f "android-parity-watchdog.sh" > /dev/null; then
    echo "✅ watchdog: running (pid $(pgrep -f android-parity-watchdog.sh | head -1))"
else
    echo "❌ watchdog: NOT RUNNING"
    PROBLEMS+=("watchdog dead")
fi

# 2. Session alive or recent?
PID=$(cat "$LOG_DIR/claude.pid" 2>/dev/null || echo "")
if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    SLOG=$(ls -t "$LOG_DIR"/session-*.log 2>/dev/null | head -1)
    AGE=$(( $(date +%s) - $(stat -f %m "$SLOG") ))
    echo "✅ session: running (pid $PID, log fresh ${AGE}s ago)"
    if [ "$AGE" -gt 2700 ]; then
        echo "⚠️  session log silent >45min (watchdog should kill it soon)"
    fi
else
    echo "ℹ️  session: between sessions (watchdog should respawn within ~1min)"
fi

# 3. Progress: commits on main in the last 5 hours?
cd "$WORK_DIR"
LAST_COMMIT_AGE=$(( $(date +%s) - $(git log -1 --format=%ct) ))
if [ "$LAST_COMMIT_AGE" -lt 18000 ]; then
    echo "✅ progress: last commit $((LAST_COMMIT_AGE/60))min ago — $(git log -1 --format='%h %s' | head -c 90)"
else
    echo "❌ progress: NO commit in $((LAST_COMMIT_AGE/3600))h"
    PROBLEMS+=("no commits ${LAST_COMMIT_AGE}s")
fi

# 4. Publishes flowing? Any user-visible commit (drift-android/ or SharedUI/)
# newer than the last publish and older than 1h = a violation of the
# ship-every-significant-change rule (operator mandate 2026-07-19).
LAST_PUB=$(git log --grep="publish build" -1 --format=%ct 2>/dev/null || echo 0)
PUB_AGE=$(( $(date +%s) - LAST_PUB ))
echo "ℹ️  last Play publish: $((PUB_AGE/3600))h ago ($(grep CURRENT_PROJECT drift-android/Skip.env))"
UNPUB=$(git log --since="@$LAST_PUB" --format='%ct %h' -- drift-android SharedUI | grep -cv "^$" || true)
if [ "${UNPUB:-0}" -gt 0 ]; then
    OLDEST_UNPUB=$(git log --since="@$LAST_PUB" --format=%ct -- drift-android SharedUI | tail -1)
    UNPUB_AGE=$(( $(date +%s) - OLDEST_UNPUB ))
    if [ "$UNPUB_AGE" -gt 3600 ]; then
        echo "❌ $UNPUB user-visible commit(s) unpublished for $((UNPUB_AGE/60))min — publish NOW (scripts/android-publish.sh)"
        PROBLEMS+=("unpublished user-visible commits")
    else
        echo "ℹ️  $UNPUB user-visible commit(s) awaiting publish (${UNPUB_AGE}s old — within the 1h window)"
    fi
fi

# 5. Emulator up (sessions need it)?
if timeout_out=$(perl -e 'alarm 5; exec @ARGV' adb devices 2>/dev/null || true); echo "$timeout_out" | grep -q "emulator.*device"; then
    echo "✅ emulator: online"
else
    echo "⚠️  emulator: offline (sessions know how to boot it)"
fi

if [ ${#PROBLEMS[@]} -gt 0 ]; then
    echo "UNHEALTHY: ${PROBLEMS[*]}"
    exit 1
fi
echo "HEALTHY"
