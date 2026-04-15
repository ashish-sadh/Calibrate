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
   - Read `Docs/roadmap.md`, `Docs/state.md`, `Docs/ai-parity.md`, `Docs/failing-queries.md`
   - `git log --oneline -40` (more history since longer sprint)
   - Review closed issues since last planning: `gh issue list --state closed --label sprint-task --json number,title,closedAt --jq '.[] | select(.closedAt > "LAST_PLAN_DATE")'`
   - Check test count, coverage snapshot, eval results
8. **Product review:**
   - Web search competitors (Boostcamp, MFP, Whoop, Strong, MacroFactor)
   - Write review report (exec summary, scorecard, what shipped, competitive position, designer + engineer discussion)
   - Open review PR with `report` label, then merge immediately: `gh pr merge --squash --delete-branch && git checkout main && git pull`
   - (Merging immediately makes it visible on dashboard. Humans can still comment on merged PRs.)
9. **Create sprint-task Issues (target 8-12 issues for 6h sprint):**
   - For each task: `gh issue create --label sprint-task --label SENIOR/JUNIOR`
   - Include in body: Goal, Files (list specific files to modify), Approach (step-by-step), Edge cases, Tests (specific test cases to write), Acceptance criteria
   - Break large features into multiple Issues — prefer 3 small Issues over 1 big one
   - Mix of sizes: ~2-3 SENIOR (architecture, AI, multi-file) + ~6-8 JUNIOR (UI, tests, food DB, fixes)
   - **SENIOR:** AI pipeline, architecture, multi-file refactors, P0 bugs, design doc implementation
   - **JUNIOR:** Food DB, single-file UI, tests, docs, simple fixes, well-specified work
   - Prioritize: P0 bugs > **product focus** > admin feedback > roadmap "Now" items > parity gaps > polish
11. **Update personas** — append "What I learned this review"
12. **Update roadmap** — apply agreed changes
13. **Close the planning Issue** — if the prompt says "close Issue #N", run: `gh issue close N --comment "Sprint planning complete. Created X sprint-task issues. Review PR: #Y."` and `gh issue edit N --remove-label in-progress`
14. **Exit** — watchdog restarts with appropriate model for first task

---

## Senior Execution (Opus)

You are the senior engineer AND the PE (Principal Engineer). Execute complex tasks and steward design docs.

1. Re-read steering notes. Stop if override says STOP.
2. **P0 bugs first — MANDATORY, before anything else:** `gh issue list --state open --label P0` → fix ALL of these before touching design docs, sprint-tasks, or features. Add SENIOR label if missing: `gh issue edit {N} --add-label SENIOR`
   - Read the full issue body. If it contains screenshots (`![screenshot]`), **download and view them** — the image shows the actual broken UI/behavior. Use the Read tool on the image URL or local path (`Docs/screenshots/`). Don't guess from text alone.
   - Do NOT proceed to step 3 until all P0 bugs are fixed or escalated.
3. **P0 feature requests:** `gh issue list --state open --label feature-request --label P0` → create sprint-task Issue (SENIOR) for it immediately, add to current sprint
4. **Design docs (label-driven lifecycle):** `gh issue list --state open --label design-doc` → for each:
   - **No `doc-ready` label** (pending): write the doc.
     1. `git checkout -b design/{N}-SHORT-NAME`
     2. Write doc in `Docs/designs/{N}-SHORT-NAME.md` using TEMPLATE.md format
     3. Commit, push, create PR: `gh pr create --label design-doc --body "Design doc for #N"`
     4. Link PR to issue: `gh issue edit {N} --body "PR: #PR_NUMBER\n\nORIGINAL_BODY"`
     5. Mark ready: `gh issue edit {N} --add-label doc-ready`
     6. `git checkout main`
   - **Has `doc-ready`, no `approved`** (in review): check PR for human comments, respond, revise doc, push.
   - **Has `approved`**: create implementation tasks with label `design-impl-{N}`, merge the PR.
   - **All `design-impl-{N}` tasks closed**: close the original design-doc issue.
   - **Every senior session must check design doc status.**
5. **Pick next SENIOR sprint-task:** `gh issue list --state open --label sprint-task --label SENIOR` → read the spec → execute
6. Build → test → commit (reference #N in message) → push
7. **Close the Issue with a comment:** what was fixed + commit hash. Never close silently.
11. **Can create max 3 new Issues per session** (SENIOR or JUNIOR) when discovering work.
12. Repeat until no SENIOR/P0/design-doc issues left → exit. Watchdog restarts with Sonnet.

---

## Junior Execution (Sonnet + Opus advisor)

You are the junior engineer with a senior advisor. Execute well-specified tasks.

1. Re-read steering notes. Stop if override says STOP.
2. **P0 bugs — escalate to SENIOR if ANY of:**
   - Touches 3+ files
   - Involves AI pipeline (IntentClassifier, ToolRanker, AIToolAgent, ToolRegistration)
   - Requires architecture changes
   - You're unsure after reading the code for 5 minutes
   - Otherwise fix it: `gh issue edit {N} --add-label SENIOR` → skip if escalating.
   - **Always check for screenshots** in the issue body. If present, download and view them before fixing — they show the actual broken behavior.
3. **Pick next JUNIOR sprint-task:** `gh issue list --state open --label sprint-task --label JUNIOR` → read spec → execute
4. If task is too complex (same criteria as P0 above) → `gh issue edit {N} --add-label SENIOR --remove-label JUNIOR` → skip
5. Build → test → commit (reference #N in message) → push
6. **Close Issue with comment:** what was done + commit hash. Never close silently.
7. **When no JUNIOR sprint-tasks left → work on permanent tasks:**
   - `gh issue list --state open --label permanent-task` → pick the one you haven't worked on most recently
   - Do the work, then **comment on the Issue** with what you did (don't close it — permanent tasks stay open)
   - Before running tests: `pkill -9 -f xcodebuild 2>/dev/null; sleep 2`
8. Repeat forever. Sonnet never idles.

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
