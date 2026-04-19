# Drift Control — Sprint System Design

> Source of truth for how the autonomous sprint system works.  
> Derived from alignment sessions: 2026-04-18.  
> Update this doc when any behavior changes — do not let it drift from the code.

---

## Actors

| Actor | Model | Role |
|-------|-------|------|
| **Watchdog** | (shell) | Orchestrates sessions, detects stalls, routes work, post-session compliance |
| **Planning session** | Opus | Sprint planning, FR triage, report generation, impl task creation |
| **Senior session** | Opus | SENIOR sprint tasks, P1/P2 bug investigation, design doc writing |
| **Junior session** | Sonnet | Regular sprint tasks, P1/P2 bugs, permanent task loops |
| **Human/Admin** | — | Approves non-admin issues, reviews design docs, controls start/stop/pause |

---

## Session Routing (Watchdog)

Priority order for deciding which session to start next:

1. **Planning overdue** (6+ hours since last planning) → planning session
2. **Planning crash recovery** — open planning issue found → resume planning
3. **SENIOR work exists** (P0 bugs, SENIOR sprint tasks, P1/P2 bugs without sprint-task) → senior session
4. **Otherwise** → junior session (runs continuously)

**Junior runs continuously** until planning is overdue. No alternating with senior. Senior is only spun up when SENIOR-class work exists; when it finishes, watchdog routes back to junior.

---

## Priority Queues

### Senior (`sprint-service next --senior`)

| Priority | Work |
|----------|------|
| 1 | Admin P0 bugs (`bug` + `P0` + `sprint-task`) |
| 2 | SENIOR sprint tasks (`sprint-task` + `SENIOR` label) |
| 3 | Admin P1/P2 bugs (`bug` + `P1`/`P2` + `sprint-task`) |
| 4 | SENIOR permanent tasks (`permanent-task` + `SENIOR`) — **once per sprint** |

### Junior (`sprint-service next --junior`)

| Priority | Work |
|----------|------|
| 1 | Admin P0 bugs (`bug` + `P0` + `sprint-task`) |
| 2 | Regular sprint tasks (`sprint-task`, no `SENIOR`, no `bug`) |
| 3 | Admin P1/P2 bugs (`bug` + `P1`/`P2` + `sprint-task`) |
| 4 | Permanent tasks (`permanent-task`, no `SENIOR`) — **loops indefinitely** |

**Key difference**: Junior loops on permanent tasks indefinitely. Senior works each permanent task **once per sprint** (`sprint_done` flag), locked until planning calls `reset-sprint-done`.

**Bugs only enter the queue when admin-approved** (have `sprint-task` label). Non-admin bugs trigger watchdog routing (`count --bugs`) but are investigated and marked `needs-review` before entering the queue.

---

## Session Lifecycle

### Startup (every session type)

**Mechanically handled by hooks — sessions do not need to do this manually:**

1. `session-start.sh` hook fires automatically at session start:
   - Calls `sprint-service.sh start-session` → resets `session_tasks` counter to 0
   - Creates + claims an overhead tracking issue → stores number in `~/drift-state/current-overhead-issue`
   - Injects `~/drift-state/last-session-summary.md` content into session context
   - Injects sprint queue state, next task, product focus, design docs, report feedback
2. Session reads `program.md` for the decision flow for its session type

### Task Loop (all implementation sessions)

- Maximum **5 tasks per session** (implementation tasks only)
- **Mechanically enforced:** `sprint-service.sh next --senior/--junior` returns `"none"` automatically when `session_tasks >= 5` (counter increments in `done` and `session-done`)
- Session does not need to track a counter — just loop on `next` until it returns `"none"`
- `done` on overhead/planning-labeled tasks does NOT increment the counter

### Exit (all sessions)

**Mechanically handled by session-compliance.sh — sessions just exit:**

1. Watchdog calls `session-compliance.sh` after every exit (clean or crash)
2. `session-compliance.sh` closes the overhead tracking issue from `~/drift-state/current-overhead-issue`
3. Writes `~/drift-state/last-session-summary.md` with recent commits and interrupted task
4. Appends to Obsidian `Sessions/YYYY-MM-DD.md`
5. Watchdog then calls `cleanup_dirty_state` → `start_claude` for next session

---

## Post-Session Compliance

**`scripts/session-compliance.sh`** — called by watchdog BEFORE `cleanup_dirty_state` after every session exit (clean, crash, or stall):

