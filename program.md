# Drift Autopilot

Follow the section that matches your prompt. The watchdog passes one of:
- `"run sprint planning"` → Sprint Planning section
- `"execute senior tasks and P0 bugs"` → Senior Execution section
- `"execute junior tasks"` → Junior Execution section
- `"run autopilot"` → Standalone section (no watchdog)

## Steering notes

**Re-read before every cycle.** Human may change at any time.

_Directive:_ **Read `Docs/roadmap.md` to understand product direction. Be bold. The goal is visible, meaningful progress every cycle.**

_Override:_ STOP

**How enforcement works:** Hooks and the watchdog enforce what must not be skipped. This file guides decisions that require judgment. If Override says STOP, exit cleanly.

---

## Sprint Planning (Opus, every ~6 hours)

You are the Product Designer + Principal Engineer. session-start.sh has already injected sprint state, last session summary, and created your overhead tracking issue.

**RESUME CHECK first:**
```bash
scripts/planning-service.sh remaining
# Skip already-completed steps. Do remaining steps in order.
```

1. **Drain process feedback:** `scripts/issue-service.sh drain-feedback` → create `infra-improvement` + `sprint-task` + `SENIOR` issues for systemic problems; skip one-offs. Then: `scripts/planning-service.sh checkpoint feedback_drained`

2. **Admin replies:** `gh pr list --label report --state all` → for each PR with comments, read the report file at the referenced line, then reply to every admin comment (ashish-sadh, nimisha-26). Actionable → create sprint-task issue. `scripts/planning-service.sh checkpoint admin_replied`

3. **Bug triage:** `gh issue list --state open --label bug` — note high-priority ones. Senior handles all bug investigation.

4. **Design docs:** Note status of open design-doc Issues/PRs. Do NOT write docs or create impl tasks — senior handles all design work.

5. **Feature request triage:** `gh issue list --state open --label feature-request`
   - P0/P1 → `gh issue edit {N} --add-label sprint-task && gh issue comment {N} --body "Triaged: added to sprint."`
   - Others → `gh issue edit {N} --add-label deferred && gh issue comment {N} --body "Deferred to next cycle."`

6. **Assess state:** Read `Docs/roadmap.md`, `Docs/state.md`. Run `git log --oneline -40`. Check recent closed issues.

7. **Product review (if due):** `scripts/report-service.sh review-due || true` — if due: `scripts/report-service.sh start-review` → read both persona files → web search competitors → write using `Docs/reports/REVIEW-TEMPLATE.md` (every section required, filename `review-cycle-{N}.md`) → PR → `scripts/report-service.sh finish`. Then: `scripts/planning-service.sh checkpoint review_merged`

8. **Daily exec report (if due):** `scripts/report-service.sh daily-due || true` — if due: `scripts/report-service.sh start-exec` → write report → PR with `--label report` → merge. Then: `echo $(date +%s) > ~/drift-state/last-report-time`

9. **Create sprint tasks (cap 100 open):** `gh issue create --label sprint-task [--label SENIOR]`
   **Hard cap: the open sprint-task queue is capped at 100.** A PreToolUse
   hook blocks new creates past the cap. If the queue is near the limit:
   prune stale issues, consolidate duplicates, mark superseded ones
   `wontfix` — don't pad the queue to hit "8+". Planning quality > task
   count.
   Body must include: Goal, Files to modify, Approach, Tests, Acceptance criteria.
   SENIOR = AI pipeline, architecture, multi-file refactors. JUNIOR = food DB, UI, tests, simple fixes.
   Prioritize: P0 bugs → product focus → admin feedback → roadmap "Now" → parity gaps.
   Then: `scripts/planning-service.sh checkpoint tasks_created`

10. **Update personas + roadmap.** `scripts/planning-service.sh checkpoint personas_updated` / `roadmap_updated`

11. **Reset senior sprint_done:** `scripts/sprint-service.sh reset-sprint-done`

12. **Refresh queue:** `scripts/sprint-service.sh refresh` → `scripts/planning-service.sh checkpoint sprint_refreshed`

13. **Close planning issue:** `gh issue close $N --comment "Planning complete. Created X tasks." && gh issue edit $N --remove-label in-progress`

**DOD (ensure-clean-state.sh blocks exit until met):**
- 8+ sprint-task issues created
- All feature-requests triaged (sprint-task or deferred)
- `scripts/sprint-service.sh refresh` called
- Planning issue closed

---

## Senior Execution (Opus)

You are the senior engineer and PE. session-start.sh has injected your context, created the overhead tracking issue, and reset your 5-task budget. `scripts/sprint-service.sh next --senior` returns "none" automatically after 5 implementation tasks.

1. Check Override — if STOP, exit cleanly.

2. **Bug investigation first (no task budget cost):**
   Run `scripts/issue-service.sh bugs-needing-plan`. For EACH bug returned: read the full issue including all comments and any screenshots (use Read tool for image files). Run `scripts/issue-service.sh investigate-bug $N` and add `needs-review` label. Clear the entire backlog before moving to sprint tasks.

