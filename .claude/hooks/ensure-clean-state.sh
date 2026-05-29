#!/bin/bash
# Hook: Stop
# Blocks session from ending if there are uncommitted changes or unpushed commits.
# Forces the model to commit and push before stopping.

set -e

cd "${CLAUDE_PROJECT_DIR:-.}"

# Skip the dirty-state check for an INTERACTIVE session (takeover / dev work)
# when autopilot is the active worker — it owns the working tree, and its OWN
# sessions still pass this gate (commit-or-abandon discipline). Match the current
# `claude -p /<skill>` invocation format (the old `(execute|run.*autopilot|sprint)`
# pattern stopped matching, so this gate wrongly blocked interactive takeover
# sessions whenever a senior/junior/planning session had files mid-edit). Only
# skip when NOT autonomous — autopilot's own sessions (DRIFT_AUTONOMOUS=1) must
# still be held to the clean-state gate below.
if [ "${DRIFT_AUTONOMOUS:-0}" != "1" ] && \
   pgrep -f 'claude .*-p .*/(senior|junior|planning|design-doc|testflight|admin-replies|knowledge-curate|ui-evaluator|ui-review)' > /dev/null 2>&1; then
  exit 0
fi

DRIFT_CONTROL=$(cat "$HOME/drift-control.txt" 2>/dev/null | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
SESSION_TYPE=$(cat "$HOME/drift-state/cache-session-type" 2>/dev/null || echo "")
# DRIFT_AUTONOMOUS is set by the watchdog on spawn — only autopilot sessions
# have it. Interactive sessions (takeovers, dev work) see SESSION_TYPE from
# the cache file that reflects the running autopilot, not their own role,
# so role-specific gates below must key off this flag instead.
IS_AUTONOMOUS="${DRIFT_AUTONOMOUS:-0}"

# Fix A: proactive branch sweep on session end. Planning sessions create
# review/cycle-N or report/exec-DATE branches. If the session crashed mid-
# flow (gh pr merge succeeded but `report-service.sh finish` never ran to
# switch back), HEAD is left on the feature branch. Run `finish` here to
# merge any open PR + switch to main + pull. Idempotent — finish is safe
# to call when nothing is mid-flow.
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
if [[ "$CURRENT_BRANCH" =~ ^(review/cycle-|report/exec-|report/) ]]; then
  echo "[ensure-clean-state] HEAD on $CURRENT_BRANCH — running report-service.sh finish to switch back to main"
  scripts/report-service.sh finish 2>/dev/null || git checkout main 2>/dev/null || true
fi

# Check for uncommitted changes (staged or unstaged). Skip files that the
# autopilot regenerates on its own schedule — they're not operator edits:
# - command-center/heartbeat.json: watchdog rewrites every 30s
# - graphify-out/*: autopilot rebuilds the knowledge graph after AI/code
#   changes; the diff is huge but operator never edits these directly
DIRTY=$(git status --porcelain 2>/dev/null | grep -v '^??' | grep -vE 'command-center/heartbeat\.json|graphify-out/' | head -5)
UNTRACKED=$(git status --porcelain 2>/dev/null | grep '^??' | grep -v '.claude/' | head -5)

# Check for unpushed commits
UNPUSHED=$(git log --oneline @{upstream}..HEAD 2>/dev/null | head -5)

ISSUES=""

if [ -n "$DIRTY" ]; then
  ISSUES="${ISSUES}Uncommitted changes:\n${DIRTY}\n\n"
fi

if [ -n "$UNTRACKED" ]; then
  ISSUES="${ISSUES}Untracked files (outside .claude/):\n${UNTRACKED}\n\n"
fi

if [ -n "$UNPUSHED" ]; then
  ISSUES="${ISSUES}Unpushed commits:\n${UNPUSHED}\n\n"
fi

# Check if persona files were updated after a product review (planning sessions only)
if [ "$DRIFT_CONTROL" = "RUN" ] && [ "$SESSION_TYPE" = "planning" ] && [ "$IS_AUTONOMOUS" = "1" ]; then
  CYCLE_COUNT=$(cat "$HOME/drift-state/commit-counter" 2>/dev/null || echo "0")
  LAST_REVIEW=$(cat "$HOME/drift-state/last-review-cycle" 2>/dev/null || echo "0")
  if [ "$CYCLE_COUNT" -eq "$LAST_REVIEW" ] && [ "$CYCLE_COUNT" -gt 0 ]; then
    DESIGNER_FILE="${CLAUDE_PROJECT_DIR:-.}/Docs/personas/product-designer.md"
    ENGINEER_FILE="${CLAUDE_PROJECT_DIR:-.}/Docs/personas/principal-engineer.md"
    NOW=$(date +%s)

    for PFILE in "$DESIGNER_FILE" "$ENGINEER_FILE"; do
      if [ -f "$PFILE" ]; then
        # Check when this file was last committed (not file mtime — mtime is always
        # older than commit timestamp, making the old PMOD < LAST_COMMIT_TIME check
        # a false positive after every correct update).
        LAST_PERSONA_COMMIT=$(git log -1 --format="%ct" -- "$PFILE" 2>/dev/null || echo "0")
        if [ "$(( NOW - LAST_PERSONA_COMMIT ))" -gt 86400 ]; then
          ISSUES="${ISSUES}Persona file not committed in 24h after product review: $(basename $PFILE)\n\n"
        fi
      fi
    done
  fi
fi

# Check if any dirty files are report files (need PR branch, not direct main commit)
REPORT_FILES=$(git status --porcelain 2>/dev/null | grep -v '^??' | grep 'Docs/reports/' | awk '{print $2}')

if [ -n "$REPORT_FILES" ] && [ -n "$ISSUES" ]; then
  # Extract report type/name for branch naming
  REPORT_NAME=$(echo "$REPORT_FILES" | head -1 | sed 's|Docs/reports/||;s|\.md||')
  if echo "$REPORT_NAME" | grep -q "^review-cycle"; then
    BRANCH="review/$(echo "$REPORT_NAME" | sed 's/^review-//')"
  elif echo "$REPORT_NAME" | grep -q "^exec-"; then
    BRANCH="report/$REPORT_NAME"
  else
    BRANCH="report/$REPORT_NAME"
  fi

  echo -e "BLOCKED: Cannot stop with dirty state.\n\n${ISSUES}" >&2
  echo -e "IMPORTANT: Report files detected in uncommitted changes ($REPORT_FILES)." >&2
  echo -e "You MUST create a PR branch for reports — do NOT commit them to main." >&2
  echo -e "Steps: git checkout -b $BRANCH && commit report + related files && git push -u origin $BRANCH && gh pr create --label report && git checkout main" >&2
  exit 2
fi

if [ -n "$ISSUES" ]; then
  echo -e "BLOCKED: Cannot stop with dirty state.\n\n${ISSUES}Commit all changes and push before stopping." >&2
  exit 2
fi

# Check for in-progress issues that weren't closed (autonomous sessions only)
if [ "$DRIFT_CONTROL" = "RUN" ] && [ "$IS_AUTONOMOUS" = "1" ]; then
  IN_PROGRESS=$(gh issue list --state open --label in-progress --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null || true)
  if [ -n "$IN_PROGRESS" ]; then
    echo -e "BLOCKED: Issues still in-progress. Verify work is done (build + tests pass), then close with comment:\n\n${IN_PROGRESS}\n\nFor each: gh issue close N --comment 'Done: {what was done} (commit {hash})'\nOr remove in-progress if unfinished: gh issue edit N --remove-label in-progress" >&2
    exit 2
  fi
fi

# Senior session Stop gate — check design doc and bug plan hygiene
if [ "$SESSION_TYPE" = "senior" ] && [ "$DRIFT_CONTROL" = "RUN" ] && [ "$IS_AUTONOMOUS" = "1" ]; then
  # Design docs in-review: if any PR has unreplied comments, block
  DESIGN_UNREPLIED=$("${CLAUDE_PROJECT_DIR:-.}/scripts/design-service.sh" in-review 2>/dev/null || echo "")
  if [ -n "$DESIGN_UNREPLIED" ] && [ "$DESIGN_UNREPLIED" != "none" ]; then
    echo -e "BLOCKED: Design PR comments unreplied:\n$DESIGN_UNREPLIED\nReply to all comments before stopping." >&2
    exit 2
  fi

  # Pending design docs unwritten: if any exist and this session produced no
  # design-doc PR, block. Senior is the only role allowed to write design docs
  # (per program.md step 3) — without this gate they were silently exiting
  # while docs like #274 rotted in the pending queue.
  PENDING_DESIGN=$("${CLAUDE_PROJECT_DIR:-.}/scripts/design-service.sh" pending 2>/dev/null | grep -E '^#[0-9]+' || echo "")
  if [ -n "$PENDING_DESIGN" ]; then
    # Did THIS session produce a design-doc PR? Check for one created by us in the last 4h.
    CUTOFF=$(date -u -v-4H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '4 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
    NEW_DESIGN_PRS=0
    if [ -n "$CUTOFF" ]; then
      NEW_DESIGN_PRS=$(gh pr list --label design-doc --state all --search "created:>$CUTOFF" --json number --jq 'length' 2>/dev/null || echo "0")
    fi
    if [ "$NEW_DESIGN_PRS" = "0" ]; then
      echo -e "BLOCKED: Pending design doc(s) not written this session:\n${PENDING_DESIGN}\nWrite at least one (design-service.sh pending → branch → PR with --label design-doc) or add the 'blocked' label with a stated reason before stopping." >&2
      exit 2
    fi
  fi

  # Bugs closed this session without plan-posted label — warn (not hard block)
  UNPLANNED=$(gh issue list --state closed --label bug --json number,title,labels \
    --jq '[.[] | select(.labels | map(.name) | index("plan-posted") | not)] | length' 2>/dev/null || echo "0")
  if [ "$UNPLANNED" -gt 0 ] 2>/dev/null; then
    echo "WARNING: $UNPLANNED bugs closed without plan-posted label — consider posting investigation next time" >&2
  fi
fi

# Planning session validation — only for autonomous planning sessions (watchdog sets both)
if [ "$SESSION_TYPE" = "planning" ] && [ "$DRIFT_CONTROL" = "RUN" ] && [ "$IS_AUTONOMOUS" = "1" ]; then
  # Bypass DOD gate if planning-done was already stamped (< 2h ago) or the
  # planning issue is already closed. Without this, a session that finished
  # planning but left one checkbox unchecked would stall forever, requiring
  # manual human restart every cycle.
  LAST_PLANNING=$(cat "$HOME/drift-state/last-planning-time" 2>/dev/null || echo "0")
  PLANNING_AGE=$(( $(date +%s) - LAST_PLANNING ))
  PLANNING_ISSUE_N=$(cat "$HOME/drift-state/planning-issue" 2>/dev/null | tr -d '[:space:]' || echo "")
  PLANNING_ISSUE_STATE="open"
  if [ -n "$PLANNING_ISSUE_N" ]; then
    PLANNING_ISSUE_STATE=$(gh issue view "$PLANNING_ISSUE_N" --json state --jq '.state' 2>/dev/null || echo "open")
  fi

  if [ "$PLANNING_AGE" -lt 7200 ] || [[ "${PLANNING_ISSUE_STATE,,}" == "closed" ]]; then
    echo "[ensure-clean-state] Planning done (stamp age ${PLANNING_AGE}s, issue ${PLANNING_ISSUE_STATE}) — DOD gate skipped"
  else
    PLAN_ISSUES=""

    # Were open feature requests reviewed and triaged?
    # Only block if any have NEITHER sprint-task NOR deferred label (truly untriaged).
    # Deferred FRs with the deferred label are intentionally left open for future sprints.
    FR_UNTRIAGED=$(gh issue list --state open --label feature-request --json number,labels \
      --jq '[.[] | select(.labels | map(.name) | (index("sprint-task") == null and index("deferred") == null))] | length' \
      2>/dev/null || echo "0")
    if [ "$FR_UNTRIAGED" -gt 0 ]; then
      FR_LIST=$(gh issue list --state open --label feature-request --json number,title,labels \
        --jq '[.[] | select(.labels | map(.name) | (index("sprint-task") == null and index("deferred") == null))] | .[] | "#\(.number) \(.title)"' \
        2>/dev/null || true)
      PLAN_ISSUES="${PLAN_ISSUES}Untriaged feature requests ($FR_UNTRIAGED) — must triage all before closing:\n${FR_LIST}\nFor each: add sprint-task label OR add deferred label (see program.md step 7).\n\n"
    fi

    # Planning checklist validation via planning-service.sh
    PLAN_VALIDATE_OUTPUT=$("${CLAUDE_PROJECT_DIR:-.}/scripts/planning-service.sh" validate 2>&1 || true)
    if echo "$PLAN_VALIDATE_OUTPUT" | grep -q "^Planning validation failed"; then
      PLAN_ISSUES="${PLAN_ISSUES}${PLAN_VALIDATE_OUTPUT}\n\n"
    fi

    if [ -n "$PLAN_ISSUES" ]; then
      echo -e "BLOCKED: Planning session incomplete.\n\n${PLAN_ISSUES}" >&2
      exit 2
    fi
  fi
fi

exit 0
