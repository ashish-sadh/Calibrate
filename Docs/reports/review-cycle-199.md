# Product Review — Cycle 199 (2026-04-12)

Last review: Cycle 170 | Cycles since: 29 | Phase: 3c (Polish & Depth)

---

## What Happened Since Last Review (Cycles 170–199)

### Major Completions
- **DDD routing complete** — 83+ direct DB calls eliminated from 18 views, routed through 7 domain services. Architecture is clean.
- **AIToolAgent test coverage: 0% → 20%** — 16 unit tests added. Critical path now has baseline coverage.
- **TestFlight build 103** published successfully.
- **Autopilot consolidation** — Merged separate code-improvement and feature loops into single Drift Autopilot program with GitHub PR-based reports.
- **Product review process hardened** — Reviews never block on human feedback; issue-check hook runs every commit.

### Metrics
| Metric | At Cycle 170 | Now | Delta |
|--------|-------------|-----|-------|
| Tests | 729+ | 743+ | +14 |
| Coverage (overall) | ~20% | 23.17% | +3.17% |
| Foods in DB | ~1030 | 1041 | +11 |
| TestFlight build | ~100 | 103 | +3 |
| Open bugs | 0 | 0 | 0 |
| DDD violations | 83+ DB calls in views | 0 (complete) | -83 |

### What Didn't Ship
- State machine refactor (still blocked by coverage gaps)
- UI theme overhaul (no visual changes in 29 cycles)
- Food DB enrichment was minimal (+11 foods)
- No new user-facing AI features

---

## Product Designer Assessment

_Speaking as: Product Designer (2yr each at MFP, Whoop, MacroFactor, Strong, Boostcamp)_

### Competitive Landscape Update (April 2026)

| App | What's New |
|-----|-----------|
| **MyFitnessPal** | Acquired Cal AI (March 2026) — photo calorie scanning now integrated. ChatGPT integration for nutrition Q&A. Full app redesign in progress. |
| **Boostcamp** | Bodyweight tracker tied to lifting analytics. Muscle engagement visualization per program. AI program creation + offline mode standard. |
| **Whoop** | AI Strength Trainer — describe workout in text, parses into structured plan. Behavior Trends after 5+ habit logs surface Recovery correlations. Jet lag AI coaching. |
| **Strong** | Staying minimal — templates search, measurement widgets, exercise renaming. No AI. $99.99 lifetime. |
| **MacroFactor** | Expenditure modifiers with predictive goal adjustment. Apple Watch support. Separate Workouts app bundled at $89.99/yr. |

### Strengths
1. **AI chat remains our unique moat.** No competitor does on-device conversational tracking. MFP's ChatGPT is cloud-based, can't log or cross-reference user data. Whoop's AI Strength Trainer is interesting but cloud-only.
2. **Cross-domain single app** — food + weight + exercise + sleep + supplements + glucose + biomarkers + body comp + cycle tracking. Nobody else covers all of these.
3. **Privacy positioning strengthens** as competitors move to cloud AI. "Everything stays on your phone" is increasingly rare and valuable.
4. **Architecture is now clean** — DDD completion means feature velocity should improve significantly.

### Gaps & Concerns
1. **29 cycles of infrastructure, zero user-visible improvements.** The DDD work was necessary but users don't see cleaner architecture. We shipped nothing that makes the app feel better to use. This is the biggest concern.
2. **Photo food logging is now table stakes.** MFP acquiring Cal AI signals this. We're behind.
3. **Food DB is still tiny** — 1041 vs 14M+. Only +11 foods in 29 cycles.
4. **UI is unchanged** — Theme overhaul has been "Now" for months. No visual progress.
5. **Exercise presentation** is still text-only. Boostcamp's muscle viz is a clear gap.
6. **Behavior insights** stuck at 3 hardcoded cards. Whoop's behavior-outcome correlations are more sophisticated.

### Proposal: Pivot to User-Facing Work
The infrastructure era is over. DDD is done, autopilot is consolidated, hooks are hardened. **The next 20 cycles must be 80% user-facing features and visual polish, 20% tests/infrastructure.**

Priority order:
1. **UI theme overhaul** — One bold cycle to transform the look across all views
2. **Coverage sprint** — Get AIToolAgent to 50% to unblock state machine refactor
3. **State machine refactor** — Proper conversation flow, foundation for multi-turn
4. **Food DB enrichment push** — Target 200+ new foods (Indian, restaurant, branded)
5. **Behavior insights v2** — Add 4th insight (sleep vs recovery), expand to 30 days

---

## Principal Engineer Response

_Speaking as: Principal Engineer (10yr each at Amazon, Google)_

