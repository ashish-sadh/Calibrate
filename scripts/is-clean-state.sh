#!/bin/bash
# is-clean-state.sh — the "complete unit of work" gate.
#
# Exit 0 iff main is in a publishable / claimable state. The rule: every
# triggered action (TestFlight publish, next-task claim) calls this first
# and skips quietly when it returns nonzero. The point is NEVER to gate
# work — only to gate user-visible side effects (releases, claims that
# would inherit a broken state).
#
# Design contract (issue #907):
#   - Always returns within a few seconds. Every sub-check is wrapped in a
#     short timeout (`guarded`); on timeout it adds a clear dirty reason
#     instead of hanging.
#   - NEVER runs `swift test` inline. Tier-0 is read-only on the shared cache
#     that `drift-mcp verify_tier0_passing` refreshes out-of-band. A missing
#     or stale cache reports `tier0_unknown` (non-blocking) rather than
#     blocking on a minutes-long live run.
#   - In --report mode it ALWAYS emits JSON, and `dirty_reasons` is never
#     empty when the exit code is nonzero (so callers never see a reasonless
#     clean:false).
#
# Checks:
#   1. git status --porcelain is empty (working tree clean)
#   2. HEAD's associated issue has <verifier_verdict decision="PASS"/> in comments
#      (skipped if HEAD commit doesn't reference an issue — e.g., chore commits
#      from bumps, docs, infra)
#   3. ~/drift-state/in-progress-issue is empty or its issue is closed
#   4. Tier-0 tests pass on HEAD (cache-only; see contract above)
#
# Flags:
#   --report   emit JSON to stdout describing each check's status
#
# Env:
#   DRIFT_GATE_TIMEOUT       per-sub-check timeout in seconds (default 8)
#   DRIFT_TIER0_CACHE_FILE   tier-0 cache path (default /tmp/drift_mcp_tier0_cache.json,
#                            the path drift-mcp verify.py writes)
#   DRIFT_TIER0_CACHE_TTL    tier-0 cache freshness window in seconds (default 300)
#
# Usage:
#   is-clean-state.sh && /testflight-publish
#   is-clean-state.sh --report  # for the MCP tool
#
# NOTE: no `set -e`. The exit code is derived explicitly from DIRTY_REASONS at
# the end; `set -e` used to kill the script mid-check (e.g. when an external
# timeout wrapper fired during the old inline `swift test`) BEFORE it could
# emit the --report JSON, producing an empty stdout that surfaced as a
# clean:false with no reasons. Each sub-check now captures its own exit code.

REPORT=0
[ "${1:-}" = "--report" ] && REPORT=1

GATE_TIMEOUT="${DRIFT_GATE_TIMEOUT:-8}"
TIER0_CACHE_FILE="${DRIFT_TIER0_CACHE_FILE:-/tmp/drift_mcp_tier0_cache.json}"
TIER0_CACHE_TTL="${DRIFT_TIER0_CACHE_TTL:-300}"

DIRTY_REASONS=()
CHECKS_JSON=""

# Pick a timeout binary if one exists; else run the command directly (the
# fast-return guarantee still holds because Tier-0 is cache-only — the only
# historically minutes-long check is gone).
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_BIN="gtimeout"
else
    TIMEOUT_BIN=""
fi

# guarded <secs> <cmd...> — run cmd with a wall-clock cap. Returns the command's
# exit code, or 124 if it timed out (matching coreutils `timeout`).
guarded() {
    local secs="$1"
    shift
    if [ -n "$TIMEOUT_BIN" ]; then
        "$TIMEOUT_BIN" "$secs" "$@"
    else
        "$@"
    fi
}

add_check() {
    local name="$1"
    local pass="$2"
    local detail="${3:-}"
    if [ "$pass" = "false" ]; then
        DIRTY_REASONS+=("$name: $detail")
    fi
    if [ -n "$CHECKS_JSON" ]; then
        CHECKS_JSON+=","
    fi
    CHECKS_JSON+="\"$name\":{\"pass\":$pass"
    if [ -n "$detail" ]; then
        # crude json escape
        escaped=$(echo "$detail" | sed 's/"/\\"/g')
        CHECKS_JSON+=",\"detail\":\"$escaped\""
    fi
    CHECKS_JSON+="}"
}

# === Check 1: working tree clean ===
PORCELAIN=$(guarded "$GATE_TIMEOUT" git status --porcelain 2>/dev/null)
RC=$?
if [ $RC -eq 124 ]; then
    add_check "working_tree" "false" "git status check timed out after ${GATE_TIMEOUT}s"
elif [ -z "$PORCELAIN" ]; then
    add_check "working_tree" "true"
else
    SNIPPET=$(echo "$PORCELAIN" | head -3 | tr '\n' '|')
    add_check "working_tree" "false" "uncommitted: $SNIPPET"
fi

