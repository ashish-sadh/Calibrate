# Harness Phase 3 — Planning slim, routine-fix worker, strict one-epic

**Status:** Shipped 2026-05-26 across 4 commits.
**Predecessor:** `harness-phase-2-workflows.md` (epics + blocker-elevation + /ui-evaluator).
**Motivation:** User feedback 2026-05-25 — "planning requires so much context and code read gathering and critical analysis, I want planning to think hard, research, and come up with one epic and finish related tasks and routine jobs to fix bugs etc. always there. I feel there is so much bureaucracy right now that harness doesn't work well."

---

## The three asks, translated

1. **Planning should think + research + emit one epic.** Today's planning runs 15 steps; 7 are load-bearing. The ceremonial 8 should leave planning's critical path so the token budget redirects to *understanding* the next arc.
2. **Routine bug-fix work should always be there.** Today every fix routes through planning → claim → debate → commit. The user wants an always-on background worker for low-risk bugs.
3. **Cut bureaucracy.** Delete dead labels, consolidate supervisor loops, move ceremony off the critical path.

## User decisions that shaped this rollout

- **Strict "one epic, nothing else"** — planning emits ONLY an epic per cycle. Standalone sprint-tasks no longer exist as a category. Bugs auto-flow to `routine-fix` (drained by the always-on junior worker); permanent-tasks continue via their own `sprint_session_done` lifecycle.
- **Watchdog-loop staleness checks** — knowledge-curate and admin-replies fire as new bands inside the existing watchdog decision tree when their stamp files go stale. No new launchd plists; same serial spawn slot the watchdog already manages.

## What shipped (commit-by-commit)

### Phase 3a — Foundations (`9d18e98b`)

- Created `routine-fix` GitHub label.
- Verified 15 unused labels were already cleaned up by an earlier session.
- `sprint-service.sh cmd_next` — new Priority 1.7 band: routine-fix jumps above regular junior sprint-tasks, below SENIOR + P0 work. Same `admin_approved()` gate.
- `sprint-service.sh cmd_epic` — body truncation at 200 lines, with `epic_body_truncated=true|false` signal line. `<goal>` + `<subtasks>` + `<visual_criteria>` survive every truncation by convention (early in the body).
- 4 new tier-0 tests for the routine-fix band (`test-drift-control.sh`).

### Phase 3b — Routine worker live (`b95fe3a3`)

- `junior/SKILL.md` step 4.5 — synthesized Done-When branch. When the claimed task has `routine-fix` AND no explicit `<done_when>`, junior synthesizes:
  - Criterion 1 (weight 3): tier-0 + tier-1 tests pass after diff (hook-enforced).
  - Criterion 2 (weight 2): the file/symbol named in the bug body is touched.
  - Criterion 3 (weight 1): diff ≤100 lines.

  Posted as the first comment on the issue, with a header `<!-- synthesized by junior routine-fix mode -->`. `require-done-when.sh` then sees the block and the rest of the junior flow proceeds normally. If an explicit `<done_when>` already exists, use it and skip the synthesis.

- `sprint-service.sh count --routine-fix` filter — mirrors the cmd_next admin_approved gate exactly so `count --routine-fix > 0` predicts the next junior claim.
- `self-improve-watchdog.sh` default-junior branch logs `"Routine-fix queue: N — junior"` when the queue has work. Routing decision unchanged.

**Choice: junior mode-flag, NOT a sibling `/junior-routine` skill.** Plan-agent's pushback in the design phase: a sibling would drift out of sync with `/junior` and double maintenance. One skill, branched at step 4.5.

### Phase 3d — Self-feeding queue (`b95fe3a3`)

- `sprint-service.sh cmd_refresh` calls new `auto_promote_orphan_bugs` after every refresh. Any open issue labeled `bug` with NO `routine-fix` label, NOT referenced as a sub-task in any open epic, AND older than 24h gets the `routine-fix` label via `gh issue edit --add-label`. Idempotent.

This is what makes strict-one-epic workable: bugs aren't lost when planning stops filing standalone tasks. They self-route to the always-on worker after one cycle.

