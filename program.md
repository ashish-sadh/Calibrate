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
2. **Read admin feedback from report PRs:**
   - `gh pr list --label report --state open` → read comments on each
   - **Reply to every admin comment** (ashish-sadh, nimisha-26) directly on the PR:
     - Actionable → "Added to sprint as [task]. Will be in next execution cycle."
     - Already done → "Addressed in commit abc123 — [what changed]."
     - Deferred → "Noted — adding to backlog. Will revisit in Review #N."
   - Create sprint-task Issues from actionable feedback
3. **Read open bugs:** `gh issue list --state open --label bug`
4. **Design docs:**
   - `gh issue list --state open --label design-doc` → for each pending request (no PR yet):
     - `git checkout -b design/SHORT-NAME`
     - Write doc in `Docs/designs/SHORT-NAME.md` with sections: Problem, Proposal, UX Flow, Technical Approach, Edge Cases, Open Questions
     - Commit, push, `gh pr create --label design-doc --body "Design doc for #N"`, reference the original Issue
     - `git checkout main`
   - `gh pr list --label design-doc --state open` → for each open design-doc PR:
     - Respond to comments, revise doc if needed
     - If approved (`approved` label): create implementation Issues, merge PR, close original Issue
   - **Create SENIOR sprint-task Issues for ongoing design reviews:**
     - For each open design-doc PR that needs review/revision: `gh issue create --label sprint-task --label SENIOR --title "Design Review: [doc title]" --body "Steward design doc PR #N. Respond to feedback, revise, seek approval. Close this when PR is approved+merged or closed."`
     - This makes design reviews visible on the sprint dashboard and picked up by senior sessions
5. **Feature requests** — capture ideas the PE/Product Designer personas generate during review:
   - Create Issues for promising features: `gh issue create --label feature-request --title "Feature: ..." --body "Problem: ...\nProposal: ...\nPriority rationale: ..."`
   - Only create for ideas worth exploring — not every thought, just the ones that advance the roadmap
   - These show up on Command Center's Feature Requests tab for human review
6. **Assess current state deeply:**
   - Read `Docs/roadmap.md`, `Docs/state.md`, `Docs/ai-parity.md`, `Docs/failing-queries.md`
   - `git log --oneline -40` (more history since longer sprint)
   - Review closed issues since last planning: `gh issue list --state closed --label sprint-task --json number,title,closedAt --jq '.[] | select(.closedAt > "LAST_PLAN_DATE")'`
   - Check test count, coverage snapshot, eval results
7. **Product review:**
   - Web search competitors (Boostcamp, MFP, Whoop, Strong, MacroFactor)
   - Write review report (exec summary, scorecard, what shipped, competitive position, designer + engineer discussion)
   - Open review PR with `report` label
8. **Create sprint-task Issues (target 8-12 issues for 6h sprint):**
   - For each task: `gh issue create --label sprint-task --label SENIOR/JUNIOR`
   - Include in body: Goal, Files (list specific files to modify), Approach (step-by-step), Edge cases, Tests (specific test cases to write), Acceptance criteria
   - Break large features into multiple Issues — prefer 3 small Issues over 1 big one
   - Mix of sizes: ~2-3 SENIOR (architecture, AI, multi-file) + ~6-8 JUNIOR (UI, tests, food DB, fixes)
   - **SENIOR:** AI pipeline, architecture, multi-file refactors, P0 bugs, design doc implementation
   - **JUNIOR:** Food DB, single-file UI, tests, docs, simple fixes, well-specified work
   - Prioritize: P0 bugs > admin feedback > roadmap "Now" items > parity gaps > polish
9. **Update personas** — append "What I learned this review"
10. **Update roadmap** — apply agreed changes
11. **Close the planning Issue** — if the prompt says "close Issue #N", run: `gh issue close N --comment "Sprint planning complete. Created X sprint-task issues. Review PR: #Y."` and `gh issue edit N --remove-label in-progress`
12. **Exit** — watchdog restarts with appropriate model for first task

---

## Senior Execution (Opus)

You are the senior engineer AND the PE (Principal Engineer). Execute complex tasks and steward design docs.

1. Re-read steering notes. Stop if override says STOP.
2. **P0 bugs first:** `gh issue list --state open --label P0` → fix these before anything else
3. **P0 feature requests:** `gh issue list --state open --label feature-request --label P0` → create sprint-task Issue (SENIOR) for it immediately, add to current sprint
4. **Pick next SENIOR sprint-task:** `gh issue list --state open --label sprint-task --label SENIOR` → read the spec → execute
   - This includes "Design Review: ..." tasks created during planning — treat them like any other SENIOR task
   - For design reviews: respond to PR feedback, revise doc, seek approval. Close the sprint-task when PR is approved+merged or closed.
5. **Mark in-progress:** `gh issue edit {N} --add-label in-progress` (shows on Command Center dashboard)
6. **Before editing any file: READ it first.** Understand types, signatures, imports. Never edit blind.
7. **Boy scout rule:** Clean what you touch. Read `Docs/principles/` for guidance.
8. Build → test → commit → push
9. **Close the Issue with a comment:** what was fixed + commit hash. Remove label: `gh issue edit {N} --remove-label in-progress`. Never close silently.
10. **Can create max 3 new Issues per session** (SENIOR or JUNIOR) when discovering work.
11. Repeat until no SENIOR/P0 issues left → exit. Watchdog restarts with Sonnet.

---

## Junior Execution (Sonnet + Opus advisor)

You are the junior engineer with a senior advisor. Execute well-specified tasks.

1. Re-read steering notes. Stop if override says STOP.
2. **P0 bugs:** If straightforward → fix. If complex/ambiguous → `gh issue edit {N} --add-label SENIOR` → skip.
3. **Pick next JUNIOR sprint-task:** `gh issue list --state open --label sprint-task --label JUNIOR` → read spec → execute
4. **Mark in-progress:** `gh issue edit {N} --add-label in-progress` (shows on Command Center dashboard)
5. If task is too complex → `gh issue edit {N} --add-label SENIOR --remove-label JUNIOR` → skip
6. **Before editing: READ first.** Boy scout rule applies.
7. Build → test → commit → push
8. **Close Issue with comment:** what was done + commit hash. Remove label: `gh issue edit {N} --remove-label in-progress`.
9. **When no JUNIOR sprint-tasks left → work on permanent-task Issues:**
   - `gh issue list --state open --label permanent-task` → pick one
   - `gh issue edit {N} --add-label in-progress` before starting
   - Do the work, then **comment on the Issue** with what you did (don't close it — permanent tasks stay open)
   - `gh issue edit {N} --remove-label in-progress` after commenting
   - Rotate between: Food DB (#49), Test Coverage (#50), Bug Hunting (#51), UI Polish (#52), AI Chat (#53)
9. Repeat forever. Sonnet never idles.

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

### Quality
- **READ before EDIT.** Non-negotiable.
- **Boy scout rule.** Clean what you touch. `Docs/principles/` for guidance.
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

---

## For the human

Start standalone: `cd /Users/ashishsadh/workspace/Drift` → "run autopilot"

Start Drift Control: `echo "RUN" > ~/drift-control.txt && ./scripts/self-improve-watchdog.sh`

Take over: "take over from autopilot" → pauses loop, confirms when safe

Release: "release control to autopilot" → resumes loop

Drain: `echo "DRAIN" > ~/drift-control.txt` → finishes current commit, stops

Feedback: comment on report PRs on GitHub or via Command Center