1. Closes overhead tracking issue (`~/drift-state/current-overhead-issue`) with exit summary comment
2. Writes `~/drift-state/last-session-summary.md`:
   - Session type + model + exit reason (normal/crash/stall)
   - Recent commits from this session (last 2 hours)
   - Interrupted task (read from sprint-state before clear)
3. Appends to Obsidian `Sessions/YYYY-MM-DD.md`
4. Logs crash/stall exits to `process-feedback.log` (planning drains this each cycle)

Called BEFORE `cleanup_dirty_state` so the interrupted in-progress task is still readable in state. After compliance, `cleanup_dirty_state` clears all in-progress and resets git.

This ensures the next session always has a clear picture of where to pick up, even after a crash.

---

## Bug Fix Protocol

**Every bug fix, regardless of priority:**

1. **Read the full issue** — body + all comments + any screenshots/attachments + prior plan comments
2. **Post a plan comment** before writing any code:
   ```
   **Plan:** [what the bug is, root cause hypothesis]. 
   **Fix:** [what I'll change and why]. 
   **Tests:** [how I'll verify it's fixed].
   ```
3. **Implement** the fix
4. **Run tests** — fix any regressions before committing
5. **Commit** → close issue with comment

If a human replies to the plan disagreeing with the approach:
- Any subsequent session picks it up, reads full thread, posts revised plan, re-implements

---

## Breaking Change Protocol

If a session discovers mid-implementation that the fix requires a breaking change (public API change, schema migration, etc.):

1. Post a comment on the issue explaining the breaking change and why it's necessary
2. Add `blocked` label
3. Exit the task (unclaim) — do NOT implement the breaking change unilaterally
4. Planning session reviews, discusses with PE/product personas, decides approach

---

## Rate Limit Protocol

If Claude API returns a rate limit error mid-session:

1. Post a comment on the currently claimed issue: "Rate limit hit — session interrupted. Will resume next session."
2. Exit cleanly
3. Watchdog detects exit, runs compliance, starts new session after delay

---

## Design Doc Lifecycle

### Autonomously-initiated design docs (planning decided)

```
Planning adds needs-design label to sprint task
  → task skipped by junior (junior never writes design docs)
  → senior picks it up, writes design doc, opens PR with design-doc label
  → any session reviews PR, leaves comments
  → any session can approve and close design review
  → planning session (next cycle) creates implementation tasks
  → sessions implement as regular sprint tasks
```

**No human gate required** for autonomously-initiated design docs.

### Human-requested design docs

```
Human requests design via Command Center or GitHub issue
  → same flow as above
  → human must add approved label (FINAL APPROVAL — always human)
  → planning creates impl tasks only after human approval
```

**Ownership rules:**
- Writing design doc: **senior only**
- Reviewing / replying to comments: **any session** (reads full doc + context first)
- Approving autonomously-initiated: **any session**
- Approving human-requested: **human only**
- Creating impl tasks: **planning session**

---

## Bug Lifecycle

### Admin-filed bug (any priority P0/P1/P2)

```
Filed (admin via Command Center)
  → auto-labeled: bug + priority + sprint-task
  → enters sprint queue at correct priority tier
  → session claims it
  → reads full issue (body + comments + screenshots)
  → posts plan comment
  → implements fix
  → runs tests (fixes regressions immediately)
  → commits to main
  → closes issue with summary comment
```

**No approval needed.** Admin filing = approval. Any session handles it.

### Non-admin-filed bug (any priority P0/P1/P2)

```
Filed (anyone via GitHub)
  → session discovers it (heartbeat scan or investigation step)
  → reads full issue
  → posts plan comment
  → adds needs-review label
  → moves on (does NOT implement)
  → human clicks "Approve → Sprint" in Command Center
  → sprint-task label added, needs-review removed
  → enters sprint queue → session claims, implements, closes
```

**All priorities including P0 require admin approval if non-admin filed.**

### P0 behavior

P0 is **first in queue**, not an interrupt. No session is killed for P0. Planning is never interrupted for P0. The current task finishes, then P0 is returned by `sprint-service next`.

---

## Senior Bug Investigation

Before picking up sprint queue tasks, senior:

1. Queries all unapproved bugs: `issue-service bugs-needing-plan`
2. For each bug (no limit per session — clears full backlog):
   - Reads full issue (body + comments + screenshots)
   - Posts investigation plan comment
   - Adds `needs-review` label
   - Moves to next bug
3. Investigation does **not** count toward the 5-task limit
4. After clearing investigation backlog → checks sprint queue (`sprint-service next --senior`)

---

## Feature Request Lifecycle

### Admin-filed feature request

