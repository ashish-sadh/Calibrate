#!/bin/bash
# Bucket the raw heartbeat log into a compact JSON snapshot the Command
# Center can render as an activity graph. Writes to
# command-center/heartbeat.json. Idempotent — safe to call on every
# watchdog tick.
#
# Bucket format: each bucket covers BUCKET_SECONDS seconds and holds the
# tool-call count + the session type that contributed the most calls. A
# session type of "idle" is emitted for buckets with zero activity. Output
# covers the last WINDOW_HOURS (24h) so the UI can show a rolling timeline.

set -e

LOG="$HOME/drift-state/session-heartbeat.log"
WATCHDOG_LOG="$HOME/drift-self-improve-logs/watchdog.log"
OUT="/Users/ashishsadh/workspace/Drift/command-center/heartbeat.json"
WINDOW_HOURS=24
BUCKET_SECONDS=300   # 5-minute buckets → 288 points over 24h

NOW=$(date +%s)
WINDOW_START=$(( NOW - WINDOW_HOURS * 3600 ))

HB_ARG="$LOG"
[ -f "$LOG" ] || HB_ARG=""
WD_ARG="$WATCHDOG_LOG"
[ -f "$WATCHDOG_LOG" ] || WD_ARG=""

python3 - "$HB_ARG" "$WD_ARG" "$WINDOW_START" "$NOW" "$BUCKET_SECONDS" <<'PY' > "$OUT"
import json, re, sys, time
from collections import defaultdict, Counter
from datetime import datetime

hb_path, wd_path, window_start, now, bucket_s = sys.argv[1:6]
window_start = int(window_start)
now = int(now)
bucket_s = int(bucket_s)

# ── Heartbeat buckets ─────────────────────────────────────────────────────
buckets = defaultdict(Counter)
if hb_path:
    try:
        with open(hb_path) as f:
            for line in f:
                parts = line.strip().split(None, 1)
                if not parts or not parts[0].isdigit():
                    continue
                ts = int(parts[0])
                session_type = parts[1] if len(parts) > 1 else "unknown"
                if ts < window_start or ts > now:
                    continue
                bucket = (ts // bucket_s) * bucket_s
                buckets[bucket][session_type] += 1
    except FileNotFoundError:
        pass

rows = []
first_bucket = (window_start // bucket_s) * bucket_s
last_bucket = (now // bucket_s) * bucket_s
b = first_bucket
while b <= last_bucket:
    counts = buckets.get(b)
    if counts:
        dominant = counts.most_common(1)[0][0]
        total = sum(counts.values())
    else:
        dominant = "idle"
        total = 0
    rows.append({"t": b, "count": total, "type": dominant})
    b += bucket_s

# ── Watchdog events (start / stall / crash / exit) ────────────────────────
events = []
if wd_path:
    ts_re = re.compile(r"^\[([\d\-]+ [\d:]+)\] (.*)$")
    start_re = re.compile(r"Starting autopilot \((\w+), model=(\w+)")
    stall_re = re.compile(r"Autopilot stalled")
    crash_re = re.compile(r"Autopilot CRASHED")
    exit_re = re.compile(r"(session exited gracefully|Autopilot completed normally)")
    pause_re = re.compile(r"PAUSE requested")

    def to_epoch(stamp):
        try:
            return int(datetime.strptime(stamp, "%Y-%m-%d %H:%M:%S").timestamp())
        except ValueError:
            return None

    try:
        with open(wd_path) as f:
            for line in f:
                m = ts_re.match(line)
                if not m:
                    continue
                ts = to_epoch(m.group(1))
                if ts is None or ts < window_start or ts > now:
                    continue
                msg = m.group(2)
                sm = start_re.search(msg)
                if sm:
                    events.append({"t": ts, "kind": "start",
                                    "session": sm.group(1), "model": sm.group(2)})
                    continue
                if stall_re.search(msg):
                    events.append({"t": ts, "kind": "stall"})
                    continue
                if crash_re.search(msg):
                    events.append({"t": ts, "kind": "crash"})
                    continue
                if pause_re.search(msg):
                    events.append({"t": ts, "kind": "pause"})
                    continue
                if exit_re.search(msg):
                    events.append({"t": ts, "kind": "exit"})
    except FileNotFoundError:
        pass

print(json.dumps({
    "generated_at": now,
    "window_hours": int((now - window_start) / 3600),
    "bucket_seconds": bucket_s,
    "buckets": rows,
    "events": events,
}))
PY
