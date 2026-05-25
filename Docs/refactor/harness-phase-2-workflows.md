# Harness Phase 2 — Workflows Layer

**Status:** Draft 2026-05-25. Builds on the approved 2026-05-18 rewrite (archived at `Docs/archive/refactor-2026-05-19/harness-rewrite-2026-05-18.md`).
**Tracking:** Epic issue TBD (this doc is the spec for it).
**Authorship:** Drafted from one human-shepherded session 2026-05-21 to 2026-05-25 where autopilot stalled despite the new harness — 15 senior sessions, 1 sprint commit, queue full of bugs the senior couldn't pick up because of an unrelated test-gate block.

---

## What's already done (the 2026-05-18 rewrite)

The prior rewrite shipped:

- Done-When contracts per issue (XML), enforced by `require-done-when.sh` hook
- Verifier-with-thresholds via `qa-tester` + `debate-moderator`
- Abandon-don't-compact discipline (never WIP-commit to main)
- MCP tool layer (`drift-mcp`) with typed `sprint.*` / `issues.*` / `state.*` / `verify.*` groups
- Stuck-detector watchdog hook (progress-based liveness, not timeout)
- Sub-agents as read-only investigators returning structured verdicts

That's already most of Anthropic's "Building effective agents" workflows applied: **prompt chaining** (plan→implement→verify), **routing** (planning routes by label to senior/junior/design), **evaluator** (qa-tester gates the commit).

## What's still missing — observed in real autopilot stalls

Three gaps in the current harness, named by the workflow pattern they correspond to:

### 1. Blocker-elevation (a missing routing primitive)

**Observed:** Sat 2026-05-21 to Sun 2026-05-22, the queue head was `#823 FM-driven free-text food parsing`. The senior repeatedly tried `#823`, hit pre-commit hook failures because three iOS tests (`weightRapidLoss`, `weightTrendFallbackUsesTwoMostRecent`, `aiToolAgentExecuteToolWithUnknownTool`) were failing on main due to hardcoded historical dates aging out. The fix was filed as `#839` (low in the queue). The senior never picked up `#839` because it wasn't top-of-queue; instead it abandoned `#823` 15 times in ~7 hours, producing 1 commit (the daily exec briefing, which is unrelated).

**Pattern this maps to:** Routing — but specifically *blocker-aware* routing. The router needs a "what's blocking my next claim?" pre-check.

**Fix:** Before the senior claims task `N`, run a tier-0 sanity ("can I commit a no-op right now?"). If the gate fails AND the queue contains any issue labeled `unblocks-gate` OR with title pattern matching `fix.*tests?`, re-route to that issue first. This is implemented as a new `sprint_claim` decision branch, not a new top-level workflow.

### 2. Epic / spec-driven queue (orchestrator-workers, but lite)

**Observed:** This week the user accumulated ~15 V7-polish bugs (visibility, refresh, lifecycle, density, tone) spread across 7 commits over 3 days. Each commit was the senior re-discovering the same project context. Senior sessions don't *know* they're working a V7 polish arc; they just see the next sprint-task.

**Pattern this maps to:** Orchestrator-workers, lite. One epic issue contains the full arc spec. Sub-tasks (also issues) reference the epic via `epic:#N`. Senior reads the epic body first to set context, then claims a sub-task. Sub-tasks can be ordered with `blocks:`/`blocked-by:` so the queue self-orders.

**Fix:** New `epic` label. Epic issue bodies include:

```xml
<epic id="V7-polish" status="in-progress">
  <goal>One paragraph naming the user-visible outcome.</goal>
  <subtasks>
    <task issue="#NNN" status="done" blocks="#MMM"/>
    <task issue="#NNN" status="open"/>
  </subtasks>
  <done_when>Epic-level Done-When; aggregates per-sub-task verdicts.</done_when>
</epic>
```

`sprint-service.sh next` learns one new behavior: when an epic issue is open, sub-tasks of *that* epic that have no open `blocks` siblings are ranked above bare sprint-tasks. Senior's skill prompt gains one step: "if claimed task has `epic:#N` reference, fetch and read epic body — its `<goal>` becomes part of your context."

This is the smallest change that solves the "senior keeps re-discovering project context" problem.

### 3. Visual evaluator-optimizer (the missing UI feedback loop)

**Observed:** This session, the user reported ~12 visibility / contrast / density bugs by taking screenshots and sending them to me. The harness has no equivalent for autopilot — qa-tester gates *code* against Done-When criteria, not *visual output* against a design intent.