**Subtle parser issue:** the regex `r'<task\s+[^>]*issue=["\']?#?(\d+)'` reused from `cmd_epic` couldn't be used verbatim — bash's heredoc lexer choked on the `\'` inside a single-quoted heredoc inside a `$(...)` context. The auto-promote function uses `chr(39)` to build the character class instead, so the source has no embedded single-quote at all.

### Phase 3c — Planning slim + staleness bands + /admin-replies + stuck-epic cap (this commit)

Five changes that land together:

#### Watchdog staleness bands

Two new bands inserted between the planning-due check and the P0/SENIOR/bug check:

```
elif _is_stale ~/drift-state/last-knowledge-curate-at 604800 → /knowledge-curate (junior model)
elif _is_stale ~/drift-state/last-admin-replies-at 86400      → /admin-replies (junior model)
```

Each band is stamp-gated, so it fires at most once per stamp interval regardless of how often the watchdog ticks. They sit ABOVE epic/senior work because they're cheap, run rarely, and prevent ceremony decay.

`_is_stale` helper added near `get_model` — checks stamp file mtime against the interval. Returns 0 (true / stale) if the stamp is missing.

#### New `/admin-replies` skill

Sonnet model, ~5k tokens per cycle. Reads open report PRs (`gh pr list --state open --label report`), finds admin comments since the last stamp, replies where appropriate (short answer / status cite / acknowledgment-with-followup), stamps `~/drift-state/last-admin-replies-at`, exits. Was bundled inside `/planning` step 3; now its own skill so planning can stay focused on the next epic.

The skill's scope is deliberately tight: it can reply to PR comments AND log followups to `~/drift-state/admin-replies-followups.log`, but it never files sprint-tasks or modifies the queue.

#### Stuck-epic 2-cycle cap

Under strict-one-epic mode, planning should not fire while a prior epic is still open. The cap is enforced at the planning-due branch of the watchdog:

```bash
if planning-due AND open_epics > 0 AND stuck_cycles < 2:
    bump stuck_cycles; skip planning; fall through to other bands
elif planning-due AND (open_epics == 0 OR stuck_cycles >= 2):
    if stuck_cycles >= 2:
        touch ~/drift-state/planning-override-stuck-epic
        log "override mode"
    rm stuck_cycles_file
    fire planning
```

Helper `_count_open_epics` calls `gh issue list --state open --label epic --json number --jq length`. Stamp file `~/drift-state/stuck-epic-cycles` tracks the counter.

In override mode, planning's step 2 detects the stamp file, removes it, and either splits / wontfixes / labels `needs-human` the stuck epic instead of (or in addition to) drafting a new arc.

#### Planning SKILL.md rewrite (15 steps → 8)

| Old step | New disposition |
|---|---|
| 1. Read tenets + signs | Kept as step 1 + add staleness self-check |
| 2. Drain feedback | Kept as step 3 |
| **3. Reply to admin comments** | **Cut — moved to `/admin-replies` skill** |
| 4. Triage open bugs | Slimmed: P0 only (P1/P2 auto-route to routine-fix). Step 4 |
| 5. Process design-doc backlog | Kept as step 5 |
| 6. Triage feature requests | Kept as step 6 |
| 7. Append to decisions.md | Kept (tightened bar: only cross-cutting). Implicit step, no number |
| **8. Run /knowledge-curate weekly** | **Cut — moved to watchdog staleness band** |
| 9. Draft 8+ sprint-tasks | **Amended to "Draft ONE epic"** at step 8 |
| 10. Debate-moderator | Kept inside step 8 |
| 11. Create issues | Kept inside step 8 |
| **12. Update roadmap.md** | **Cut — folded into /knowledge-curate** |
| **13. Update personas** | **Cut — folded into /knowledge-curate** |
| 14. Refresh sprint-service | Kept as step 9 |
| 15. Exit | Kept as step 9 (amended exit condition) |

**New steps:**