3. **Design docs:**
   - `scripts/design-service.sh in-review` → reply to each PR comment
   - `scripts/design-service.sh pending` → write doc on branch → PR with `--label design-doc` → add `doc-ready` label to issue
   - `scripts/design-service.sh approved-not-started` → `scripts/design-service.sh create-impl-tasks $N` → `scripts/sprint-service.sh refresh`

4. **Sprint task loop:**
   `TASK=$(scripts/sprint-service.sh next --senior --claim)` — atomically selects the next task AND marks it in-progress. Returns "none" when 5 tasks done or queue empty. If "none", exit immediately. **Do NOT use `--any` or `--junior` as fallback — senior must only work SENIOR/P0 tasks.**
   When you get a task: extract `$N` from the first word → read full issue + all comments → **post a plan comment on the GitHub issue BEFORE writing any code** (root cause + fix approach + files to change) → implement → build → test → commit → `scripts/sprint-service.sh done $N $(git rev-parse HEAD)`.
   If diagnosis reveals the task is misspecified or a duplicate, `scripts/sprint-service.sh unclaim $N` and loop. The atomic `next --claim` removes the gap where a session would read `next`, start editing, and leave no in-progress tag behind.
   - **Stale task** (issue already closed on GitHub): `scripts/sprint-service.sh session-done $N` → loop.
   - **Breaking change** (would touch 5+ public APIs or protocol files): unclaim + `gh issue edit $N --add-label blocked` + comment describing needed design → loop.
   - **Bug close:** write `echo "Resolution: ..." > /tmp/done-note-$N` before calling `done` — hook enforces non-empty resolution.

5. Can create up to 3 new Issues per session when discovering work. Add `SENIOR` label if complex.

session-compliance.sh closes the overhead issue and writes the session summary automatically on exit.

---

## Junior Execution (Sonnet)

You are the junior engineer. session-start.sh has injected your context, created the overhead tracking issue, and reset your 5-task budget. `scripts/sprint-service.sh next --junior` returns "none" automatically after 5 tasks or when the queue is truly empty (including permanent tasks).

1. Check Override — if STOP, exit cleanly.

2. **Task loop:**
   `TASK=$(scripts/sprint-service.sh next --junior --claim)` — atomically returns the next task AND marks it in-progress. Returns sprint tasks, then permanent tasks when sprint is empty, then "none" after 5 implementation tasks. If "none", exit.
   Extract `$N` from the first word → read full issue + all comments → **post a plan comment on the GitHub issue BEFORE writing any code** (what you'll do + which files) → then:
   - **Sprint task:** implement → build → test → commit → `scripts/sprint-service.sh done $N $(git rev-parse HEAD)`
   - **Permanent task:** implement → commit → `gh issue comment $N --body "Progress: ..."` → `scripts/sprint-service.sh session-done $N`. **NEVER run `gh issue close` on a permanent task — they are recurring and must stay open forever.**
   - **Stale task** (issue already closed on GitHub): `scripts/sprint-service.sh session-done $N` → loop.

3. **Too complex?** Unclaim + `gh issue edit $N --add-label SENIOR` → back to step 2.

session-compliance.sh closes the overhead issue and writes the session summary automatically on exit.

---

## Standalone (no watchdog)

Human says "run autopilot". No watchdog, no model switching.

1. Check P0 bugs → fix first.
2. Check `Docs/sprint.md` for unchecked items → pick top one.
3. No sprint items → roadmap "Now" items → failing queries → permanent tasks.
4. Execute: read → edit → build → test → commit → push. Repeat.

---

## Rules

- **Tests must pass before committing.** Run eval harness after AI changes — revert immediately if scores drop.
- **TestFlight:** hook injects mandatory publish instructions when due — follow them exactly.
- **Daily exec report:** hook injects mandatory instructions when due — follow the template exactly.
- **Every bug close requires a resolution comment** (enforced by hook — will block without it).
- **Every admin report PR comment gets a reply.**
- **Every design doc comment gets a response.**
- **P0 bugs are Priority 1 in the sprint queue.** No session is killed for P0 — current task finishes first.
- **Read full issues before implementing** — body + all comments + screenshots.
- **Post a plan comment before every implementation** (not needed for P0 bugs in emergency).
- **GitHub API:** Reads = 1pt, writes = 5pts. Budget 900pts/min. Batch edits. On 403/429: comment on current task, exit — watchdog restarts with backoff.
- **Output to `/tmp/`.** Run `xcodegen generate` if adding files. New ideas → `Docs/backlog.md`.

---

## For the human

Start standalone: `cd /Users/ashishsadh/workspace/Drift` → "run autopilot"

Start Drift Control: `echo "RUN" > ~/drift-control.txt && ./scripts/self-improve-watchdog.sh`

Pause/resume via Command Center or: `echo "PAUSE" > ~/drift-control.txt` / `echo "RUN" > ~/drift-control.txt`

Drain (finish current task then stop): `echo "DRAIN" > ~/drift-control.txt`

**Human takeover:**
1. `echo "PAUSE" > ~/drift-control.txt` — watchdog tells current session to stop after its task (~5min)
2. Open Claude normally and work. The session-start hook resets the session type to "human" so auto-publish hooks are suppressed.
3. When done: `echo "RUN" > ~/drift-control.txt` — watchdog resumes autonomous operation.
