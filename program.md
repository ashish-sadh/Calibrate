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

1. **Read persona files:** `Docs/personas/product-designer.md`, `Docs/personas/principal-engineer.md`
2. **Read product focus:** `gh issue list --state open --label product-focus --json body --jq '.[0].body'`
   - If set: bias sprint tasks toward this focus. P0 bugs, feature requests, and design docs are ALWAYS valid regardless of focus. The focus shapes which new tasks to create and how to prioritize the backlog — it doesn't block existing commitments.
   - If not set: use roadmap and own judgment.
3. **Read admin feedback from report PRs:**
   - `gh pr list --label report --state all` → for each PR with comments:
     - Comments include `[Line N]` and a quoted section. Read the report file (`Docs/reports/` on main) at that line number to understand the full context around the comment.
     - Only then interpret the feedback — "Yes, we should" means nothing without reading what the Decision Needed section actually proposed.
   - **Reply to every admin comment** (ashish-sadh, nimisha-26) directly on the PR:
     - Actionable → "Added to sprint as [task]. Will be in next execution cycle."
     - Already done → "Addressed in commit abc123 — [what changed]."
     - Deferred → "Noted — adding to backlog. Will revisit in Review #N."
   - Create sprint-task Issues from actionable feedback
4. **Read open bugs:** `gh issue list --state open --label bug`
5. **Design docs:** Review status of open design-doc Issues and PRs. Do NOT write docs here — senior execution handles writing. Just note which ones need attention.
6. **Feature requests** — capture ideas the PE/Product Designer personas generate during review:
   - Create Issues for promising features: `gh issue create --label feature-request --title "Feature: ..." --body "Problem: ...\nProposal: ...\nPriority rationale: ..."`
   - Only create for ideas worth exploring — not every thought, just the ones that advance the roadmap
   - These show up on Command Center's Feature Requests tab for human review
7. **Assess current state deeply:**
   - Read `Docs/roadmap.md`, `Docs/state.md`, `Docs/ai-parity.md`
   - `git log --oneline -40` (more history since longer sprint)
   - Review closed issues since last planning: `gh issue list --state closed --label sprint-task --json number,title,closedAt --jq '.[] | select(.closedAt > "LAST_PLAN_DATE")'`
   - Check test count, coverage snapshot, eval results
8. **Product review — MUST follow template exactly:**
   - Read both persona files FIRST: `Docs/personas/product-designer.md` and `Docs/personas/principal-engineer.md`
   - Web search ALL competitors (Boostcamp, MFP, Whoop, Strong, MacroFactor) for recent updates
   - Write report using `Docs/reports/REVIEW-TEMPLATE.md` — every section is REQUIRED
   - Filename MUST be `review-cycle-{CYCLE_NUMBER}.md` (e.g., `review-cycle-2855.md`)
   - The report MUST include: Designer Assessment, Engineer Assessment, and The Debate section where personas discuss and disagree
   - Open review PR with `report` label, then merge immediately: `gh pr merge --squash --delete-branch && git checkout main && git pull`
9. **Create sprint-task Issues (target 8-12 issues for 6h sprint):**
   - For each task: `gh issue create --label sprint-task` (add `--label SENIOR` only for complex/architecture tasks)
   - Include in body: Goal, Files (list specific files to modify), Approach (step-by-step), Edge cases, Tests (specific test cases to write), Acceptance criteria
   - Break large features into multiple Issues — prefer 3 small Issues over 1 big one
   - Mix of sizes: ~2-3 SENIOR (architecture, AI, multi-file) + ~6-8 regular (UI, tests, food DB, fixes)
   - **SENIOR:** AI pipeline, architecture, multi-file refactors, P0 bugs, design doc implementation
   - **JUNIOR:** Food DB, single-file UI, tests, docs, simple fixes, well-specified work
   - Prioritize: P0 bugs > **product focus** > admin feedback > roadmap "Now" items > parity gaps > polish
10. **Update personas** — append "What I learned this review"
11. **Update roadmap** — apply agreed changes
12. **Refresh sprint service:** `scripts/sprint-service.sh refresh` — loads all new tasks into queue for next session
13. **Close the planning Issue:**
    ```bash
    gh issue close N --comment "Sprint planning complete. Created X sprint-task issues. Review PR: #Y."
    gh issue edit N --remove-label in-progress
    ```
