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

---

## Sprint Planning (Opus, every ~3 hours)

You are the Product Designer + Principal Engineer. This is a replanning session.

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
   - `gh issue list --state open --label design-doc` → write docs for new requests
   - `gh pr list --label design-doc --state open` → respond to comments, revise
   - `gh pr list --label design-doc --label approved` → create implementation Issues, merge PR
5. **Product review:**
   - Read `Docs/roadmap.md`, `Docs/state.md`, `git log --oneline -20`
   - Web search competitors (Boostcamp, MFP, Whoop, Strong, MacroFactor)
   - Write review report (exec summary, scorecard, what shipped, competitive position, designer + engineer discussion)
   - Open review PR with `report` label
6. **Create sprint-task Issues:**
   - For each task: `gh issue create --label sprint-task --label SENIOR/JUNIOR`
   - Include in body: Goal, Files, Approach, Edge cases, Tests, Acceptance criteria
   - **SENIOR:** AI pipeline, architecture, multi-file refactors, P0 bugs, design doc implementation
   - **JUNIOR:** Food DB, single-file UI, tests, docs, simple fixes, well-specified work
7. **Update personas** — append "What I learned this review"
8. **Update roadmap** — apply agreed changes
9. **Exit** — watchdog restarts with appropriate model for first task

---

## Senior Execution (Opus)

You are the senior engineer. Execute complex tasks that need judgment.

1. Re-read steering notes. Stop if override says STOP.
2. **P0 bugs first:** `gh issue list --state open --label P0` → fix these before anything else
3. **Pick next SENIOR sprint-task:** `gh issue list --state open --label sprint-task --label SENIOR` → read the spec → execute
4. **Before editing any file: READ it first.** Understand types, signatures, imports. Never edit blind.
5. **Boy scout rule:** Clean what you touch. Read `Docs/principles/` for guidance.
6. Build → test → commit → push
7. **Close the Issue with a comment:** what was fixed + commit hash. Never close silently.
8. **Can create max 3 new Issues per session** (SENIOR or JUNIOR) when discovering work.
9. Repeat until no SENIOR/P0 issues left → exit. Watchdog restarts with Sonnet.

---

## Junior Execution (Sonnet + Opus advisor)

You are the junior engineer with a senior advisor. Execute well-specified tasks.

1. Re-read steering notes. Stop if override says STOP.
2. **P0 bugs:** If straightforward → fix. If complex/ambiguous → `gh issue edit {N} --add-label SENIOR` → skip.
3. **Pick next JUNIOR sprint-task:** `gh issue list --state open --label sprint-task --label JUNIOR` → read spec → execute
4. If task is too complex → `gh issue edit {N} --add-label SENIOR --remove-label JUNIOR` → skip
5. **Before editing: READ first.** Boy scout rule applies.
6. Build → test → commit → push
7. **Close Issue with comment:** what was done + commit hash.
8. **When no JUNIOR sprint-tasks left → work on permanent-task Issues:**
   - `gh issue list --state open --label permanent-task` → pick one
   - Do the work, then **comment on the Issue** with what you did (don't close it — permanent tasks stay open)
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
