#!/bin/bash
# Sprint Service — authoritative task queue for all Drift Control sessions.
# Manages ~/drift-state/sprint-state.json as source of truth.
# All sessions call this script to get work, claim tasks, and close them.
#
# Commands:
#   refresh                              — fetch GitHub issues, write state file
#   next [--senior|--junior|--any]       — print "NUMBER TITLE" of next task, or "none"
#   claim <N>                            — atomically mark task in-progress
#   done <N> <commit_hash>               — comment + close + remove in-progress
#   unclaim <N>                          — release claim without closing
#   clear                                — remove ALL in-progress (watchdog cleanup)
#   status                               — print sprint summary
#   count [--p0|--senior|--junior|--sprint|--permanent] — print count
#   planning-due                         — exit 0 if 6+ hours since last planning
#   planning-done                        — stamp last-planning-time = now

set -euo pipefail

STATE_FILE="$HOME/drift-state/sprint-state.json"
LOCK_FILE="$HOME/drift-state/sprint-state.json.lock"
LAST_REVIEW_FILE="$HOME/drift-state/last-review-time"
LAST_PLANNING_FILE="$HOME/drift-state/last-planning-time"
WORK_DIR="/Users/ashishsadh/workspace/Drift"

mkdir -p "$HOME/drift-state"

# ── JSON helpers ──────────────────────────────────────────────────────────────

read_state() {
    if [ ! -f "$STATE_FILE" ]; then
        echo '{"version":1,"refreshed":0,"in_progress":null,"tasks":[]}'
    else
        cat "$STATE_FILE"
    fi
}

write_state() {
    echo "$1" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
}

# ── Commands ──────────────────────────────────────────────────────────────────