14. **Exit** — watchdog restarts with appropriate model for first task

**DOD — ensure-clean-state.sh blocks Stop until all done (autonomous sessions only):**
- Product review PR merged
- 8+ sprint-task issues created
- All admin PR comments replied to
- All feature-requests triaged (sprint-task label or defer comment)
- `scripts/sprint-service.sh refresh` called
- Planning issue closed

---

## Senior Execution (Opus)

You are the senior engineer AND the PE (Principal Engineer). Execute complex tasks and steward design docs.

1. Re-read steering notes. Stop if override says STOP.
2. **Design docs first (before sprint tasks):**
   ```bash
   scripts/design-service.sh in-review         # PRs with comments — reply to each + revise
   scripts/design-service.sh pending            # Issues needing doc — write on branch, PR, doc-ready label
   scripts/design-service.sh approved-not-started  # Need impl tasks — run create-impl-tasks + sprint-service.sh refresh
   # DO NOT touch: scripts/design-service.sh awaiting-approval (human reviewing)
   ```
3. **Sprint tasks (loop until "none"):**
   ```bash
   # Get next task (P0s always returned first, regardless of filter)
   TASK=$(scripts/sprint-service.sh next --senior)   # prints "NUMBER TITLE" or "none"
   [ "$TASK" = "none" ] && exit 0

   N=$(echo "$TASK" | cut -d' ' -f1)
   scripts/sprint-service.sh claim $N           # atomic — fails if another task already in-progress

   gh issue view $N                             # read full spec; if screenshot → Read the image file
   gh issue comment $N --body "**Starting.** Plan: [1-2 sentences]. Files: [list]. Tests: [what I'll verify]."

   # Execute → build → test
   echo "Fixed: [what changed]" > /tmp/done-note-$N
   git commit -m "fix|feat: ... (closes #$N)" && git push
   scripts/sprint-service.sh done $N $(git rev-parse HEAD)
   ```
   Repeat until `next --senior` returns "none" AND `design-service.sh` shows no pending work.
4. **Can create max 3 new Issues per session** when discovering work. Add SENIOR label if complex.
5. Exit when done. Watchdog restarts with appropriate model.

---

## Junior Execution (Sonnet + Opus advisor)

You are the junior engineer. Execute well-specified tasks. Loop forever — junior never idles.

1. Re-read steering notes. Stop if override says STOP.
2. **Get next task (P0s always first):**
   ```bash
   TASK=$(scripts/sprint-service.sh next --junior)   # "NUMBER TITLE" or "none"
   ```
3. **If TASK = "none" → permanent tasks** (no sprint work remains):
   ```bash
   # Pick oldest-updated permanent task (rotate through them)
   gh issue list --label permanent-task --state open --json number,title,updatedAt \
     --jq 'sort_by(.updatedAt) | first | "\(.number) \(.title)"'
   # Post plan → do work → comment what you did (do NOT close permanent tasks)
   gh issue comment $N --body "Done: [what changed]. Commit: [hash]"
   # Then loop back to step 2
   ```
4. **Claim and execute sprint task:**
   ```bash
   N=$(echo "$TASK" | cut -d' ' -f1)
   scripts/sprint-service.sh claim $N           # atomic — CLAIM FAILED = another task in-progress (shouldn't happen)

   gh issue view $N                             # read full spec; if screenshot → Read the image file
   gh issue comment $N --body "**Starting.** Plan: [1-2 sentences]. Files: [list]. Tests: [what I'll verify]."
   ```
5. **Complexity check** (escalate if too complex):
   ```bash
   # If: 3+ files, AI pipeline, architecture, unsure after 5 min reading:
   scripts/sprint-service.sh unclaim $N
   gh issue edit $N --add-label SENIOR
   # → go to step 2
   ```
6. **Execute → build → test → close:**
   ```bash
   # do the work
   echo "Fixed: [what changed]" > /tmp/done-note-$N
   git commit -m "fix|feat: ... (closes #$N)" && git push
   scripts/sprint-service.sh done $N $(git rev-parse HEAD)
   ```
7. **Loop back to step 2.** Never stop between tasks.

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
