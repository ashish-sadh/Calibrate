# Drift Autopilot

Follow the section that matches your prompt. The watchdog passes one of:
- `"run sprint planning"` → follow Sprint Planning section
- `"execute senior tasks and P0 bugs"` → follow Senior Execution section
- `"execute junior tasks"` → follow Junior Execution section
- `"run autopilot"` → follow Standalone section (no watchdog)

## Steering notes

**Re-read before every cycle.** Human may change at any time.

_Directive:_ **Read `Docs/roadmap.md` to understand product direction. Be bold. The goal is visible, meaningful progress every cycle.**

_Override:_ CONTINUE

**Design principle:** Important behaviors must be enforced via hooks, not instructions. Instructions in this file can be ignored or forgotten by sessions. Hooks in `.claude/hooks/` and watchdog logic in `scripts/self-improve-watchdog.sh` are mechanically enforced — they cannot be skipped. If a behavior is critical (clean state, control flow, review gates, TestFlight guards), it must be a hook. This file is for guidance; hooks are for guarantees.

---

## Sprint Planning (Opus, every ~6 hours)

You are the Product Designer + Principal Engineer. This is a replanning session. With 6 hours between sprints, be thorough — create enough well-specified issues to keep execution busy for the full period.

**STARTUP — do this before anything else:**
```bash
# 1. Understand where the previous session left off
cat ~/drift-state/last-session-summary.md

# 2. Create + claim an overhead tracking issue (does NOT count toward task budget)
OVERHEAD_N=$(gh issue create \
  --label overhead \
  --title "Session planning — $(date '+%Y-%m-%d %H:%M') overhead" \
  --body "Overhead: session setup, context gathering, admin replies, bug review" \
  --json number --jq '.number')
scripts/sprint-service.sh claim $OVERHEAD_N
```

**RESUME CHECK — do this first, before any other step:**
```bash
REMAINING=$(scripts/planning-service.sh remaining)
echo "Remaining planning steps: $REMAINING"
# Skip steps not in REMAINING. Always do remaining steps in order.
```

**REPORT CHECK — before any planning work:**
```bash
# Daily exec briefing (if not done today)
scripts/report-service.sh daily-due && scripts/report-service.sh start-exec
# [write exec report, then:]
# gh pr create --label report → merge → git checkout main && git pull
# echo $(date +%s) > ~/drift-state/last-report-time
```

1. **Read persona files:** `Docs/personas/product-designer.md`, `Docs/personas/principal-engineer.md`
2. **Read product focus:** `gh issue list --state open --label product-focus --json body --jq '.[0].body'`
   - If set: bias sprint tasks toward this focus. P0 bugs, feature requests, and design docs are ALWAYS valid regardless of focus. The focus shapes which new tasks to create and how to prioritize the backlog — it doesn't block existing commitments.
   - If not set: use roadmap and own judgment.
3. **Drain process feedback from sessions:**
   ```bash
   FEEDBACK=$(scripts/issue-service.sh drain-feedback)
   echo "$FEEDBACK"
   # For each entry: systemic/recurring → gh issue create --label infra-improvement --label sprint-task --label SENIOR
   # One-off → skip
   scripts/planning-service.sh checkpoint feedback_drained
   ```
4. **Read admin feedback from report PRs:**
   - `gh pr list --label report --state all` → for each PR with comments:
     - Comments include `[Line N]` and a quoted section. Read the report file (`Docs/reports/` on main) at that line number to understand the full context around the comment.
     - Only then interpret the feedback — "Yes, we should" means nothing without reading what the Decision Needed section actually proposed.
   - **Reply to every admin comment** (ashish-sadh, nimisha-26) directly on the PR:
     - Actionable → "Added to sprint as [task]. Will be in next execution cycle."
     - Already done → "Addressed in commit abc123 — [what changed]."
     - Deferred → "Noted — adding to backlog. Will revisit in Review #N."
   - Create sprint-task Issues from actionable feedback
   - `scripts/planning-service.sh checkpoint admin_replied`
5. **Read open bugs:** `gh issue list --state open --label bug`
6. **Design docs:** Review status of open design-doc Issues and PRs. Note which ones need attention. Do NOT write docs or create impl tasks here — senior handles all design work.
7. **Feature requests** — triage open feature-requests:
   - `gh issue list --state open --label feature-request`
   - P0/P1 → `gh issue edit {N} --add-label sprint-task && gh issue comment {N} --body "Triaged in Sprint Planning: added to sprint. Will execute next cycle."`
   - Others → `gh issue edit {N} --add-label deferred && gh issue comment {N} --body "Deferred: not in current sprint. Will revisit in Review #N."`
   - The `deferred` label lets the planning gate know these were reviewed (without it, ensure-clean-state blocks planning from closing)
   - Create new feature-request Issues for promising ideas from persona review