**Pattern this maps to:** Evaluator-optimizer — but with a vision model evaluator instead of a code-grading one.

**Fix:** New `/ui-evaluator` skill spawned after any commit touching `Drift/Views/`. The skill:
1. Reads the affected screens from a manifest (e.g., `food-tab → Food.swift, FoodDiary.swift`).
2. Spawns `mobile-mcp` against the staged simulator build.
3. Captures screenshots of each affected screen.
4. Feeds screenshots + the Done-When `<visual_criteria>` block to a vision model (Claude Sonnet via `messages.create` with image inputs).
5. Vision model returns `<visual_verdict decision="PASS|REJECT">` with per-criterion scores.
6. On REJECT, files a refinement sub-task under the epic.

`<visual_criteria>` schema:

```xml
<visual_criteria>
  <criterion id="contrast" weight="3">All small text (≤13pt) reads at ≥4.5:1 contrast against its background.</criterion>
  <criterion id="density" weight="2">Each meal-row in the food diary fits ≥6 rows in the visible viewport.</criterion>
  <criterion id="brand-discipline" weight="2">Coral (Theme.accent) used only on primary CTAs, brand moments, and selected user-bubbles — not on every "+" icon or chip.</criterion>
</visual_criteria>
```

This is the highest-value addition because it converts the user's manual screenshot-by-screenshot QA loop into automation. The lint test `HardcodedWhiteTextTests` added in commit `f061fde0` is the static half of this — the vision-model evaluator is the runtime half.

## What this is NOT

- **Not a multi-agent rewrite.** Cognition's *Don't Build Multi-Agents* warning still applies. The new pieces (blocker-elevator, epic router, ui-evaluator) all run as serial steps inside one senior session, not as concurrent agents.
- **Not new top-level skills.** Blocker-elevation is a `sprint_claim` change. Epic awareness is a new step in the existing `senior` skill. The UI evaluator is one new sub-skill called from `senior` post-commit.
- **Not a queue rewrite.** Sprint-state.json schema is unchanged. Epic awareness is computed on read via jq filter over the existing `labels` field.

## Implementation phases (in order)

| Phase | Scope | LOC | Why first |
|---|---|---|---|
| 2a | **Epic label + senior reads epic body** | ~80 LOC in sprint-service.sh + ~30 LOC in senior SKILL.md | Smallest scope, biggest "stop re-discovering context" payoff. Convert this week's bug sweep into an epic to validate. |
| 2b | **Blocker-elevator in `sprint_claim`** | ~50 LOC in sprint-service.sh + 1 hook | Stops the kind of 15-sessions-for-1-commit stall observed 2026-05-21. |
| 2c | **`/ui-evaluator` skill + `<visual_criteria>` schema** | ~150 LOC new skill + ~50 LOC mobile-mcp wiring + 1 cron hook | Highest impact, most work. The screenshot-driven user QA loop becomes automated. |

Phase 2a ships in this session (see "Step 1 implementation" below). 2b is a 2-hour follow-up. 2c is a 1-day follow-up.

## Step 1 implementation (this session)

This session implements 2a only:

1. New issue label `epic` exists in the GitHub repo.
2. `sprint-service.sh refresh` parses `epic` issues + extracts the `<epic>` XML block into the state file (epics are NOT claimable; they're context).
3. `sprint-service.sh next-epic <subtask-issue-N>` returns the parent epic number if the issue is referenced by any open epic's sub-tasks.
4. Senior SKILL.md step 4.5 (between "claim" and "read Done-When"): "If the claimed task is part of an open epic, read the epic body. Its `<goal>` is added to your working context."
5. Convert the bug sweep this week into the first epic issue. Sub-tasks are the issues already filed (#838 iCloud Drive, #839 broken iOS tests, #842 infrequent-logger handling, plus any new ones from the active autopilot/user work).

After step 1 ships, the senior should still pick the next sub-task from the queue, but it now reads the epic context first. That's the simplest possible validation that the pattern works.

## References

- Anthropic, *Building effective agents* (Dec 2024) — workflow patterns vocabulary.
- The approved 2026-05-18 rewrite, archived at `Docs/archive/refactor-2026-05-19/harness-rewrite-2026-05-18.md`.
- Cognition, *Don't Build Multi-Agents* — guards against over-engineering this layer.
- The 2026-05-21 to 2026-05-25 autopilot stall logs in `~/drift-state/watchdog-*.log` (the lived motivation for blocker-elevation).
