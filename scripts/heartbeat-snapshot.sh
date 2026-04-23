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
OUT="/Users/ashishsadh/workspace/Drift/command-center/heartbeat.json"
WINDOW_HOURS=24
BUCKET_SECONDS=300   # 5-minute buckets → 288 points over 24h

NOW=$(date +%s)
WINDOW_START=$(( NOW - WINDOW_HOURS * 3600 ))

if [ ! -f "$LOG" ]; then
    # Emit an empty snapshot so the dashboard can render "no activity".
    python3 -c "
import json, time
print(json.dumps({
    'generated_at': $NOW,
    'window_hours': $WINDOW_HOURS,
    'bucket_seconds': $BUCKET_SECONDS,
    'buckets': []
}))
" > "$OUT"
    exit 0
fi

python3 - "$LOG" "$WINDOW_START" "$NOW" "$BUCKET_SECONDS" <<'PY' > "$OUT"
import json, sys, time
from collections import defaultdict, Counter

log_path, window_start, now, bucket_s = sys.argv[1:5]
window_start = int(window_start)
now = int(now)
bucket_s = int(bucket_s)

buckets = defaultdict(Counter)
with open(log_path) as f:
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

# Emit a row per bucket in the window so the UI can draw a full timeline
# including idle gaps.
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

print(json.dumps({
    "generated_at": now,
    "window_hours": int((now - window_start) / 3600),
    "bucket_seconds": bucket_s,
    "buckets": rows
}))
PY
