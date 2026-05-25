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
#   planning-due                         — exit 0 if 24+ hours since last planning
#   planning-done                        — stamp last-planning-time = now

set -euo pipefail

# shellcheck source=lib/atomic-write.sh
source "$(dirname "$0")/lib/atomic-write.sh"

STATE_FILE="$HOME/drift-state/sprint-state.json"
LOCK_FILE="$HOME/drift-state/sprint-state.json.lock"
LAST_REVIEW_FILE="$HOME/drift-state/last-review-time"
LAST_PLANNING_FILE="$HOME/drift-state/last-planning-time"
WORK_DIR="/Users/ashishsadh/workspace/Drift"

mkdir -p "$HOME/drift-state"

# ── gh helpers ────────────────────────────────────────────────────────────────
#
# Audit (2026-04-25) found cmd_claim/done/unclaim/session-done all used
# `gh ... 2>/dev/null || true` — silent failure. Local state would mark
# "done" while GitHub stayed open, and discipline failures were invisible.
# Pattern: run gh, capture stderr, retry once on transient failures, log
# loudly on hard failures. Returns 0 on success, non-zero otherwise.

GH_ERR_LOG="${GH_ERR_LOG:-$HOME/drift-state/gh-errors.log}"

gh_loud() {
    # gh_loud <description> -- <gh args...>
    local desc="$1"; shift
    [ "$1" = "--" ] && shift
    local err
    if err=$(gh "$@" 2>&1 >/dev/null); then
        return 0
    fi
    # Retry once on transient errors (rate limit, 5xx, network)
    if echo "$err" | grep -qiE "rate limit|HTTP 5|timeout|temporarily unavailable|connection reset"; then
        sleep 2
        if err=$(gh "$@" 2>&1 >/dev/null); then
            return 0
        fi
    fi
    # Hard failure — log loudly so it doesn't go silent
    {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] gh_loud FAILED: $desc"
        echo "  cmd: gh $*"
        echo "  err: $err"
    } >> "$GH_ERR_LOG"
    echo "WARN: gh $desc failed — see $GH_ERR_LOG" >&2
    return 1
}

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

    # Fetch ONE unfiltered list, then derive every bucket via jq. The previous
    # code did 8 separate `gh issue list --label X` calls — each routed through
    # GitHub's search index, which has a propagation lag (typically <5 min,
    # observed up to 27+ min on 2026-05-07). Newly-labeled P0 bugs (#650, #651)
    # were invisible to refresh until the index caught up, hiding both from
    # sprint-state for nearly half an hour. Client-side filtering bypasses the
    # search index entirely — slower per call but immune to lag.
    # --limit 200 covers the cap of 100 sprint-tasks plus permanents/design
    # docs/bugs comfortably.
    gh issue list --state open --limit 200 --json number,title,labels,updatedAt \
        > "$TMP_DIR/all.json" 2>/dev/null || echo "[]" > "$TMP_DIR/all.json"

    # Each derivation: one jq pass over all.json. Keep `status: "pending"` for
    # sprint/queue tasks, `status: "permanent"` for permanents (rotation
    # logic depends on the tag). Permanents preserve updatedAt for ordering.
    jq '[.[] | (.labels|map(.name)) as $L
        | select(($L|index("bug")) and ($L|index("P0")))
        | {number, title, labels: $L, status: "pending"}]' \
        "$TMP_DIR/all.json" > "$TMP_DIR/p0_bugs.json" 2>/dev/null || echo "[]" > "$TMP_DIR/p0_bugs.json"

    jq '[.[] | (.labels|map(.name)) as $L
        | select(($L|index("feature-request")) and ($L|index("P0")))
        | {number, title, labels: $L, status: "pending"}]' \
        "$TMP_DIR/all.json" > "$TMP_DIR/p0_feats.json" 2>/dev/null || echo "[]" > "$TMP_DIR/p0_feats.json"

    jq '[.[] | (.labels|map(.name)) as $L
        | select(($L|index("sprint-task")) and ($L|index("SENIOR")))
        | {number, title, labels: $L, status: "pending"}]' \
        "$TMP_DIR/all.json" > "$TMP_DIR/senior.json" 2>/dev/null || echo "[]" > "$TMP_DIR/senior.json"

    # Junior = sprint-task without SENIOR (matches old --label sprint-task + jq filter)
    jq '[.[] | (.labels|map(.name)) as $L
        | select(($L|index("sprint-task")) and (($L|index("SENIOR")) | not))
        | {number, title, labels: $L, status: "pending"}]' \
        "$TMP_DIR/all.json" > "$TMP_DIR/junior.json" 2>/dev/null || echo "[]" > "$TMP_DIR/junior.json"

    jq '[.[] | (.labels|map(.name)) as $L
        | select($L|index("design-doc"))
        | {number, title, labels: $L, status: "pending"}]' \
        "$TMP_DIR/all.json" > "$TMP_DIR/design_docs.json" 2>/dev/null || echo "[]" > "$TMP_DIR/design_docs.json"

    jq '[.[] | (.labels|map(.name)) as $L
        | select(($L|index("bug")) and ($L|index("P1")))
        | {number, title, labels: $L, status: "pending"}]' \
        "$TMP_DIR/all.json" > "$TMP_DIR/p1_bugs.json" 2>/dev/null || echo "[]" > "$TMP_DIR/p1_bugs.json"

    jq '[.[] | (.labels|map(.name)) as $L
        | select(($L|index("bug")) and ($L|index("P2")))
        | {number, title, labels: $L, status: "pending"}]' \
        "$TMP_DIR/all.json" > "$TMP_DIR/p2_bugs.json" 2>/dev/null || echo "[]" > "$TMP_DIR/p2_bugs.json"

    jq '[.[] | (.labels|map(.name)) as $L
        | select($L|index("permanent-task"))
        | {number, title, labels: $L, status: "permanent", updatedAt}]' \
        "$TMP_DIR/all.json" > "$TMP_DIR/perm.json" 2>/dev/null || echo "[]" > "$TMP_DIR/perm.json"

    local NEW_STATE
    NEW_STATE=$(python3 - <<PYEOF
import json, os

tmp = "$TMP_DIR"
def load(f):
    try:
        return json.load(open(f))
    except Exception:
        return []

p0_bugs     = load(f"{tmp}/p0_bugs.json")
p1_bugs     = load(f"{tmp}/p1_bugs.json")
p2_bugs     = load(f"{tmp}/p2_bugs.json")
senior      = load(f"{tmp}/senior.json")
junior      = load(f"{tmp}/junior.json")
perm        = load(f"{tmp}/perm.json")
design_docs = load(f"{tmp}/design_docs.json")

seen, tasks = set(), []
for t in p0_bugs + p1_bugs + p2_bugs + senior + junior + perm + design_docs:
    if t["number"] not in seen:
        seen.add(t["number"])
        tasks.append(t)

state = {"version": 1, "refreshed": $NOW, "in_progress": None, "tasks": tasks, "session_tasks": 0}
try:
    existing = json.load(open("$STATE_FILE"))
    state["in_progress"] = existing.get("in_progress")
    state["session_tasks"] = existing.get("session_tasks", 0)
    # Preserve claim_started — required for stale-claim detection in
    # self-improve-watchdog. Without this, every watchdog refresh tick
    # nukes the timestamp and the 1h auto-flag never fires. (Bug
    # observed 2026-04-26: in_progress=477 had claim_started=null
    # because refresh dropped it.)
    if existing.get("claim_started"):
        state["claim_started"] = existing.get("claim_started")
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
    # Accept --claim anywhere in args so both
    #   next --senior --claim
    #   next --claim --senior
    # work. Any other arg becomes the filter mode.
    local FILTER="--any"
    local DO_CLAIM=0
    for arg in "$@"; do
        if [ "$arg" = "--claim" ]; then
            DO_CLAIM=1
        elif [ -n "$arg" ]; then
            FILTER="$arg"
        fi
    done

    local RESULT
    RESULT=$(python3 - "$FILTER" "$STATE_FILE" <<'PYEOF'
import json, sys, os

filter_mode = sys.argv[1]
state_file  = sys.argv[2]

try:
    state = json.load(open(state_file))
except Exception:
    print("none"); sys.exit(0)

tasks       = state.get("tasks", [])
in_progress = state.get("in_progress")

def has(t, label): return label in t.get("labels", [])

# Session budget: ONE implementation task per session. After it completes,
# session exits and watchdog respawns within ~60s. Was 10 → 1 (2026-05-12).
# Rationale: at 10 tasks/session the model's context bloated with stale state
# from prior tasks — task N got worse output than task 1 because of carry-over
# (irrelevant file reads, prior plan comments, prior QA verdicts polluting the
# attention). Per-session overhead (~60s respawn + 5min context-load) is small
# vs task wall-time (30-60min including iOS sim tests) so the cost is fine.
# Tests still override via DRIFT_TEST_BUDGET env var.
# Not enforced for --any (used by tests / planning).
_BUDGET = int(os.environ.get("DRIFT_TEST_BUDGET", "1"))
if filter_mode in ("--senior", "--junior"):
    if state.get("session_tasks", 0) >= _BUDGET:
        print("none"); sys.exit(0)

# Skip done, currently claimed, and needs-human (auto-applied after 3
# abandons per the rewrite plan — issues with this label have proven
# un-actionable by autopilot and need human triage before re-entering
# the queue. Without this filter, the router serves them on every spawn
# and they accumulate dozens of abandon comments (#801 reached 55).
# Reuses the existing has() helper defined above; labels are bare strings
# in sprint-state.json, not {name: ...} dicts.)
available = [t for t in tasks
             if t.get("status") != "done"
             and t.get("number") != in_progress
             and not has(t, "needs-human")]

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

# ── Priority 1.5 (senior + any): P0 SENIOR features ───────────────────────────
# A P0 label on a non-bug means the feature is critical-priority but isn't a
# bug. Without this clause, P0 features were ranked at Priority 2 alongside
# every other SENIOR sprint-task — the P0 label was effectively decorative.
# This jumps them ahead of regular SENIOR features. Reachable from --any too
# so junior queries that touch the senior path still see the elevation.
if filter_mode in ("--senior", "--any"):
    for t in available:
        if has(t, "needs-review"): continue
        if has(t, "sprint-task") and has(t, "SENIOR") and has(t, "P0"):
            print(f"{t['number']} {t['title']}"); sys.exit(0)

# ── Senior-only section ────────────────────────────────────────────────────────
if filter_mode in ("--senior", "--any"):

    # Priority 2: SENIOR-labeled sprint tasks (feature tasks + explicitly SENIOR bugs)
    # P0 SENIOR features already handled by Priority 1.5 above; this picks up
    # non-P0 SENIOR sprint-tasks.
    for t in available:
        if has(t, "needs-review"): continue
        if has(t, "sprint-task") and has(t, "SENIOR"):
            print(f"{t['number']} {t['title']}"); sys.exit(0)

    # Priority 2 (cont): Design-doc issues routed to senior without sprint-task label.
    # Routing conditions (both mean "document needs senior attention"):
    #   - design-doc without doc-ready: document not yet written
    #   - design-doc + approved without implementing: approved, impl tasks not yet spawned
    # Excluded: doc-ready (awaiting PE review) and implementing (impl tasks already exist).
    def is_senior_design_doc(t):
        lbls = t.get("labels", [])
        if "design-doc" not in lbls:
            return False
        if "doc-ready" in lbls:
            return False
        if "implementing" in lbls:
            return False
        return True

    for t in available:
        if has(t, "needs-review"): continue
        if is_senior_design_doc(t):
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

    # Priority 1.9 (#790): Stale junior sprint-tasks. Tasks queued long ago
    # that no junior session has claimed get bumped ahead of fresher work
    # so multi-week-old cuisine/food-DB tasks don't keep losing the lottery
    # to whatever planning just filed.
    #
    # Age proxy: issue NUMBER. sprint-state.json doesn't store createdAt
    # currently; lower numbers are older. The router considers a task
    # "stale" when its number is ≥STALE_DELTA below the max current task
    # number — i.e., it's been queued behind a sliding window of newer
    # tasks. STALE_DELTA=80 picks up tasks roughly ≥5 days old at the
    # current planning cadence (8-12 new tasks/cycle, ~2 cycles/day).
    nums = [t.get("number", 0) for t in available if isinstance(t.get("number"), int)]
    _max_num = max(nums) if nums else 0
    STALE_DELTA = 80
    stale_juniors = [
        t for t in available
        if has(t, "sprint-task") and not has(t, "SENIOR") and not has(t, "bug")
        and not has(t, "needs-review")
        and isinstance(t.get("number"), int)
        and t["number"] < (_max_num - STALE_DELTA)
    ]
    if stale_juniors:
        # Oldest (lowest number) first within the stale bucket.
        stale_juniors.sort(key=lambda t: t["number"])
        t = stale_juniors[0]
        print(f"{t['number']} {t['title']}"); sys.exit(0)

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
)

    # If no task or claim not requested, just print result and return.
    echo "$RESULT"
    if [ "$DO_CLAIM" -ne 1 ] || [ "$RESULT" = "none" ] || [ -z "$RESULT" ]; then
        return 0
    fi

    # Extract task number from "N TITLE" and claim it. Claim output goes
    # to stderr so the stdout contract ("N TITLE" or "none") stays intact
    # for callers that captured `next` before this flag existed.
    local NUM
    NUM=$(echo "$RESULT" | awk '{print $1}')
    if [ -n "$NUM" ]; then
        cmd_claim "$NUM" >&2 || true
    fi
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

        local NOW_TS=$(date +%s)
    python3 - "$STATE_FILE" "$NUM" "$ISSUE_JSON" "$NOW_TS" <<'PYEOF'
import json, sys

state_file  = sys.argv[1]
num         = int(sys.argv[2])
issue_json  = sys.argv[3]
now_ts      = int(sys.argv[4])

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
state["claim_started"] = now_ts  # for stale-claim detection in self-improve-watchdog
with open(state_file, "w") as f:
    json.dump(state, f, indent=2)
print(f"Claimed #{num}")
PYEOF

    rmdir "$LOCK_DIR" 2>/dev/null || true
    trap - EXIT

    # Loud + logged on failure, but non-blocking — local state already
    # claims #N, so the session can proceed even if the GitHub label add
    # fails. The discrepancy will show up in gh-errors.log and the
    # in-progress label may be missing in the UI; both are visible signals
    # rather than silent state divergence.
    gh_loud "add in-progress label on #$NUM" -- issue edit "$NUM" --add-label in-progress || true

    # Resumable warning — surfaces when claiming an issue with `resumable`
    # label set by the watchdog after a prior session crashed mid-work.
    # Without this, sessions ran bare `gh issue view N` (no comments) and
    # missed the WIP file pointers, redoing orientation 6+ times on #515.
    # Print to STDOUT so the model sees it inline with the claim — stderr
    # would be dropped from the session's tool result. Filed as #516.
    #
    # Source of truth = state file (already updated by the Python claim
    # block above). Tests pre-populate state, gh may fail in test envs.
    local IS_RESUMABLE
    IS_RESUMABLE=$(python3 -c "
import json
try:
    state = json.load(open('$STATE_FILE'))
    task = next((t for t in state.get('tasks', []) if t['number'] == $NUM), None)
    print('yes' if task and 'resumable' in task.get('labels', []) else 'no')
except Exception:
    print('no')
")
    if [ "$IS_RESUMABLE" = "yes" ]; then
        echo ""
        echo "⚠️  RESUMABLE — prior session left WIP for #${NUM}. Read context before continuing:"
        echo "    gh issue view ${NUM} --comments"
        echo "    ls -la ~/drift-state/wip/${NUM}.*"
        echo "    git apply ~/drift-state/wip/${NUM}.patch  # or skip + start fresh"
        echo "  Post a comment noting which path you took before implementing."
        echo "  Run \`gh issue edit ${NUM} --remove-label resumable\` after committing."
        echo ""
    fi

    # Surface any orphan WIP from a prior dead session (snapshot_orphan_wip).
    # Even if it's not for this exact issue, the diff may be relevant —
    # senior protocol says read it before redoing work from scratch.
    local LAST_ORPHAN="$HOME/drift-state/wip/last-orphan.patch"
    if [ -L "$LAST_ORPHAN" ] || [ -f "$LAST_ORPHAN" ]; then
        echo ""
        echo "ℹ️  Orphan WIP exists at $LAST_ORPHAN (a prior unclaimed session died with"
        echo "  uncommitted edits). Inspect: git apply --stat $LAST_ORPHAN"
        echo "  If the diff is for this task, apply + continue. If unrelated, ignore + delete."
        echo ""
    fi

    # Reset pre-claim Read budget so the next claim cycle starts fresh.
    rm -f "$HOME/drift-state/preclaim-reads"
}

cmd_done() {
    local NUM="$1"
    local COMMIT="${2:-}"
    if [ -z "$NUM" ]; then echo "Usage: sprint-service.sh done <number> <commit>" >&2; exit 1; fi

    # Fetch labels once — reused by the permanent-task guard and the
    # design-doc guard below.
    local LABELS_JSON
    LABELS_JSON=$(gh issue view "$NUM" --json labels --jq '[.labels[].name]' 2>/dev/null || echo "[]")

    # Design-doc guard: writing the doc is one step in a multi-stage lifecycle
    # (doc-ready → approved → implementing → close). Auto-closing skips human
    # review and impl-task creation. Senior should add doc-ready and stop —
    # but if they call `done` (because senior protocol's recipe is uniform),
    # redirect to that path. Without this, design-doc issues #665 #666 got
    # auto-closed on 2026-05-07 with the doc unreviewed.
    local IS_DESIGN_DOC
    IS_DESIGN_DOC=$(echo "$LABELS_JSON" | jq -r 'index("design-doc") != null' 2>/dev/null || echo "false")
    if [ "$IS_DESIGN_DOC" = "true" ]; then
        local DD_NOTE=""
        if [ -f "/tmp/done-note-$NUM" ]; then
            DD_NOTE=$(cat "/tmp/done-note-$NUM")
            rm -f "/tmp/done-note-$NUM"
        fi
        local DD_REF=""
        [ -n "$COMMIT" ] && DD_REF=" Commit: $COMMIT"
        local DD_COMMENT="Doc-ready. Design doc filed; awaiting human \`approved\` label before impl tasks file.${DD_REF}"
        [ -n "$DD_NOTE" ] && DD_COMMENT="Doc-ready: $DD_NOTE${DD_REF}"
        gh_loud "comment doc-ready on design #$NUM" -- issue comment "$NUM" --body "$DD_COMMENT" || true
        gh_loud "add doc-ready label on #$NUM" -- issue edit "$NUM" --add-label doc-ready || true
        echo "WARN: #$NUM is a design-doc — redirecting 'done' to 'session-done' + doc-ready label. Use 'session-done' next time." >&2
        cmd_session_done "$NUM"
        return
    fi

    # Permanent-task guard: `done` would close the issue, but permanents must
    # recur. PreToolUse hook (guard-permanent-close.sh) can't see internal
    # `gh issue close` calls from this script, so enforce here. Redirect to
    # session-done semantics: post a Progress comment, never close.
    # Without this, closed permanents drained the junior queue and armed the
    # TestFlight/require-claim deadlock (#49 #50 #51 #52 #193, 2026-05-03/04).
    local IS_PERM
    IS_PERM=$(echo "$LABELS_JSON" | jq -r 'index("permanent-task") != null' 2>/dev/null || echo "false")
    if [ "$IS_PERM" = "true" ]; then
        local PROGRESS_NOTE=""
        if [ -f "/tmp/done-note-$NUM" ]; then
            PROGRESS_NOTE=$(cat "/tmp/done-note-$NUM")
            rm -f "/tmp/done-note-$NUM"
        fi
        local PROGRESS_REF=""
        [ -n "$COMMIT" ] && PROGRESS_REF=" Commit: $COMMIT"
        local PROGRESS_COMMENT="Progress.${PROGRESS_REF}"
        [ -n "$PROGRESS_NOTE" ] && PROGRESS_COMMENT="Progress: $PROGRESS_NOTE${PROGRESS_REF}"
        gh_loud "comment progress on permanent #$NUM" -- issue comment "$NUM" --body "$PROGRESS_COMMENT" || true
        echo "WARN: #$NUM is a permanent-task — redirecting 'done' to 'session-done'. Use 'session-done' next time." >&2
        cmd_session_done "$NUM"
        return
    fi

    local NOTE=""
    if [ -f "/tmp/done-note-$NUM" ]; then
        NOTE=$(cat "/tmp/done-note-$NUM")
        rm -f "/tmp/done-note-$NUM"
    fi

    local COMMIT_REF=""
    [ -n "$COMMIT" ] && COMMIT_REF=" Commit: $COMMIT"

    local COMMENT="Done.${COMMIT_REF}"
    [ -n "$NOTE" ] && COMMENT="$NOTE${COMMIT_REF}"

    # Reachability guard: refuse to close the issue if the commit isn't on
    # origin/main. Drift is trunk-based for sprint tasks (see program.md);
    # branches are reserved for design-doc / report / review. Sessions that
    # drift off-protocol and use a feature branch (e.g. PR #671 / #669,
    # 2026-05-08) leave the fix unmerged while cmd_done closes the issue —
    # the work looks shipped but isn't. Refusing the close forces the
    # session to either merge the PR or use session-done.
    #
    # The test harness passes synthetic hashes ("abc123", "hash999", etc.)
    # that aren't real git objects — `cat-file -e` returns false, and we
    # skip the reachability check in that case (preserves harness behavior).
    if [ -n "$COMMIT" ] && git -C "$WORK_DIR" cat-file -e "$COMMIT" 2>/dev/null; then
        # Refresh remote refs so the check sees freshly-pushed-to-origin
        # commits (low-cost, just updates origin/main).
        git -C "$WORK_DIR" fetch origin main --quiet 2>/dev/null || true
        if ! git -C "$WORK_DIR" merge-base --is-ancestor "$COMMIT" origin/main 2>/dev/null; then
            local CURRENT_BRANCH
            CURRENT_BRANCH=$(git -C "$WORK_DIR" branch --show-current 2>/dev/null || echo "?")
            cat >&2 <<EOF
REFUSED: commit $COMMIT is not on origin/main (current branch: $CURRENT_BRANCH).

Drift is trunk-based for sprint tasks. Branches are only for:
  design/<N>-<slug>   — design docs (PR with --label design-doc)
  report/exec-DATE    — daily exec reports (PR with --label report)
  review/cycle-N      — product reviews (PR with --label report)

If you used a feature branch by mistake:
  - Merge the PR, then re-run done: gh pr merge <PR> --squash --delete-branch && git checkout main && git pull && sprint-service.sh done $NUM \$(git rev-parse HEAD)
  - Or keep work-in-progress: sprint-service.sh session-done $NUM   (does not close)

Refusing to close #$NUM until commit reaches origin/main.
EOF
            exit 2
        fi
    fi

    # Defensive check: if the GitHub issue is already CLOSED, skip the
    # duplicate comment + close calls. Prevents the "Done. Commit: reconcile"
    # noise pattern observed on #440 (2026-04-26) where a session worked on
    # a closed issue and posted spurious comments. Local state still updates
    # and budget still increments — that's what callers depend on.
    local CURRENT_STATE
    CURRENT_STATE=$(gh issue view "$NUM" --json state --jq '.state' 2>/dev/null || echo "OPEN")
    if [ "$CURRENT_STATE" = "CLOSED" ]; then
        echo "Issue #$NUM is already CLOSED on GitHub — skipping duplicate comment+close, just clearing local state." >&2
        gh_loud "remove in-progress label on closed #$NUM" -- issue edit "$NUM" --remove-label in-progress || true
    else
        # All three calls are loud (logged to gh-errors.log on failure) but
        # non-blocking: we still update local state + increment budget so the
        # session can progress. Failed closes leave the GitHub issue open and
        # the WARN visible — the watchdog or human can re-close them. This
        # preserves the budget-bookkeeping semantics test-drift-control.sh expects.
        gh_loud "comment on #$NUM" -- issue comment "$NUM" --body "$COMMENT" || true
        gh_loud "close #$NUM" -- issue close "$NUM" || true
        gh_loud "remove in-progress label on #$NUM" -- issue edit "$NUM" --remove-label in-progress || true
    fi

    python3 - "$STATE_FILE" "$NUM" <<'PYEOF'
import json, sys
state_file, num = sys.argv[1], int(sys.argv[2])
try:
    d = json.load(open(state_file))
    d["in_progress"] = None
    d.pop("claim_started", None)
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

    # Clean up any WIP snapshot for this issue — work is shipped, no need to
    # keep the patch+tarball around. Watchdog snapshot_wip_if_in_progress
    # writes these every tick while the issue is in_progress.
    rm -f "$HOME/drift-state/wip/${NUM}.patch" "$HOME/drift-state/wip/${NUM}.untracked.tar.gz" 2>/dev/null

    # Clean up plan-posted cache for this issue so a future re-claim of the
    # same #N starts fresh on the nudge timer (the comment is still on
    # GitHub; nudge hook will re-detect it on first check).
    rm -f "$HOME/drift-state/plan-posted/${NUM}" 2>/dev/null

    echo "Closed #$NUM"
}

cmd_unclaim() {
    local NUM="$1"
    if [ -z "$NUM" ]; then echo "Usage: sprint-service.sh unclaim <number>" >&2; exit 1; fi

    gh_loud "remove in-progress label on #$NUM" -- issue edit "$NUM" --remove-label in-progress || true

    python3 - "$STATE_FILE" "$NUM" <<'PYEOF'
import json, sys
state_file, num = sys.argv[1], int(sys.argv[2])
try:
    d = json.load(open(state_file))
    if d.get("in_progress") == num:
        d["in_progress"] = None
        d.pop("claim_started", None)
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
    gh_loud "remove in-progress label on #$NUM (session-done)" -- issue edit "$NUM" --remove-label in-progress || true

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
    if d.get("in_progress") == num:
        d["in_progress"] = None
        d.pop("claim_started", None)
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
        gh_loud "clear in-progress label on #$N" -- issue edit "$N" --remove-label in-progress || true
    done

    # Also check state file for claimed task
    local STATE_IP
    STATE_IP=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('in_progress') or '')" 2>/dev/null || true)
    if [ -n "$STATE_IP" ] && [ "$STATE_IP" != "None" ]; then
        gh_loud "clear in-progress label on #$STATE_IP (from state)" -- issue edit "$STATE_IP" --remove-label in-progress || true
    fi

    python3 - "$STATE_FILE" <<'PYEOF'
import json, sys
state_file = sys.argv[1]
try:
    d = json.load(open(state_file))
    d["in_progress"] = None
    d.pop("claim_started", None)
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
def _is_senior_design_doc(t):
    lbls = t.get("labels", [])
    return "design-doc" in lbls and "doc-ready" not in lbls and "implementing" not in lbls
p0      = [t for t in pending if "P0" in t.get("labels", [])]
senior  = [t for t in pending if ("sprint-task" in t.get("labels", []) and "SENIOR" in t.get("labels", [])) or _is_senior_design_doc(t)]
junior  = [t for t in pending if "sprint-task" in t.get("labels", []) and "SENIOR" not in t.get("labels", [])]
age     = int(time.time()) - d.get("refreshed", 0)
print(f"Sprint: {len(pending)} pending ({len(p0)} P0, {len(senior)} SENIOR, {len(junior)} junior) | {len(done)} done | {len(perm)} permanent")
print(f"In-progress: #{ip}" if ip else "In-progress: none")
print(f"State refreshed: {age}s ago")
PYEOF
}