# === Check 2: HEAD's issue has PASS verdict ===
HEAD_SUBJECT=$(git log -1 --format=%s 2>/dev/null || echo "")
# Try to extract issue ref like "(#123)" or "fixes #123"
ISSUE_REF=$(echo "$HEAD_SUBJECT" | grep -oE "#[0-9]+" | head -1 | tr -d '#' || true)
if [ -z "$ISSUE_REF" ]; then
    # No issue ref → can't check verdict; treat as PASS (chore/docs/infra commits)
    add_check "head_verdict" "true" "no issue ref in HEAD subject; treated as PASS"
else
    COMMENTS=$(guarded "$GATE_TIMEOUT" gh issue view "$ISSUE_REF" --json comments --jq '.comments[].body' 2>/dev/null)
    RC=$?
    if [ $RC -eq 124 ]; then
        add_check "head_verdict" "false" "gh verdict check for #$ISSUE_REF timed out after ${GATE_TIMEOUT}s"
    elif echo "$COMMENTS" | grep -q '<verifier_verdict[^>]*decision="PASS"'; then
        add_check "head_verdict" "true" "issue #$ISSUE_REF has PASS verdict"
    else
        add_check "head_verdict" "false" "issue #$ISSUE_REF has no PASS verdict"
    fi
fi

# === Check 3: no claim in flight ===
IN_PROGRESS_FILE="$HOME/drift-state/in-progress-issue"
if [ ! -f "$IN_PROGRESS_FILE" ] || [ -z "$(cat "$IN_PROGRESS_FILE" 2>/dev/null)" ]; then
    add_check "no_claim_in_flight" "true"
else
    IN_PROGRESS_ISSUE=$(cat "$IN_PROGRESS_FILE")
    STATE=$(guarded "$GATE_TIMEOUT" gh issue view "$IN_PROGRESS_ISSUE" --json state --jq .state 2>/dev/null)
    RC=$?
    if [ $RC -eq 124 ]; then
        # Can't confirm the claim is closed → conservatively treat as in-flight.
        add_check "no_claim_in_flight" "false" "gh state check for #$IN_PROGRESS_ISSUE timed out after ${GATE_TIMEOUT}s"
    elif [ "$STATE" = "CLOSED" ]; then
        add_check "no_claim_in_flight" "true" "stale file references closed #$IN_PROGRESS_ISSUE"
    else
        add_check "no_claim_in_flight" "false" "session has #$IN_PROGRESS_ISSUE claimed"
    fi
fi

# === Check 4: tier-0 tests pass (cache-ONLY; never runs swift test inline) ===
# Reads the shared cache that drift-mcp `verify_tier0_passing` writes
# (verify.py: json.dumps → float "at" with ": " spacing). A missing / stale /
# unparseable cache is NON-blocking: report tier0_unknown and let the heavier
# gates (preflight-check.sh, the PASS-verdict commit gate, the session's own
# Tier-0 run) protect the actual side effects.
NOW=$(date +%s)
if [ ! -f "$TIER0_CACHE_FILE" ]; then
    add_check "tier0_tests" "true" "tier0_unknown: cache missing ($TIER0_CACHE_FILE); refresh via verify_tier0_passing"
else
    # Robust-parse the float "at" (tolerate the ": " spacing json.dumps emits)
    # and truncate to whole seconds for integer age math.
    CACHED_AT=$(grep -oE '"at"[[:space:]]*:[[:space:]]*[0-9.]+' "$TIER0_CACHE_FILE" 2>/dev/null | head -1 | grep -oE '[0-9.]+' | head -1)
    CACHED_PASSING=$(grep -oE '"passing"[[:space:]]*:[[:space:]]*(true|false)' "$TIER0_CACHE_FILE" 2>/dev/null | head -1 | grep -oE '(true|false)' | head -1)
    CACHED_AT_INT="${CACHED_AT%.*}"
    if [ -z "$CACHED_AT_INT" ] || [ -z "$CACHED_PASSING" ]; then
        add_check "tier0_tests" "true" "tier0_unknown: cache unparseable ($TIER0_CACHE_FILE)"
    else
        AGE=$((NOW - CACHED_AT_INT))
        if [ $AGE -ge "$TIER0_CACHE_TTL" ]; then
            add_check "tier0_tests" "true" "tier0_unknown: cache stale (${AGE}s > ${TIER0_CACHE_TTL}s); refresh via verify_tier0_passing"
        elif [ "$CACHED_PASSING" = "true" ]; then
            add_check "tier0_tests" "true" "cached pass (${AGE}s old)"
        else
            add_check "tier0_tests" "false" "tier0 cached fail (${AGE}s old)"
        fi
    fi
fi

if [ $REPORT -eq 1 ]; then
    DIRTY_JSON=""
    for r in "${DIRTY_REASONS[@]}"; do
        if [ -n "$DIRTY_JSON" ]; then DIRTY_JSON+=","; fi
        escaped=$(echo "$r" | sed 's/"/\\"/g')
        DIRTY_JSON+="\"$escaped\""
    done
    echo "{\"checks\":{$CHECKS_JSON},\"dirty_reasons\":[$DIRTY_JSON]}"
fi

# Exit 0 if no dirty reasons; 1 otherwise. dirty_reasons is non-empty whenever
# this is nonzero, by construction.
if [ ${#DIRTY_REASONS[@]} -eq 0 ]; then
    exit 0
else
    exit 1
fi
