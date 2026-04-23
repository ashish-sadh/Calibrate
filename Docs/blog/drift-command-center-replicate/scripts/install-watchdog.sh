#!/bin/bash
# Install, uninstall, restart, or inspect the Drift watchdog launchd agent.
# Once installed, launchd keeps the watchdog alive across crashes, reboots,
# and logouts. Day-to-day pausing stays via ~/drift-control.txt — only
# uninstall when you're truly done with Drift Control.
#
# Usage:
#   scripts/install-watchdog.sh install     — copy plist, bootstrap, start
#   scripts/install-watchdog.sh uninstall   — stop + bootout, remove plist
#   scripts/install-watchdog.sh restart     — kickstart (respawns cleanly)
#   scripts/install-watchdog.sh status      — is it loaded? running?
#
# No-op safe: install and uninstall are idempotent.

set -euo pipefail

LABEL="com.drift.watchdog"
UID_NUM="$(id -u)"
TARGET_DIR="$HOME/Library/LaunchAgents"
TARGET_PLIST="$TARGET_DIR/$LABEL.plist"
SOURCE_PLIST="$(cd "$(dirname "$0")" && pwd)/$LABEL.plist"
LOG_DIR="$HOME/drift-self-improve-logs"

cmd="${1:-status}"

ensure_log_dir() { mkdir -p "$LOG_DIR"; }

is_loaded() {
    launchctl list 2>/dev/null | awk -v l="$LABEL" '$3 == l { found=1 } END { exit !found }'
}

# `launchctl bootstrap`/`bootout` are the modern commands (macOS 10.10+);
# fall back to `load`/`unload` on older systems.
bootstrap_plist() {
    if launchctl bootstrap "gui/$UID_NUM" "$TARGET_PLIST" 2>/dev/null; then
        return 0
    fi
    launchctl load -w "$TARGET_PLIST"
}

bootout_plist() {
    if launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null; then
        return 0
    fi
    launchctl unload -w "$TARGET_PLIST" 2>/dev/null || true
}

case "$cmd" in
    install)
        ensure_log_dir
        mkdir -p "$TARGET_DIR"
        cp "$SOURCE_PLIST" "$TARGET_PLIST"
        chmod 644 "$TARGET_PLIST"

        if is_loaded; then
            echo "Watchdog already loaded — reloading with fresh plist..."
            bootout_plist
        fi
        bootstrap_plist
        sleep 1
        if is_loaded; then
            echo "Installed + running."
            echo "  plist:  $TARGET_PLIST"
            echo "  logs:   $LOG_DIR/launchd-{stdout,stderr}.log"
            echo "  paused: echo PAUSE > ~/drift-control.txt (does NOT stop watchdog)"
        else
            echo "Install completed but watchdog not showing up in launchctl list."
            echo "Check: $LOG_DIR/launchd-stderr.log"
            exit 1
        fi
        ;;

    uninstall)
        if is_loaded; then
            echo "Stopping watchdog..."
            bootout_plist
        fi
        if [ -f "$TARGET_PLIST" ]; then
            rm -f "$TARGET_PLIST"
            echo "Removed $TARGET_PLIST."
        fi
        echo "Uninstalled. The running watchdog process (if any) has been signalled."
        ;;

    restart)
        if ! is_loaded; then
            echo "Watchdog is not loaded. Run: $0 install"
            exit 1
        fi
        launchctl kickstart -k "gui/$UID_NUM/$LABEL"
        echo "Restarted (kickstart)."
        ;;

    status)
        if is_loaded; then
            PID=$(launchctl list 2>/dev/null | awk -v l="$LABEL" '$3 == l { print $1 }')
            if [ "$PID" != "-" ] && [ -n "$PID" ]; then
                ETIME=$(ps -p "$PID" -o etime= 2>/dev/null | tr -d ' ' || echo "?")
                echo "Loaded: yes"
                echo "Running: PID $PID, etime $ETIME"
            else
                echo "Loaded: yes"
                echo "Running: no (launchd will restart within 30s)"
            fi
        else
            echo "Loaded: no"
            echo "Run: $0 install  to bootstrap"
        fi
        ;;

    *)
        echo "Usage: $0 {install|uninstall|restart|status}" >&2
        exit 2
        ;;
esac