Admin has two options in Command Center at filing time:
- **"Add to Sprint now"** — adds `sprint-task` immediately, enters queue
- **"Send to Planning"** — planning session triages it next cycle

### Non-admin feature request

```
Filed → sits untriaged
  → planning session picks it up next cycle
  → planning posts plan/recommendation as comment
  → planning adds needs-review label
  → human reviews, approves via Command Center (adds sprint-task)
  → enters sprint queue
```

Untriaged FRs (no `sprint-task` AND no `deferred` label) block planning exit.

---

## Design Doc Needed (`needs-design` label)

- **Planning** adds `needs-design` label at task creation time for complex features
- **Junior** skips any task with `needs-design` — not junior's domain
- **Senior** picks it up: writes design doc first, then implements (in same or later session)

---

## Planning Session Responsibilities

Runs every 6+ hours (watchdog triggers when overdue). Every planning cycle:

1. Read `last-session-summary.md` — understand where sessions left off
2. Open the planning issue (creates one if none exists)
3. Address human comments from previous exec report PRs — always done before anything else
4. Check `blocked` issues — discuss with PE/product personas, update acceptance criteria, remove `blocked` label
5. Drain process feedback log (`issue-service drain-feedback`) — file `infra-improvement` issues for systemic problems
6. Triage untriaged feature requests — post plan, add `needs-review` or `sprint-task`
7. Triage untriaged non-admin bugs — post plan, add `needs-review`
8. Check autonomously-initiated design docs — any session can approve; create impl tasks
9. Check human-requested design docs — only create impl tasks after human approval
10. Check product focus / roadmap — set direction for sprint
11. Generate daily exec report (if 24h+ since last report) — posts as GitHub PR
12. Product review (every cycle) — reflect on last sprint, set direction for next
13. Reset senior permanent task `sprint_done` flags: `sprint-service reset-sprint-done`
14. Create sprint-task issues (8+ per cycle)
15. Update personas + roadmap
16. Run full Obsidian knowledge base scan (code graph + architecture audit)
17. Close planning issue

---

## Permanent Tasks

- `permanent-task` label — never closed on GitHub
- **Junior**: picks up after all sprint tasks done, loops indefinitely updating progress, no per-sprint budget. Junior ignores `sprint_done` flag.
- **Senior**: picks up after SENIOR sprint tasks done, works each task **once per sprint** (`sprint_done` flag), locked until planning calls `reset-sprint-done`
- `session-done <N>`: marks done locally without GitHub close; sets `sprint_done=True` for permanent tasks

---

## Stale State Handling

State refresh runs every ~1 minute. When session discovers a mismatch (issue closed on GitHub but state says open):

1. Call `sprint-service session-done <N>` — fixes local cache
2. Log "stale state corrected for #N — moving on"
3. Pick next task

This prevents the deadlock where `sprint-service next` keeps returning a closed issue.

---

## Stall Detection & Recovery

| Session type | Stall threshold | Nudge wait | Action |
|-------------|----------------|-----------|--------|
| Planning | 1 hour | 5 min | Kill + resume via open planning issue |
| Senior | 30 min | 5 min | Kill + unclaim task + start fresh |
| Junior | 30 min | 5 min | Kill + unclaim task + start fresh |

**Nudge before kill**: Watchdog logs stall warning, waits 5 more minutes. If still no progress → kills and restarts.

**After kill**: `cleanup_dirty_state` → unclaims task → `session-compliance.sh` → next session picks up task from the beginning.

---

## Pause / Resume

**Pause**: Watchdog stops launching new sessions. Current session finishes its current task, then exits.

**Resume**: Watchdog presents a summary of the current queue (next session type, pending tasks) via CLI. Human confirms. Watchdog starts next session.

---

## Crash Recovery

**Session crash mid-task:**
- Watchdog detects (process gone or no log output)
- Runs `session-compliance.sh` (best-effort — captures what was done)
- Runs `cleanup_dirty_state` — discards changes, unclaims task
- Next session picks up the task from the beginning

**Planning crash:**
- Open planning issue remains on GitHub
- Watchdog detects open planning issue → routes next session to resume planning

---

## Heartbeat (Watchdog Loop)

Every ~1 minute:
1. `sprint-service refresh` — sync GitHub → local state
2. Check session health (still running? log updated recently?)
3. If stall threshold exceeded → nudge (log warning) → wait 5min → kill if still stalled
4. If session exited → run `session-compliance.sh` → route next session per routing rules

Compliance cache (P0 bug list, product focus) refreshed every minute.

---

## Exec Report Format

Runs every planning cycle if 24h+ since last report. PE + PM personas collaborate.