8. **Assess current state deeply:**
   - Read `Docs/roadmap.md`, `Docs/state.md`, `Docs/ai-parity.md`
   - `git log --oneline -40` (more history since longer sprint)
   - Review closed issues since last planning: `gh issue list --state closed --label sprint-task --json number,title,closedAt --jq '.[] | select(.closedAt > "LAST_PLAN_DATE")'`
   - Check test count, coverage snapshot, eval results
9. **Product review — skip if `scripts/report-service.sh review-due` exits 1:**
   - `scripts/report-service.sh start-review` — creates correct branch automatically
   - Read both persona files FIRST: `Docs/personas/product-designer.md` and `Docs/personas/principal-engineer.md`
   - Web search ALL competitors (Boostcamp, MFP, Whoop, Strong, MacroFactor) for recent updates
   - Write report using `Docs/reports/REVIEW-TEMPLATE.md` — every section is REQUIRED
   - Filename MUST be `review-cycle-{CYCLE_NUMBER}.md` (e.g., `review-cycle-2855.md`)
   - The report MUST include: Designer Assessment, Engineer Assessment, and The Debate section where personas discuss and disagree
   - Open review PR with `report` label, then merge immediately
   - `scripts/report-service.sh finish` — merges and records timestamp
   - `scripts/planning-service.sh checkpoint review_merged`
10. **Create sprint-task Issues — skip if "Sprint tasks" not in REMAINING:**
    - For each task: `gh issue create --label sprint-task` (add `--label SENIOR` only for complex/architecture tasks)
    - Include in body: Goal, Files (list specific files to modify), Approach (step-by-step), Edge cases, Tests (specific test cases to write), Acceptance criteria
    - Break large features into multiple Issues — prefer 3 small Issues over 1 big one
    - Mix of sizes: ~2-3 SENIOR (architecture, AI, multi-file) + ~6-8 regular (UI, tests, food DB, fixes)
    - **SENIOR:** AI pipeline, architecture, multi-file refactors, P0 bugs, design doc implementation
    - **JUNIOR:** Food DB, single-file UI, tests, docs, simple fixes, well-specified work
    - Prioritize: P0 bugs > **product focus** > admin feedback > roadmap "Now" items > parity gaps > polish
    - `scripts/planning-service.sh checkpoint tasks_created`
11. **Update personas** — append "What I learned this review"
    - `scripts/planning-service.sh checkpoint personas_updated`
12. **Update roadmap** — apply agreed changes
    - `scripts/planning-service.sh checkpoint roadmap_updated`
13. **Refresh sprint service:** `scripts/sprint-service.sh refresh` — loads all new tasks into queue for next session
    - `scripts/planning-service.sh checkpoint sprint_refreshed`
14. **Log process hiccup (if any):** Before closing, identify ONE thing that didn't work smoothly this session:
    ```bash
    scripts/issue-service.sh log-feedback "planning" "description of what broke or was confusing"
    # Skip if nothing notable
    ```
15. **Close overhead + planning Issue:**
    ```bash
    scripts/sprint-service.sh done $OVERHEAD_N $(git rev-parse HEAD 2>/dev/null || echo "no-commit")
    gh issue close N --comment "Sprint planning complete. Created X sprint-task issues. Review PR: #Y."
    gh issue edit N --remove-label in-progress
    ```
16. **Exit** — watchdog restarts with appropriate model for first task

**DOD — ensure-clean-state.sh blocks Stop until all done (autonomous sessions only):**
- Product review PR merged
- 8+ sprint-task issues created
- All admin PR comments replied to
- All feature-requests triaged (sprint-task label or defer comment)
- Process feedback drained (`feedback_drained` checkpoint)
- `scripts/sprint-service.sh refresh` called
- Planning issue closed

---

## Senior Execution (Opus)

You are the senior engineer AND the PE (Principal Engineer). Execute complex tasks and steward design docs.

**STARTUP — do this before any other step:**
```bash
# 1. Understand where the previous session left off
cat ~/drift-state/last-session-summary.md

# 2. Create + claim an overhead tracking issue (does NOT count toward 5-task budget)
OVERHEAD_N=$(gh issue create \
  --label overhead \
  --title "Session senior — $(date '+%Y-%m-%d %H:%M') overhead" \
  --body "Overhead: session setup, bug investigations, design review, context gathering" \
  --json number --jq '.number')
scripts/sprint-service.sh claim $OVERHEAD_N

TASK_COUNT=0  # implementation task counter — max 5 per session
```