# ── Epic awareness (phase 2a, 2026-05-25) ─────────────────────────────────────
#
# Spec-driven workflow primitive: an open issue with the `epic` label has a
# body containing `<epic id="..." status="..."><goal>...</goal><subtasks>...
# <task issue="N" .../></subtasks>...</epic>` plus per-task status entries.
# Sub-tasks remain regular sprint-tasks; the epic is *context*, not claimable.
#
# `epic <subtask-issue-N>` prints the parent epic's number, status, and goal
# when N appears in any open epic's <subtasks>. Senior reads it after claim so
# the arc goal is in working context (see Docs/refactor/harness-phase-2-workflows.md).
#
# Live `gh` lookup — no state-file schema change in v1. Future v2: hoist into
# `cmd_refresh` so `sprint-state.json` carries an `epics` block.
cmd_epic() {
    local SUBTASK="${1:-}"
    if [ -z "$SUBTASK" ]; then
        echo "usage: sprint-service.sh epic <subtask-issue-number>" >&2
        return 1
    fi
    # Bodies routinely contain triple-quotes / XML / newlines that break
    # heredoc interpolation. Pass via env var (gh JSON is one line per
    # issue, but the body is multi-line within the JSON string).
    local OPEN_EPICS_FILE
    OPEN_EPICS_FILE=$(mktemp)
    gh issue list --state open --label epic --json number,title,body --limit 50 \
        > "$OPEN_EPICS_FILE" 2>/dev/null || echo "[]" > "$OPEN_EPICS_FILE"
    EPIC_FILE="$OPEN_EPICS_FILE" python3 - "$SUBTASK" <<'PYEOF'
import json, os, re, sys
subtask = sys.argv[1].lstrip("#")
with open(os.environ["EPIC_FILE"]) as f:
    epics = json.load(f)
match = None
for ep in epics:
    body = ep.get("body", "") or ""
    # <task issue="NNN" ...> — number may be quoted or bare, with or without `#`.
    for m in re.finditer(r'<task\s+[^>]*issue=["\']?#?(\d+)', body):
        if m.group(1) == subtask:
            match = ep
            break
    if match: break
if not match:
    print("none")
    sys.exit(0)
goal = ""
gm = re.search(r"<goal>(.*?)</goal>", match["body"], re.DOTALL)
if gm:
    goal = re.sub(r"\s+", " ", gm.group(1)).strip()
print(f"epic_number={match['number']}")
print(f"epic_title={match['title']}")
print(f"epic_goal={goal}")
PYEOF
    rm -f "$OPEN_EPICS_FILE"
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
    def is_senior_design_doc(t):
        lbls = t.get("labels", [])
        return "design-doc" in lbls and "doc-ready" not in lbls and "implementing" not in lbls
    if   filt == "--p0":       print(len([t for t in av if has(t,"P0")]))
    elif filt == "--senior":   print(len([t for t in av if (has(t,"sprint-task") and has(t,"SENIOR")) or is_senior_design_doc(t)]))
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
    local SECONDS_SINCE=$(( NOW - LAST ))
    # 24h cadence — was 12h, raised again to once-per-day. Planning is
    # high-cost senior work and most days don't accumulate enough new
    # priority signal in 12h to warrant re-planning. Product review rides
    # on the same trigger (see report-service.sh review-due).
    if [ "$SECONDS_SINCE" -ge 86400 ]; then
        exit 0  # planning due
    else
        exit 1  # not due
    fi
}