- **Step 2** — Detect override mode (`~/drift-state/planning-override-stuck-epic`). If set: scope the stuck epic instead of drafting a new arc.
- **Step 7a** — Optional `WebSearch` grounding for new arcs (~2-5k tokens). Cite findings in the epic's `<goal>`.
- **Step 7b** — Spawn `Agent: Explore` (read-only) to grep + read the code area the next arc will touch. Returns file:line citations that ground the epic's `<done_when>` criteria. **This is what planning's redirected budget funds.**

New exit condition: epic-labeled issue exists, prior epics are closed OR the new epic has an `<override>` block, sprint-state refreshed.

## Failure modes the new shape introduces + mitigations

1. **Routine-fix tarpit** — junior ships a "fix" that breaks main with wrong-fit synthesized Done-When. Mitigation: synthesized criterion 1 (tier-0 + tier-1 tests) is hook-enforced; if those fail, no commit lands. Same gate as today.

2. **Epic deadlock** — if exit condition is "previous epic closed," a stuck epic blocks planning forever. Mitigation: 2-cycle stuck cap; planning fires in override mode after, can mark `needs-human`, split, or `wontfix`.

3. **Routine queue starvation** — if no admin labels bugs `routine-fix`, junior idles. Mitigation: auto-promote orphan bugs after 1 cycle (phase 3d, shipped `b95fe3a3`).

4. **Watchdog band-priority inversion** — if knowledge-curate / admin-replies bands sit too high, they push epic work down indefinitely. Mitigation: stamp-gated so they fire at most once per interval.

5. **Single-epic context pollution** — epic body grows with sub-task notes, every senior session pays more. Mitigation: 200-line cap in `cmd_epic` output (phase 3a, shipped `9d18e98b`).

6. **Strict mode starves non-bug standalone work** — feature requests that don't fit the active epic and aren't bugs have nowhere to go. Mitigation: such requests either (a) become the next epic when this one closes, (b) get `routine-fix`-labeled if admin judges them low-risk, or (c) admin opens a `<override>` in the next planning epic body to re-scope.

## Critical files

- `scripts/sprint-service.sh` — `cmd_next` routine-fix band (3a), `cmd_epic` body cap (3a), `count --routine-fix` filter (3b), `cmd_refresh` auto-promote (3d).
- `scripts/self-improve-watchdog.sh` — `_is_stale` + `_count_open_epics` helpers (3c), staleness bands (3c), stuck-epic 2-cycle cap (3c), routine-fix log message (3b).
- `.claude/skills/junior/SKILL.md` — step 4.5 synthesized Done-When (3b).
- `.claude/skills/planning/SKILL.md` — full rewrite (3c).
- `.claude/skills/admin-replies/SKILL.md` — new skill (3c).
- `scripts/test-drift-control.sh` — 4 new tier-0 cases for the routine-fix band (3a).

## Verification

- Sprint-service tier-0: 230/230 passing.
- Live `sprint-service.sh refresh` runs without error; auto-promote correctly skips bugs already referenced by open epics.
- Live `sprint-service.sh epic 839` returns epic #849 with truncation-false (current body is 68 lines).
- Watchdog syntax check: `bash -n self-improve-watchdog.sh` clean.

End-to-end after the four phases ship — expected outcome:

- Watchdog spawns planning at most once (or zero if a prior epic is still open).
- Senior drains epic sub-tasks until exhausted.
- Junior-routine drains routine-fix queue continuously in between.
- Knowledge-curate fires once if 7d stale; admin-replies once if 24h stale.
- The 15-sessions-for-1-commit pattern from 2026-05-21 does not recur (blocker-elevation from 2b + epic context from 2a + routine drumbeat from 3b + planning override cap from 3c).

## Out of scope for this phase

- Anthropic Agent SDK / Managed Agents integration.
- Web tools (USDA / Anthropic web_search) for Drift chat.
- Voice-transcript editable input.
- Multi-agent orchestrator (concurrent senior sessions) — Cognition's *Don't Build Multi-Agents* warning still applies; the new pieces all run serial inside one session.
