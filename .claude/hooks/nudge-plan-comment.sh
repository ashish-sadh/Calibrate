#!/bin/bash
# PreToolUse hook — Plan comment enforcement.
#
# Two modes (selected by tool_name):
#
# 1. SOFT NUDGE on Bash|Read|Grep|Glob — escalating additionalContext that
#    reminds the model to post a Plan comment. Does NOT block.
#
# 2. HARD BLOCK on Edit|Write — exits 2 once EDIT_BUDGET Edit/Write calls
#    have happened on a claimed issue without a <plan> XML block appearing
#    in any comment. Surfaced by #801 (senior spent 21 min iterating tests
#    without posting any plan; the eventual commit would have been
#    rejected by require-qa-verdict.sh, but only after the wasted iteration).
#
# Detects both the new XML contract (`<plan>` tag) and the legacy markdown
# "Plan:" / "Approach:" headings so this works through the migration.
#
# Skips entirely when:
#   - DRIFT_AUTONOMOUS != 1 (humans free)
#   - session type is not senior/junior (planning bypasses)
#   - sprint-state.in_progress is null (no active claim)
#   - sprint-state.claim_started is unset (legacy claim)
#   - claim age < 5 min for soft nudge (orientation phase)
#   - Plan comment cached as posted (per-claim cache)

set -e

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
case "$TOOL_NAME" in
    Bash|Read|Grep|Glob|Edit|Write) ;;
    *) exit 0 ;;
esac

# Only autopilot
[ "${DRIFT_AUTONOMOUS:-0}" = "1" ] || exit 0

# Only senior/junior
SESSION_TYPE=$(cat "$HOME/drift-state/cache-session-type" 2>/dev/null || echo "")
case "$SESSION_TYPE" in
    senior|junior) ;;
    *) exit 0 ;;
esac

STATE_FILE="$HOME/drift-state/sprint-state.json"
[ -f "$STATE_FILE" ] || exit 0

NUM=$(jq -r '.in_progress // empty' "$STATE_FILE" 2>/dev/null || echo "")
CT=$(jq -r '.claim_started // empty' "$STATE_FILE" 2>/dev/null || echo "")
[ -z "$NUM" ] || [ "$NUM" = "null" ] && exit 0
[ -z "$CT" ] || [ "$CT" = "null" ] && exit 0

NOW=$(date +%s)
AGE_MIN=$(( (NOW - CT) / 60 ))

# Per-claim cache: once Plan was seen, skip the gh call
CACHE_DIR="$HOME/drift-state/plan-posted"
mkdir -p "$CACHE_DIR"
CACHE_FILE="$CACHE_DIR/${NUM}"
if [ -f "$CACHE_FILE" ]; then exit 0; fi

# Check the issue once per call when not cached. Look for BOTH the new XML
# contract (<plan>) and the legacy markdown headings.
COMMENTS=$(gh issue view "$NUM" --json comments --jq '.comments[].body' 2>/dev/null || echo "")
HAS_XML_PLAN=$(echo "$COMMENTS" | grep -c '<plan>' || true); HAS_XML_PLAN=${HAS_XML_PLAN:-0}
HAS_MD_PLAN=$(echo "$COMMENTS" | grep -ciE '^[[:space:]]*(plan|approach|investigation|progress|resolution)[[:space:]]*[:-]' || true); HAS_MD_PLAN=${HAS_MD_PLAN:-0}
HAS_PLAN=$(( HAS_XML_PLAN + HAS_MD_PLAN ))
if [ "$HAS_PLAN" -gt 0 ]; then
    touch "$CACHE_FILE"
    exit 0
fi

# === HARD BLOCK PATH: Edit | Write ===
# Once a session starts modifying code, the plan comment must exist. Without
# it, the work is uninspectable + the verifier has nothing to score against.
# EDIT_BUDGET allows a small head-start (e.g. the model edits 2-3 boilerplate
# lines before posting the plan); after that, we block until the plan is up.
if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
    COUNT_DIR="$HOME/drift-state/edit-count-since-plan"
    mkdir -p "$COUNT_DIR"
    COUNT_FILE="$COUNT_DIR/${NUM}"
    CURRENT=$(cat "$COUNT_FILE" 2>/dev/null || echo "0")
    CURRENT=$((CURRENT + 1))
    echo "$CURRENT" > "$COUNT_FILE"
    EDIT_BUDGET=3
    if [ "$CURRENT" -gt "$EDIT_BUDGET" ]; then
        cat >&2 <<EOF
[nudge-plan-comment] BLOCKED — Edit/Write #${CURRENT} on issue #${NUM} without a Plan comment.

The plan-comment is the verifier's anchor — without it, the eventual
debate-moderator pass has no goal/approach/touches to compare against, and
require-qa-verdict.sh will reject the commit. Post the plan FIRST, then
return to editing.

Recipe (new XML format):
  gh issue comment ${NUM} --body '<plan>
    <goal>Restate Done-When criterion 1 in one sentence.</goal>
    <approach>1. step. 2. step. 3. step.</approach>
    <touches><file>path/to/file.swift</file></touches>
    <risk>One sentence; "low" allowed.</risk>
    <verifier_path>Done-When criteria covered; "all" allowed.</verifier_path>
  </plan>'

Or if you do not actually have a plan, unclaim:
  scripts/sprint-service.sh unclaim ${NUM}
EOF
        exit 2
    fi
    # Edit budget not yet exhausted — fall through to soft nudge below if applicable
fi

# === SOFT NUDGE PATH: Bash | Read | Grep | Glob (and Edit|Write within budget) ===
# Time-based escalation. additionalContext (advisory, non-blocking).
[ "$AGE_MIN" -lt 5 ] && exit 0

RECIPE='gh issue comment '"$NUM"' --body "<plan><goal>...</goal><approach>1. ...</approach><touches><file>...</file></touches><risk>...</risk><verifier_path>...</verifier_path></plan>"'
if [ "$AGE_MIN" -lt 10 ]; then
    MSG="FYI: ${AGE_MIN} min into #${NUM} with no Plan comment yet. Post one before continuing: ${RECIPE}. Skip if already posted."
elif [ "$AGE_MIN" -lt 15 ]; then
    MSG="POST PLAN NOW: ${AGE_MIN} min into #${NUM}, no Plan visible. Edit/Write will be BLOCKED after a few more attempts. Run: ${RECIPE}"
else
    MSG="WANDERING ALERT: ${AGE_MIN} min into #${NUM} with no Plan. Post the Plan immediately OR run scripts/sprint-service.sh unclaim ${NUM} if you do not actually have one yet. Recipe: ${RECIPE}"
fi

cat <<ENDJSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"${MSG}"}}
ENDJSON
exit 0