cmd_planning_done() {
    atomic_write "$LAST_PLANNING_FILE" "$(date +%s)"
    echo "Recorded planning time"
}

# Planning-time context — emits whether the planning session should also do a
# product review this round. Folded here so review has a single cadence (sprint
# planning), not a separate timer that drifts.
#
# As of cycle 10950, the trigger is wall-clock (PRODUCT_REVIEW_INTERVAL_DAYS,
# default 5) rather than cycle-count. Cycle-count stats are still emitted for
# telemetry — humans like seeing "23 cycles since last review" in exec briefings
# — but they are no longer the gate. See report-service.sh cmd_review_due.
#
# Usage: scripts/sprint-service.sh planning-context
# Outputs (one line each, key=value):
#   cycle_count=<int>
#   last_review_cycle=<int>
#   cycles_since_last_review=<int>        # telemetry only
#   last_review_time=<unix-seconds>
#   days_since_last_review=<int>          # the trigger
#   review_due=<true|false>               # true when days_since_last_review >= review_interval_days
#   review_interval_days=<int>            # default 5, override via PRODUCT_REVIEW_INTERVAL_DAYS env
#   review_cycle_interval=<int>           # legacy telemetry only — no longer the trigger
cmd_planning_context() {
    local INTERVAL_DAYS="${PRODUCT_REVIEW_INTERVAL_DAYS:-5}"
    local LEGACY_CYCLE_INTERVAL="${PRODUCT_REVIEW_CYCLE_INTERVAL:-20}"
    local CYCLE
    CYCLE=$(cat "$HOME/drift-state/commit-counter" 2>/dev/null || echo "0")
    local LAST_REVIEW_CYCLE
    LAST_REVIEW_CYCLE=$(cat "$HOME/drift-state/last-review-cycle" 2>/dev/null || echo "0")
    local CYCLES_SINCE=$(( CYCLE - LAST_REVIEW_CYCLE ))
    [ "$CYCLES_SINCE" -lt 0 ] && CYCLES_SINCE=0

    local LAST_REVIEW_TIME
    LAST_REVIEW_TIME=$(cat "$HOME/drift-state/last-review-time" 2>/dev/null || echo "0")
    local NOW
    NOW=$(date +%s)
    local SECONDS_SINCE=$(( NOW - LAST_REVIEW_TIME ))
    [ "$SECONDS_SINCE" -lt 0 ] && SECONDS_SINCE=0
    local DAYS_SINCE=$(( SECONDS_SINCE / 86400 ))

    local INTERVAL_SECONDS=$(( INTERVAL_DAYS * 86400 ))
    local DUE="false"
    [ "$SECONDS_SINCE" -ge "$INTERVAL_SECONDS" ] && DUE="true"

    echo "cycle_count=$CYCLE"
    echo "last_review_cycle=$LAST_REVIEW_CYCLE"
    echo "cycles_since_last_review=$CYCLES_SINCE"
    echo "last_review_time=$LAST_REVIEW_TIME"
    echo "days_since_last_review=$DAYS_SINCE"
    echo "review_due=$DUE"
    echo "review_interval_days=$INTERVAL_DAYS"
    echo "review_cycle_interval=$LEGACY_CYCLE_INTERVAL"
}

# ── Dispatch ──────────────────────────────────────────────────────────────────

CMD="${1:-status}"
shift 2>/dev/null || true

case "$CMD" in
    refresh)        cmd_refresh ;;
    next)           cmd_next "$@" ;;
    claim)          cmd_claim "$1" ;;
    done)           cmd_done "$1" "${2:-}" ;;
    unclaim)        cmd_unclaim "$1" ;;
    session-done)      cmd_session_done "$1" ;;
    start-session)     cmd_start_session ;;
    reset-sprint-done) cmd_reset_sprint_done ;;
    clear)             cmd_clear ;;
    status)            cmd_status ;;
    count)             cmd_count "${1:---sprint}" ;;
    epic)              cmd_epic "${1:-}" ;;
    planning-due)      cmd_planning_due ;;
    planning-done)     cmd_planning_done ;;
    planning-context)  cmd_planning_context ;;
    *)
        echo "Unknown command: $CMD" >&2
        echo "Commands: refresh, next, claim, done, unclaim, session-done, reset-sprint-done, clear, status, count, epic, planning-due, planning-done, planning-context" >&2
        exit 1
        ;;
esac