### What Went Well
- **DDD completion is a genuine milestone.** 83 direct DB calls eliminated. The codebase is now properly layered. This was the right call — it was getting worse every cycle we delayed.
- **AIToolAgent testing went from 0% to 20%.** Still below threshold but no longer flying blind.
- **Zero open bugs.** Clean issue tracker for the first time in a while.
- **Autopilot consolidation** eliminated the split-brain between improvement and feature loops.

### Technical Concerns
1. **Overall coverage at 23.17% is still critically low.** AIToolAgent at 20% (target 50%), IntentClassifier at 36% (target 50%), AIRuleEngine at 25% (target 50%), FoodService at 30% (target 50%). This has been flagged for 6+ consecutive reviews.
2. **State machine refactor is overdue** — scattered pendingMealName/pendingWorkout state vars are a bug factory. But I agree with the blocker: we need AIToolAgent at 50% before touching the orchestrator.
3. **Context window (2048 tokens)** is a hard constraint on multi-turn quality. Not proposing we fix it now, but it limits how good multi-turn can get.

### Response to Designer's Proposal
I agree with the 80/20 split. Pushback on specifics:

- **UI theme overhaul: YES** — but scope it to one cycle. Pick a direction, commit, don't iterate for 5 cycles. Theme churn is worse than no theme.
- **Coverage sprint first, then state machine: YES** — correct sequencing. AIToolAgent to 50% is ~15 more test methods. IntentClassifier needs ~10. Do this in 2-3 cycles.
- **Food DB: careful** — Adding 200+ foods manually is tedious and error-prone. Instead, focus on the 50 most-commonly-searched-for foods that return no results. Quality over quantity.
- **Photo food logging: NOT YET** — On-device ML accuracy for Indian/mixed dishes is poor. Voice input via iOS SpeechRecognizer is higher ROI and lower risk. Don't chase MFP's cloud approach.
- **Behavior insights: YES** — Low-risk, high-visibility. Sleep vs recovery is just a query + card.

### Issue Triage
- No open GitHub issues. Clean slate.

---

## Agreed Direction — Next 20 Cycles (199–219)

### Sprint Plan

| Priority | Item | Cycles | Owner |
|----------|------|--------|-------|
| P0 | **Coverage recovery** — AIToolAgent to 50%, IntentClassifier to 50%, AIRuleEngine to 50% | 3 | Engineer |
| P0 | **UI theme overhaul** — Bold visual refresh across ALL views in one cycle | 1 | Designer |
| P1 | **State machine refactor** — Replace scattered state vars with proper FSM | 3 | Engineer |
| P1 | **Food DB enrichment** — 50 most-wanted foods, fix bad serving sizes | 2 | Both |
| P1 | **Dashboard redesign** — Better hierarchy, macro rings, scannable | 2 | Designer |
| P2 | **Behavior insights v2** — 4th insight (sleep/recovery), 30-day window | 1 | Engineer |
| P2 | **Chat UI polish** — Message bubbles, tool execution feedback | 2 | Designer |
| P2 | **Multi-turn reliability** — 3-turn meal logging, workout building tests | 2 | Engineer |
| Ongoing | **Boy scout rule** — Clean what you touch, tests for new code | All | Both |
| Ongoing | **Food DB quality** — Fix wrong macros, bad serving sizes as encountered | All | Both |

### Roadmap Changes
- Move **Coverage recovery** from "Now" note to explicit P0 sprint item — it's been "Now" for 6 reviews without resolution
- Add **Voice input research** to "Next" in AI Chat (higher ROI than photo)
- Mark DDD routing as DONE in Quality section
- Add **Whoop AI Strength Trainer** as competitive benchmark
- Promote **Dashboard redesign** to "Now" alongside theme overhaul

### What We're NOT Doing (Scope Control)
- Photo food logging — deferred to Phase 4 (on-device accuracy too poor for Indian food)
- Voice input — research only, not building yet
- Apple Watch — Phase 4+
- Fine-tuned models — Phase 5
- Workout split builder — after state machine refactor

---

## Open Questions

1. **Should we increase the context window from 2048?** More context = better multi-turn, but memory impact unknown. Needs profiling on 6GB devices.
2. **Is the tiered pipeline still the right architecture?** With Gemma 4 getting better, should more queries go directly to LLM rather than through rules?
3. **When do we add voice input?** iOS SpeechRecognizer is built-in, relatively low effort. Could be a Phase 3c item if we finish early.

---

_Comment on any line to provide feedback. Next review: ~Cycle 219._
_This review will be incorporated into the next sprint planning._