cmd_refresh() {
    local TMP_DIR
    TMP_DIR=$(mktemp -d)
    local NOW
    NOW=$(date +%s)

    # Write each issue list to temp files (avoids shell quoting fragility)
    # --limit 100 on all calls: gh default is 30, which truncates busy repos
    gh issue list --state open --label bug --label P0 --limit 100 --json number,title,labels \
        --jq '[.[] | {"number": .number, "title": .title, "labels": [.labels[].name], "status": "pending"}]' \
        > "$TMP_DIR/p0_bugs.json" 2>/dev/null || echo "[]" > "$TMP_DIR/p0_bugs.json"

    gh issue list --state open --label feature-request --label P0 --limit 100 --json number,title,labels \
        --jq '[.[] | {"number": .number, "title": .title, "labels": [.labels[].name], "status": "pending"}]' \
        > "$TMP_DIR/p0_feats.json" 2>/dev/null || echo "[]" > "$TMP_DIR/p0_feats.json"

    gh issue list --state open --label sprint-task --label SENIOR --limit 100 --json number,title,labels \
        --jq '[.[] | {"number": .number, "title": .title, "labels": [.labels[].name], "status": "pending"}]' \
        > "$TMP_DIR/senior.json" 2>/dev/null || echo "[]" > "$TMP_DIR/senior.json"

    gh issue list --state open --label sprint-task --limit 100 --json number,title,labels \
        --jq '[.[] | select(.labels | map(.name) | index("SENIOR") | not) | {"number": .number, "title": .title, "labels": [.labels[].name], "status": "pending"}]' \
        > "$TMP_DIR/junior.json" 2>/dev/null || echo "[]" > "$TMP_DIR/junior.json"

    gh issue list --state open --label bug --label P1 --limit 100 --json number,title,labels \
        --jq '[.[] | {"number": .number, "title": .title, "labels": [.labels[].name], "status": "pending"}]' \
        > "$TMP_DIR/p1_bugs.json" 2>/dev/null || echo "[]" > "$TMP_DIR/p1_bugs.json"

    gh issue list --state open --label bug --label P2 --limit 100 --json number,title,labels \
        --jq '[.[] | {"number": .number, "title": .title, "labels": [.labels[].name], "status": "pending"}]' \
        > "$TMP_DIR/p2_bugs.json" 2>/dev/null || echo "[]" > "$TMP_DIR/p2_bugs.json"

    gh issue list --state open --label permanent-task --limit 100 --json number,title,labels,updatedAt \
        --jq '[.[] | {"number": .number, "title": .title, "labels": [.labels[].name], "status": "permanent", "updatedAt": .updatedAt}]' \
        > "$TMP_DIR/perm.json" 2>/dev/null || echo "[]" > "$TMP_DIR/perm.json"

    local NEW_STATE
    NEW_STATE=$(python3 - <<PYEOF
import json, os

tmp = "$TMP_DIR"
def load(f):
    try:
        return json.load(open(f))
    except Exception:
        return []

p0_bugs = load(f"{tmp}/p0_bugs.json")
p1_bugs  = load(f"{tmp}/p1_bugs.json")
p2_bugs  = load(f"{tmp}/p2_bugs.json")
senior   = load(f"{tmp}/senior.json")
junior   = load(f"{tmp}/junior.json")
perm     = load(f"{tmp}/perm.json")

seen, tasks = set(), []
for t in p0_bugs + p1_bugs + p2_bugs + senior + junior + perm:
    if t["number"] not in seen:
        seen.add(t["number"])
        tasks.append(t)

state = {"version": 1, "refreshed": $NOW, "in_progress": None, "tasks": tasks, "session_tasks": 0}
try:
    existing = json.load(open("$STATE_FILE"))
    state["in_progress"] = existing.get("in_progress")
    state["session_tasks"] = existing.get("session_tasks", 0)
    # Preserve per-task sprint_done flags across refreshes (senior once-per-sprint budget)
    old_by_num = {t["number"]: t for t in existing.get("tasks", [])}
    for t in state["tasks"]:
        old = old_by_num.get(t["number"], {})
        if t.get("status") == "permanent" and old.get("sprint_done"):
            t["sprint_done"] = True
except Exception:
    pass

print(json.dumps(state, indent=2))
PYEOF
)

    rm -rf "$TMP_DIR"

    if [ -n "$NEW_STATE" ]; then
        echo "$NEW_STATE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
        local COUNT
        COUNT=$(python3 -c "import json; print(len(json.load(open('$STATE_FILE'))['tasks']))" 2>/dev/null || echo "?")
        echo "Sprint service: refreshed $COUNT tasks"
    else
        echo "Sprint service: refresh failed (no GitHub access?), using stale state" >&2
    fi

    # Update P0 cache for compliance hook
    gh issue list --state open --label P0 --json number,title \
        --jq '.[] | "#\(.number) \(.title)"' > "$HOME/drift-state/cache-p0-bugs" 2>/dev/null || true
}