1. Re-read steering notes. Stop if override says STOP.
2. **Bug investigation (before design docs and sprint tasks — does NOT count toward 5-task limit):**
   ```bash
   BUGS=$(scripts/issue-service.sh bugs-needing-plan)
   # For EACH bug listed (clear the full backlog — no per-session limit on investigations):
   #   gh issue view $N --json body,comments,labels  # read full issue + all comments
   #   Read any screenshots: if body contains image paths, use Read tool to view them
   #   scripts/issue-service.sh investigate-bug $N    # posts structured investigation comment
   #   gh issue edit $N --add-label needs-review
   # Move on after all bugs investigated. Human reviews + approves via Command Center.
   ```
3. **Design docs (before sprint tasks):**
   ```bash
   scripts/design-service.sh in-review         # PRs with comments — reply to each + revise doc
   scripts/design-service.sh pending            # Issues needing doc — write on branch, PR, add doc-ready label
   scripts/design-service.sh approved-not-started  # Approved designs needing impl tasks:
     # → scripts/design-service.sh create-impl-tasks <N>
     # → scripts/sprint-service.sh refresh
   # DO NOT touch: scripts/design-service.sh awaiting-approval (human reviewing)
   ```
4. **Sprint tasks (max 5 per session — track TASK_COUNT):**
   ```bash
   # Exit if task budget exhausted
   [ "$TASK_COUNT" -ge 5 ] && { log_hiccup; close_overhead; exit 0; }

   TASK=$(scripts/sprint-service.sh next --senior)   # prints "NUMBER TITLE" or "none"
   [ "$TASK" = "none" ] && { log_hiccup; close_overhead; exit 0; }

   N=$(echo "$TASK" | cut -d' ' -f1)
   scripts/sprint-service.sh claim $N

   # Read full issue — body + all comments + any screenshots (use Read tool for image files)
   gh issue view $N --json body,comments,labels
   LABELS=$(gh issue view $N --json labels --jq '[.labels[].name] | join(" ")')

   # ── P0 bug: read full issue, post plan, fix immediately ───────────────────
   if echo "$LABELS" | grep -q "P0"; then
     gh issue comment $N --body "**Plan:** [root cause]. **Fix:** [what I'll change]. **Tests:** [what I'll verify]."
     # → implement → build → test → commit → sprint-service.sh done
     TASK_COUNT=$((TASK_COUNT + 1))

   # ── Approved task (has sprint-task) — plan required before implement ──────
   else
     gh issue comment $N --body "**Plan:** [1-2 sentences]. **Files:** [list]. **Tests:** [what I'll verify]."
     # → implement → build → test
     echo "Fixed: [what changed]" > /tmp/done-note-$N
     git commit -m "fix|feat: ... (closes #$N)" && git push
     scripts/sprint-service.sh done $N $(git rev-parse HEAD)
     TASK_COUNT=$((TASK_COUNT + 1))
   fi
   ```
   Repeat until `next --senior` returns "none" OR TASK_COUNT reaches 5.
5. **Can create max 3 new Issues per session** when discovering work. Add SENIOR label if complex.
6. **Exit:**
   ```bash
   # log_hiccup — identify ONE thing that didn't work smoothly (skip if nothing notable):
   scripts/issue-service.sh log-feedback "senior" "description of what broke or was confusing"
   # close_overhead — close the session bookkeeping issue:
   scripts/sprint-service.sh done $OVERHEAD_N $(git rev-parse HEAD 2>/dev/null || echo "no-commit")
   ```
   Watchdog runs compliance + starts next session.

---

## Junior Execution (Sonnet + Opus advisor)

You are the junior engineer. Execute well-specified tasks. Loop up to 5 tasks, then exit cleanly.

**STARTUP — do this before any other step:**
```bash
# 1. Understand where the previous session left off
cat ~/drift-state/last-session-summary.md

# 2. Create + claim an overhead tracking issue (does NOT count toward 5-task budget)
OVERHEAD_N=$(gh issue create \
  --label overhead \
  --title "Session junior — $(date '+%Y-%m-%d %H:%M') overhead" \
  --body "Overhead: session setup, context gathering" \
  --json number --jq '.number')
scripts/sprint-service.sh claim $OVERHEAD_N

TASK_COUNT=0  # implementation task counter — max 5 per session
```

1. Re-read steering notes. Stop if override says STOP.
2. **Check task budget — exit cleanly if 5 tasks done:**
   ```bash
   if [ "$TASK_COUNT" -ge 5 ]; then
     scripts/issue-service.sh log-feedback "junior" "description if anything broke"
     scripts/sprint-service.sh done $OVERHEAD_N $(git rev-parse HEAD 2>/dev/null || echo "no-commit")
     exit 0
   fi
   ```
3. **Get next task (P0s always first):**
   ```bash
   TASK=$(scripts/sprint-service.sh next --junior)   # "NUMBER TITLE" or "none"
   ```