**Contains** (readable in 2-3 minutes):
- **Headline** — one sentence on what moved
- **Product snapshot** — build#, test count, food DB size, AI tools, coverage
- **What shipped** — user-visible bullet list (not refactor details)
- **What went well**
- **Strategic direction** — where the product is heading this sprint
- **Token / cost breakdown** — where investment went this sprint (by session type), rough dollar cost
- **Risks & blockers**
- **Open strategic questions for human** — decisions that need human input
- **Focus for next period**

Planning always addresses human comments on the previous exec report PR before starting any other planning work.

Planning also maintains and updates:
- **Product taste doc** (`Docs/product-taste.md`) — evolving record of human nudges, decisions, aesthetic preferences; used to align future sessions with the product's direction
- **Product strategy doc** — updated with decisions from this cycle

---

## LLM Eval Protocol

After any commit that touches AI routing, intent classification, or LLM prompt files:

```bash
pkill -9 -f xcodebuild 2>/dev/null; sleep 2
xcodebuild test -project Drift.xcodeproj -scheme Drift \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:DriftLLMEvalTests 2>&1 | grep -E "📊|❌|✔|✘|passed|failed"
```

If eval scores drop → revert the commit immediately, investigate before re-implementing.

---

## TestFlight Protocol

Pre-flight checklist before publishing:
1. All unit tests pass
2. Build succeeds
3. 3+ hours since last TestFlight publish
4. No open P0 bugs

Session increments `CURRENT_PROJECT_VERSION` in `project.yml`, then publishes.

---

## Obsidian Knowledge Base (Planned)

Local markdown vault at `~/drift-knowledge/` (valid Obsidian vault — Obsidian reads regular `.md` files).

**Structure:**
```
/Architecture    — system architecture, module relationships
/Decisions       — non-obvious technical choices and rationale
/Features        — per-feature-area docs (AI, food DB, UI, analytics)
/Sessions        — per-day session logs (what ran, what was done)
```

**Update rules:**
- Sessions update **after each task** for what they touched (architecture changes → `/Architecture`, technical decisions → `/Decisions`)
- `/Features` updated only for **structural changes** (new schema, new data source) — not for individual entries like single food items
- `/Decisions` gets an entry whenever a session makes a **non-obvious technical choice** during a task
- Planning runs a **full audit** each cycle (consolidates + ensures consistency)

**Code graph:**
- **Incremental**: post-commit hook regenerates graphs only for changed Swift modules (~5s)
- **Full scan**: planning runs complete dependency scan each cycle

**Reading rule**: Sessions read relevant Obsidian notes **before** exploring source code — saves tokens by getting context first.

---

## Commit & Close Rules

- All commits go directly to `main` (no PRs from sessions)
- Issue close: always `gh issue close <N> --comment "<summary>"` — comment required
- Before risky operations: session posts a comment explaining what it's about to do, then proceeds
- Tests run after every commit — session fixes regressions before moving on

---

## Blocked Tasks

When a session cannot complete an acceptance criterion:
1. Posts a comment explaining the block and what was completed
2. Checks off completed items in the DoD
3. Adds `blocked` label
4. Moves on to next task

Planning session picks up blocked issues each cycle, clarifies with PE/product personas, removes `blocked` label, reintroduces to sprint.

---

## Issue Comment Scanning

Any session scans for unanswered human comments on open AND closed issues during startup. Reads full issue context before replying. Not tied to task ownership.

---

## Process Improvements

When a session discovers a broken script, unclear instruction, or process problem:
- Files an `infra-improvement` sprint issue
- Planning session triages it next cycle

Sessions do NOT modify `program.md` — human only.

---

## State Files

| File | Purpose |
|------|---------|
| `~/drift-state/sprint-state.json` | Task queue, in-progress tracking, per-sprint done flags |
| `~/drift-state/planning-issue` | Number of the open planning issue (crash recovery) |
| `~/drift-state/last-planning-time` | Timestamp of last planning session start |
| `~/drift-state/last-report-time` | Timestamp of last daily report |
| `~/drift-state/last-session-summary.md` | What the previous session did — read at startup |
| `~/drift-state/cache-p0-bugs` | Live P0 bug list (refreshed every ~1min) |
| `~/drift-state/cache-product-focus` | Current product focus from roadmap |
| `~/drift-state/process-feedback.log` | Session hiccup log (drained by planning) |
| `~/drift-state/model-config` | Per-session-type model overrides |
| `~/drift-control.txt` | RUN / PAUSE / STOP / DRAIN |