cmd_next() {
    local FILTER="${1:---any}"

    python3 - "$FILTER" "$STATE_FILE" <<'PYEOF'
import json, sys

filter_mode = sys.argv[1]
state_file  = sys.argv[2]

try:
    state = json.load(open(state_file))
except Exception:
    print("none"); sys.exit(0)

tasks       = state.get("tasks", [])
in_progress = state.get("in_progress")

def has(t, label): return label in t.get("labels", [])

# Session budget: max 5 implementation tasks per session (not enforced for --any / planning)
if filter_mode in ("--senior", "--junior"):
    if state.get("session_tasks", 0) >= 5:
        print("none"); sys.exit(0)

# Skip done and currently claimed
available = [t for t in tasks
             if t.get("status") != "done" and t.get("number") != in_progress]

# ── Priority 1 (all sessions): Admin-approved P0 bugs ─────────────────────────
# Admin-approved = has sprint-task OR approved label. CC's Approve button stamps
# sprint-task; admins sometimes manually stamp `approved` via GitHub UI (e.g. #282,
# which then stayed invisible to the router). Accept either as the go-signal.
def admin_approved(t):
    return has(t, "sprint-task") or has(t, "approved")

for t in available:
    if has(t, "needs-review"): continue
    if has(t, "bug") and has(t, "P0") and admin_approved(t):
        print(f"{t['number']} {t['title']}"); sys.exit(0)

# ── Senior-only section ────────────────────────────────────────────────────────
if filter_mode in ("--senior", "--any"):

    # Priority 2: SENIOR-labeled sprint tasks (feature tasks + explicitly SENIOR bugs)
    for t in available:
        if has(t, "needs-review"): continue
        if has(t, "sprint-task") and has(t, "SENIOR"):
            print(f"{t['number']} {t['title']}"); sys.exit(0)

    # Priority 3: Admin-approved P1/P2 bugs (sprint-task or approved, no SENIOR, no needs-review)
    for t in available:
        if has(t, "needs-review"): continue
        if has(t, "bug") and (has(t, "P1") or has(t, "P2")) and admin_approved(t) and not has(t, "SENIOR"):
            print(f"{t['number']} {t['title']}"); sys.exit(0)

    # Priority 4: Requested SENIOR permanent tasks (admin-requested this cycle, once per sprint)
    for t in available:
        if has(t, "needs-review"): continue
        if has(t, "permanent-task") and has(t, "SENIOR") and has(t, "requested") and not t.get("sprint_done", False):
            print(f"{t['number']} {t['title']}"); sys.exit(0)

    # Priority 5: SENIOR permanent tasks (once per sprint — sprint_done flag resets at planning)
    perm_senior = sorted(
        [t for t in available if has(t, "permanent-task") and has(t, "SENIOR")
         and not t.get("sprint_done", False) and not has(t, "needs-review")],
        key=lambda t: t.get("updatedAt", "")
    )
    if perm_senior:
        print(f"{perm_senior[0]['number']} {perm_senior[0]['title']}"); sys.exit(0)

# ── Junior-only section ────────────────────────────────────────────────────────
if filter_mode in ("--junior", "--any"):

    # Priority 2: Regular sprint tasks (sprint-task, no SENIOR, not a bug)
    for t in available:
        if has(t, "needs-review"): continue
        if has(t, "sprint-task") and not has(t, "SENIOR") and not has(t, "bug"):
            print(f"{t['number']} {t['title']}"); sys.exit(0)

    # Priority 3: Admin-approved P1/P2 bugs (sprint-task or approved, no SENIOR, no needs-review)
    for t in available:
        if has(t, "needs-review"): continue
        if has(t, "bug") and (has(t, "P1") or has(t, "P2")) and admin_approved(t) and not has(t, "SENIOR"):
            print(f"{t['number']} {t['title']}"); sys.exit(0)

    # Priority 4: Requested non-SENIOR permanent tasks (admin-requested this cycle)
    for t in available:
        if has(t, "needs-review"): continue
        if has(t, "permanent-task") and not has(t, "SENIOR") and has(t, "requested"):
            print(f"{t['number']} {t['title']}"); sys.exit(0)

    # Priority 5: Regular permanent tasks (no SENIOR, loops indefinitely — no sprint budget for junior)
    # Only when no sprint tasks remain in the queue
    remaining_sprint = [t for t in available if has(t, "sprint-task") and not has(t, "needs-review")]
    if not remaining_sprint:
        perm = sorted(
            [t for t in available if has(t, "permanent-task") and not has(t, "SENIOR")
             and not has(t, "needs-review")],
            key=lambda t: t.get("updatedAt", "")
        )
        if perm:
            print(f"{perm[0]['number']} {perm[0]['title']}"); sys.exit(0)

print("none")
PYEOF
}