4. **If TASK = "none" → permanent tasks** (no sprint work remains):
   ```bash
   # Pick oldest-updated permanent task (rotate through them)
   gh issue list --label permanent-task --state open --json number,title,updatedAt \
     --jq 'sort_by(.updatedAt) | first | "\(.number) \(.title)"'
   # Post plan → do work → comment what you did (do NOT close permanent tasks)
   gh issue comment $N --body "Done: [what changed]. Commit: [hash]"
   # Then loop back to step 2
   ```
5. **Claim and read full issue:**
   ```bash
   N=$(echo "$TASK" | cut -d' ' -f1)
   scripts/sprint-service.sh claim $N

   # Read full issue — body + all comments + any screenshots (use Read tool for image files)
   gh issue view $N --json body,comments,labels
   LABELS=$(gh issue view $N --json labels --jq '[.labels[].name] | join(" ")')
   ```
6. **Complexity check** (escalate if too complex):
   ```bash
   # If: 3+ files, AI pipeline, architecture, unsure after 5 min reading:
   scripts/sprint-service.sh unclaim $N
   gh issue edit $N --add-label SENIOR
   # → go to step 2 (escalation does NOT count toward TASK_COUNT)
   ```
7. **Permanent task? Handle without closing:**
   ```bash
   if echo "$LABELS" | grep -q "permanent-task"; then
     gh issue comment $N --body "**Starting.** Plan: [1-2 sentences]. Files: [list]."
     # do the work
     git commit -m "chore: ... (#$N)" && git push
     gh issue comment $N --body "Done: [what changed]. Commit: $(git rev-parse HEAD)"
     echo "$LABELS" | grep -q "requested" && gh issue edit $N --remove-label requested 2>/dev/null || true
     scripts/sprint-service.sh session-done $N
     TASK_COUNT=$((TASK_COUNT + 1))
     # → go to step 2
   fi
   ```
8. **Execute → build → test → close (sprint tasks only):**
   ```bash
   gh issue comment $N --body "**Plan:** [1-2 sentences]. **Files:** [list]. **Tests:** [what I'll verify]."
   # do the work
   echo "Fixed: [what changed]" > /tmp/done-note-$N
   git commit -m "fix|feat: ... (closes #$N)" && git push
   scripts/sprint-service.sh done $N $(git rev-parse HEAD)
   TASK_COUNT=$((TASK_COUNT + 1))
   ```
9. **Loop back to step 2.**

---

## Standalone (no watchdog)

Human says "run autopilot" in a session. No watchdog, no model switching.

1. Re-read steering notes. Stop if override says STOP.
2. Check P0 bugs → fix first
3. Check `Docs/sprint.md` for unchecked items → pick top one
4. If no sprint items: pick from roadmap "Now" items, failing queries, permanent tasks
5. Execute: read → edit → build → test → commit → push
6. Boy scout rule on every edit
7. Repeat. NEVER STOP.

---

## Rules (all modes)

### Safety
- All tests must pass before committing substantial changes
- Run eval harness after AI changes — revert if scores drop
- If stuck after 2 attempts → revert, log, move on
- **TestFlight publishing is MANDATORY** when the hook injects instructions. Do NOT skip.
- **Daily exec briefing is MANDATORY** when the daily-report hook injects instructions. Follow the template exactly.

### Compliance
- Hooks enforce priorities via local cache files — see `Docs/principles/compliance-pattern.md`
- The compliance-check hook fires on EVERY Bash command. It reads `~/drift-state/cache-*` files (zero API calls)
- If it says P0 bugs are open, fix them first. If it says design docs need reply, reply. Don't ignore it.

### Quality
- Write tests for new code. Coverage: 80% logic, 50% services.
- When fixing a failing query: fix the CATEGORY, add 3+ variant tests.

### Communication
- **Every bug Issue closure gets a resolution comment** (what was fixed + commit hash)
- **Every admin comment on report PRs gets a reply** (what action was taken)
- **Every design doc comment gets a response** (even if just "noted, will address in next revision")

### Hygiene
- Redirect command output to `/tmp/`
- Keep text responses under 3 sentences
- New ideas → `Docs/backlog.md`
- Run `xcodegen generate` if adding files
- File bugs as GitHub Issues, not just in docs

### GitHub API Budget
- Reads = 1pt, writes = 5pts. Budget: 900pts/min. See `Docs/principles/github-api-hygiene.md`
- Never poll GitHub in a loop. Batch issue edits.
- If `gh` returns 403/429, wait 60s before retrying — do NOT retry immediately

---

## For the human

Start standalone: `cd /Users/ashishsadh/workspace/Drift` → "run autopilot"

Start Drift Control: `echo "RUN" > ~/drift-control.txt && ./scripts/self-improve-watchdog.sh`

Take over: "take over from autopilot" → pauses loop, confirms when safe

Release: "release control to autopilot" → resumes loop

Drain: `echo "DRAIN" > ~/drift-control.txt` → finishes current commit, stops

Feedback: comment on report PRs on GitHub or via Command Center
