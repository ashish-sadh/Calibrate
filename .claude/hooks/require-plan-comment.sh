#!/bin/bash
# Hook: PreToolUse on Bash(git commit *)
#
# Enforces program.md's "post a plan comment before every implementation"
# rule that was previously documented but never gated. Audit showed only
# 15% of recent closed sprint-tasks had plan comments — sessions skipped
# this and the harness never noticed.
#
# This hook BLOCKS `git commit` when:
#   - The session is autopilot (DRIFT_AUTONOMOUS=1), AND
#   - sprint-state.json has an in-progress issue, AND
#   - That issue has no comment starting with Plan:/Approach:/Investigation:/
#     Progress:/Resolution: (case-insensitive), AND
#   - The issue isn't a planning issue (planning IS the plan), AND
#   - The issue isn't a P0 emergency (per program.md exception).
#
# Escape hatch: set DRIFT_SKIP_PLAN_COMMENT=1 if you posted the plan in
# the issue body rather than a comment, or for one-off cases the rule
# shouldn't apply to.

set -e

# 0. Read stdin JSON (PreToolUse contract — pause-gate.sh:6-7 for proven pattern).
#    Filter to git-commit only. The settings.json `if: "Bash(git commit *)"`
#    matcher does NOT actually filter PreToolUse — without this in-script
#    check the hook would fire on every Bash call and block all autopilot
#    work. (Bug observed 2026-04-26 cycle 7581.)
#
#    Earlier version of this hook read TOOL_INPUT env var which is never set in
#    PreToolUse, so the filter never matched and the hook silently fell through
#    on every Bash call (no-op). Always read stdin.
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
echo "$COMMAND" | grep -qE "git[[:space:]]+commit" || exit 0

# 1. Only gate autopilot. Humans aren't subject to this discipline.
[[ "${DRIFT_AUTONOMOUS:-0}" != "1" ]] && exit 0

# 2. Explicit escape hatch.
[[ "${DRIFT_SKIP_PLAN_COMMENT:-0}" == "1" ]] && exit 0

# 2b. The parity lanes claim `android-parity` issues, which sprint-state.json
#     does not track — so every check below would grade this commit against
#     whatever the SPRINT lane last claimed (seen 2026-08-17: #1143's commit
#     blocked citing #1018, a stranger's ticket). The rule still binds those
#     lanes; it is enforced where their work actually lives: the parity
#     planner writes a `## Plan` comment on the issue before it is labelled
#     `planned`, and the executor may not claim an unplanned one.
#     Same stale-in_progress flaw as require-qa-verdict.sh.
[[ -n "${DRIFT_PARITY_LANE:-}" ]] && exit 0

STATE_FILE="$HOME/drift-state/sprint-state.json"
[ -f "$STATE_FILE" ] || exit 0

# 3. Read in_progress from local state. If null/empty, the commit isn't
#    tied to a claimed task (heartbeat, chore, planning checkpoint, etc.).
NUM=$(python3 -c "
import json, sys
try:
    d = json.load(open('$STATE_FILE'))
    ip = d.get('in_progress')
    print(ip if ip else '')
except Exception:
    print('')
" 2>/dev/null)
[ -z "$NUM" ] && exit 0

# 4. Check labels — skip planning + P0/emergency.
LABELS=$(gh issue view "$NUM" --json labels --jq '[.labels[].name] | join(",")' 2>/dev/null || echo "")
case ",$LABELS," in
    *,planning,*) exit 0 ;;
esac
if [[ ",$LABELS," == *",P0,"* ]] && [[ ",$LABELS," == *",emergency,"* ]]; then
    exit 0
fi

# 5. Look for a plan-style comment.
COMMENTS_BODY=$(gh issue view "$NUM" --json comments --jq '.comments[].body' 2>/dev/null || echo "")
if echo "$COMMENTS_BODY" | grep -qiE '^[[:space:]]*(plan|approach|investigation|progress|resolution)[[:space:]]*[:-]'; then
    exit 0
fi

# 6. No plan-style comment found — block.
cat >&2 <<EOF
BLOCKED: Issue #$NUM has no plan comment yet.

Per program.md, sessions must post a plan comment before implementing.
The plan should describe: root cause + fix approach + files to change.

Post one now, then retry the commit:

    gh issue comment $NUM --body "Plan: <root cause> — <fix approach> — touches <files>"

Accepted comment prefixes (case-insensitive):
    Plan:   Approach:   Investigation:   Progress:   Resolution:

Escape hatches (use only when the rule genuinely shouldn't apply):
    - Set DRIFT_SKIP_PLAN_COMMENT=1 for this commit
    - Add the 'planning' label to the issue (planning IS the plan)
    - Add 'emergency' + 'P0' labels (per program.md exception)
EOF
exit 2