cmd_claim() {
    local NUM="$1"
    if [ -z "$NUM" ]; then echo "Usage: sprint-service.sh claim <number>" >&2; exit 1; fi

    # mkdir-based atomic lock (cross-platform: macOS + Linux)
    local LOCK_DIR="${LOCK_FILE}.dir"
    local LOCK_WAIT=0
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        sleep 0.2
        LOCK_WAIT=$((LOCK_WAIT + 1))
        if [[ "$LOCK_WAIT" -ge 50 ]]; then  # 10s timeout
            echo "CLAIM FAILED: could not acquire lock" >&2; exit 1
        fi
    done
    trap "rmdir '$LOCK_DIR' 2>/dev/null || true" EXIT

    # Fetch issue data for task-not-in-state case (do before Python to avoid gh inside heredoc)
    local ISSUE_JSON
    ISSUE_JSON=$(gh issue view "$NUM" --json title,labels 2>/dev/null || echo '{"title":"Issue #'"$NUM"'","labels":[]}')

    python3 - "$STATE_FILE" "$NUM" "$ISSUE_JSON" <<'PYEOF'
import json, sys

state_file  = sys.argv[1]
num         = int(sys.argv[2])
issue_json  = sys.argv[3]

try:
    state = json.load(open(state_file))
except:
    state = {"version": 1, "refreshed": 0, "in_progress": None, "tasks": []}

ip = state.get("in_progress")
if ip is not None:
    print(f"CLAIM FAILED: task #{ip} already in-progress. Use: sprint-service.sh done {ip} <commit> OR unclaim {ip}", file=sys.stderr)
    sys.exit(1)

# Find or insert task
tasks = state.get("tasks", [])
found = next((t for t in tasks if t["number"] == num), None)
if found is None:
    issue = json.loads(issue_json)
    labels = [lb["name"] for lb in issue.get("labels", [])]
    tasks.insert(0, {"number": num, "title": issue.get("title", f"Issue #{num}"), "labels": labels, "status": "in_progress"})
    state["tasks"] = tasks
else:
    found["status"] = "in_progress"

state["in_progress"] = num
with open(state_file, "w") as f:
    json.dump(state, f, indent=2)
print(f"Claimed #{num}")
PYEOF

    rmdir "$LOCK_DIR" 2>/dev/null || true
    trap - EXIT

    gh issue edit "$NUM" --add-label in-progress 2>/dev/null || true
}

cmd_done() {
    local NUM="$1"
    local COMMIT="${2:-}"
    if [ -z "$NUM" ]; then echo "Usage: sprint-service.sh done <number> <commit>" >&2; exit 1; fi

    local NOTE=""
    if [ -f "/tmp/done-note-$NUM" ]; then
        NOTE=$(cat "/tmp/done-note-$NUM")
        rm -f "/tmp/done-note-$NUM"
    fi

    local COMMIT_REF=""
    [ -n "$COMMIT" ] && COMMIT_REF=" Commit: $COMMIT"

    local COMMENT="Done.${COMMIT_REF}"
    [ -n "$NOTE" ] && COMMENT="$NOTE${COMMIT_REF}"

    gh issue comment "$NUM" --body "$COMMENT" 2>/dev/null || true
    gh issue close "$NUM" 2>/dev/null || true
    gh issue edit "$NUM" --remove-label in-progress 2>/dev/null || true

    python3 - "$STATE_FILE" "$NUM" <<'PYEOF'
import json, sys
state_file, num = sys.argv[1], int(sys.argv[2])
try:
    d = json.load(open(state_file))
    d["in_progress"] = None
    for t in d["tasks"]:
        if t["number"] == num:
            t["status"] = "done"
            # Count implementation tasks toward session budget
            labels = t.get("labels", [])
            if "sprint-task" in labels or "permanent-task" in labels:
                d["session_tasks"] = d.get("session_tasks", 0) + 1
            break
    with open(state_file, "w") as f: json.dump(d, f, indent=2)
except Exception: pass
PYEOF

    echo "Closed #$NUM"
}

cmd_unclaim() {
    local NUM="$1"
    if [ -z "$NUM" ]; then echo "Usage: sprint-service.sh unclaim <number>" >&2; exit 1; fi

    gh issue edit "$NUM" --remove-label in-progress 2>/dev/null || true

    python3 - "$STATE_FILE" "$NUM" <<'PYEOF'
import json, sys
state_file, num = sys.argv[1], int(sys.argv[2])
try:
    d = json.load(open(state_file))
    if d.get("in_progress") == num: d["in_progress"] = None
    for t in d["tasks"]:
        if t["number"] == num: t["status"] = "pending"; break
    with open(state_file, "w") as f: json.dump(d, f, indent=2)
except Exception: pass
PYEOF

    echo "Unclaimed #$NUM"
}

cmd_session_done() {
    local NUM="$1"
    if [ -z "$NUM" ]; then echo "Usage: sprint-service.sh session-done <number>" >&2; exit 1; fi

    # Remove in-progress label from GitHub
    gh issue edit "$NUM" --remove-label in-progress 2>/dev/null || true

    # Mark done in LOCAL state only — do NOT close the GitHub issue.
    # For permanent tasks:
    #   - Sets sprint_done=True (persists across refreshes, blocks senior re-selection this sprint)
    #   - Status "done" is a local sentinel; next refresh resets status to "permanent"
    #   - Junior ignores sprint_done; senior respects it until planning calls reset-sprint-done
    # Also used for stale-state correction: session discovers GitHub issue already closed,
    # calls session-done to fix local cache so sprint-service next doesn't return it again.
    python3 - "$STATE_FILE" "$NUM" <<'PYEOF'
import json, sys
state_file, num = sys.argv[1], int(sys.argv[2])
try:
    d = json.load(open(state_file))
    if d.get("in_progress") == num: d["in_progress"] = None
    for t in d["tasks"]:
        if t["number"] == num:
            t["status"] = "done"
            if "permanent-task" in t.get("labels", []):
                t["sprint_done"] = True  # blocks senior re-selection until planning resets
                d["session_tasks"] = d.get("session_tasks", 0) + 1
            break
    with open(state_file, "w") as f: json.dump(d, f, indent=2)
except Exception: pass
PYEOF

    echo "Session-done #$NUM (not closed on GitHub)"
}

cmd_start_session() {
    python3 - "$STATE_FILE" <<'PYEOF'
import json, sys
state_file = sys.argv[1]
try:
    d = json.load(open(state_file))
except Exception:
    d = {"version": 1, "refreshed": 0, "in_progress": None, "tasks": []}
d["session_tasks"] = 0
with open(state_file, "w") as f: json.dump(d, f, indent=2)
print("Session started: task counter reset to 0")
PYEOF
}

cmd_reset_sprint_done() {
    # Clear all sprint_done flags — called by planning session at end of each cycle
    # to allow senior to work permanent tasks again in the new sprint
    python3 - "$STATE_FILE" <<'PYEOF'
import json, sys
state_file = sys.argv[1]
try:
    d = json.load(open(state_file))
    count = 0
    for t in d["tasks"]:
        if t.get("sprint_done"):
            t["sprint_done"] = False
            count += 1
    with open(state_file, "w") as f: json.dump(d, f, indent=2)
    print(f"Reset sprint_done for {count} permanent task(s)")
except Exception: pass
PYEOF
}

cmd_clear() {
    # Remove all in-progress labels from GitHub and clear state file
    local IN_PROGRESS_NUMS
    IN_PROGRESS_NUMS=$(gh issue list --state open --label in-progress --json number \
        --jq '.[].number' 2>/dev/null || true)

    for N in $IN_PROGRESS_NUMS; do
        gh issue edit "$N" --remove-label in-progress 2>/dev/null || true
    done

    # Also check state file for claimed task
    local STATE_IP
    STATE_IP=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('in_progress') or '')" 2>/dev/null || true)
    if [ -n "$STATE_IP" ] && [ "$STATE_IP" != "None" ]; then
        gh issue edit "$STATE_IP" --remove-label in-progress 2>/dev/null || true
    fi

    python3 - "$STATE_FILE" <<'PYEOF'
import json, sys
state_file = sys.argv[1]
try:
    d = json.load(open(state_file))
    d["in_progress"] = None
    for t in d["tasks"]:
        if t.get("status") == "in_progress": t["status"] = "pending"
    with open(state_file, "w") as f: json.dump(d, f, indent=2)
except Exception: pass
PYEOF

    # Clear in-progress cache
    > "$HOME/drift-state/cache-in-progress" 2>/dev/null || true
    echo "Sprint service: cleared all in-progress"
}

cmd_status() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "Sprint service: not initialized. Run: scripts/sprint-service.sh refresh"
        return
    fi
    python3 - "$STATE_FILE" <<'PYEOF'
import json, sys, time
state_file = sys.argv[1]
d = json.load(open(state_file))
tasks   = d.get("tasks", [])
pending = [t for t in tasks if t.get("status") == "pending"]
done    = [t for t in tasks if t.get("status") == "done"]
perm    = [t for t in tasks if t.get("status") == "permanent"]
ip      = d.get("in_progress")
p0      = [t for t in pending if "P0" in t.get("labels", [])]
senior  = [t for t in pending if "sprint-task" in t.get("labels", []) and "SENIOR" in t.get("labels", [])]
junior  = [t for t in pending if "sprint-task" in t.get("labels", []) and "SENIOR" not in t.get("labels", [])]
age     = int(time.time()) - d.get("refreshed", 0)
print(f"Sprint: {len(pending)} pending ({len(p0)} P0, {len(senior)} SENIOR, {len(junior)} junior) | {len(done)} done | {len(perm)} permanent")
print(f"In-progress: #{ip}" if ip else "In-progress: none")
print(f"State refreshed: {age}s ago")
PYEOF
}

cmd_count() {
    local FILTER="${1:---sprint}"
    if [ ! -f "$STATE_FILE" ]; then echo "0"; return; fi
    python3 - "$STATE_FILE" "$FILTER" <<'PYEOF'
import json, sys
state_file, filt = sys.argv[1], sys.argv[2]
try:
    d   = json.load(open(state_file))
    ip  = d.get("in_progress")
    def has(t, l): return l in t.get("labels", [])
    av  = [t for t in d["tasks"] if t.get("status") != "done" and t.get("number") != ip]
    if   filt == "--p0":       print(len([t for t in av if has(t,"P0")]))
    elif filt == "--senior":   print(len([t for t in av if has(t,"sprint-task") and has(t,"SENIOR")]))
    elif filt == "--junior":   print(len([t for t in av if has(t,"sprint-task") and not has(t,"SENIOR")]))
    elif filt == "--sprint":   print(len([t for t in av if has(t,"sprint-task")]))
    elif filt == "--permanent":print(len([t for t in av if has(t,"permanent-task")]))
    elif filt == "--bugs":
        # P1/P2 bugs not yet approved (no sprint-task) and not already waiting for review
        def needs_investigation(t):
            lbls = t.get("labels", [])
            return ("bug" in lbls and ("P1" in lbls or "P2" in lbls)
                    and "sprint-task" not in lbls and "needs-review" not in lbls)
        print(len([t for t in av if needs_investigation(t)]))
    else:                      print(len(av))
except Exception: print(0)
PYEOF
}

cmd_planning_due() {
    # Keys off last-planning-time, not last-review-time. Each timestamp
    # gates its own activity; coupling them means any break in one flow
    # silently starves the other.
    local LAST
    LAST=$(cat "$LAST_PLANNING_FILE" 2>/dev/null || echo "0")
    local NOW
    NOW=$(date +%s)
    local HOURS_SINCE=$(( (NOW - LAST) / 3600 ))
    if [ "$HOURS_SINCE" -ge 6 ]; then
        exit 0  # planning due
    else
        exit 1  # not due
    fi
}

cmd_planning_done() {
    date +%s > "$LAST_PLANNING_FILE"
    echo "Recorded planning time"
}

# ── Dispatch ──────────────────────────────────────────────────────────────────

CMD="${1:-status}"
shift 2>/dev/null || true

case "$CMD" in
    refresh)        cmd_refresh ;;
    next)           cmd_next "${1:---any}" ;;
    claim)          cmd_claim "$1" ;;
    done)           cmd_done "$1" "${2:-}" ;;
    unclaim)        cmd_unclaim "$1" ;;
    session-done)      cmd_session_done "$1" ;;
    start-session)     cmd_start_session ;;
    reset-sprint-done) cmd_reset_sprint_done ;;
    clear)             cmd_clear ;;
    status)            cmd_status ;;
    count)             cmd_count "${1:---sprint}" ;;
    planning-due)      cmd_planning_due ;;
    planning-done)     cmd_planning_done ;;
    *)
        echo "Unknown command: $CMD" >&2
        echo "Commands: refresh, next, claim, done, unclaim, session-done, reset-sprint-done, clear, status, count, planning-due, planning-done" >&2
        exit 1
        ;;
esac
