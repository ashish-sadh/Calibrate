# Product Review — Cycle 5374 (2026-04-16) · PR #47

## Executive Summary

Since Review #46 (cycle 5228): exercise visual enrichment shipped (#66 — images + YouTube tutorial links per exercise, closing the Boostcamp gap), LLM eval gold set expanded +11 cases with HRV and sleep-continuation routing hardened, and food DB grew to 2,107 with Maharashtrian/Goan/seafood coverage. Sprint planning for cycle 5374 adds two new structural P0 tickets: per-component isolated gold sets (#161) and AIChatView ViewModel extraction (#162), directly addressing the human feedback that regressions accumulate because individual pipeline stages lack their own test suites.

## Scorecard

| Metric | Value | Trend |
|--------|-------|-------|
| Build | 130 | +2 (from 128) |
| Tests | 1,564 | stable |
| Food DB | 2,107 | +40 |
| AI Tools | 20 | — |
| Gold Set (FoodLogging) | 100% | stable |
| Gold Set (IntentRouting) | 100% | +11 cases |
| P0 Bugs Fixed | 2 | HRV routing, sleep-continuation routing |
| Sprint Velocity | 5/5 | all tasks closed |

## What Shipped Since Last Review (cycles 5228→5374)

- **Exercise visual enrichment (#66)** — Every exercise now shows an image and a curated YouTube tutorial link. On-demand architecture (not bundled). Closes the most glaring visual gap vs Boostcamp after 3 review cycles of deferral. Build 130 ships it.
- **LLM eval gold set +11 cases** — IntentRoutingEval expanded; HRV query routing fixed (was mis-routing to food domain), sleep-continuation queries now correctly resolve in context without re-triggering classifier.
- **Food DB +40 foods (2,067→2,107)** — Two batches: Maharashtrian/Goan seafood (Surmai, Rawas, Bangda, Bombil, Bombay Duck, Koliwada Prawn, Malvani Chicken, Kombdi Vade, Saoji Chicken, Tisrya Masala, Masala Crab) and regional staples (Ragi Mudde, Sol Kadi, Tindora, Gavar, Vazhakkai, Amboli, Karanji, Undi, Pathande). Strong South Indian and coastal coverage.
- **Smart Units cross-interface consistency (#156)** — 4 serving-unit bugs fixed (Butter Chicken, Chicken Parmesan, Vindaloo, Chicken Stock). 5 regression tests added. All 3 food entry interfaces verified consistent.
- **Test coverage audit (#153)** — All files verified above thresholds (80% logic, 50% services). No regressions.
- **TestFlight build 130** — Published with exercise visuals.

## Competitive Analysis

- **MyFitnessPal:** Cal AI integration (20M food DB) now live in Premium+. Photo-to-log and voice log are $20/mo features. Free tier is increasingly limited. Our free on-device AI is a direct response.
- **Boostcamp:** Still the exercise-content gold standard with GIFs and detailed muscle engagement per exercise. Our YouTube tutorial links are a strong first step, but animated muscle diagrams remain a gap.
- **Whoop:** AI Coach conversation memory released. Behavior Trends now auto-surface cross-domain patterns. On-device privacy moat remains our differentiator.
- **Strong:** Minimal, no AI. Overlap with our exercise logging UX. No meaningful changes reported.
- **MacroFactor:** Workouts app added auto-progression AI. Competitive in exercise intelligence. Cloud-based — our local story holds.

## Product Designer Assessment

*Speaking as the Product Designer persona:*

### What's Working
- **Exercise visuals finally shipped.** Three product review cycles of "top recommendation" and we finally have images + YouTube links per exercise. This was the top concern from every prior review — it's resolved. Users comparing Drift to Boostcamp will now see a real fitness app, not a text list.
- **Eval discipline is real.** 100% on both gold sets, +11 new routing cases, two regressions proactively fixed (HRV, sleep-continuation). The harness is working as an immune system.
- **Indian food coverage is legitimate.** 2,107 foods with Maharashtrian, Goan, Konkani, South Indian coastal depth. No competitor on-device matches this for this audience.

### What Concerns Me
- **Per-component testing is still a sprint ticket, not reality.** Human feedback was explicit: each pipeline stage needs its own gold set. #161 is in Ready — it must ship this sprint, not slip again. We keep discovering routing regressions *after* they reach users.
- **Voice input (#159) is the only shipped feature still in Ready column.** Every TestFlight build that ships without resolving voice bugs means users testing voice hit the same issue repeatedly. This erodes trust in the input modality we're betting on.
- **No UI wins visible to a casual tester.** Exercise visuals are great, but a user who hasn't loaded an exercise won't see the change. No dashboard update, no chat UI improvement, no new visual surface since the theme overhaul. Casual TestFlight testers need something to notice.

### My Recommendation
Deliver #161 (per-component gold sets) and #159 (voice bugs) as non-negotiable this sprint. Everything else is secondary. Per-component testing is infrastructure for every future AI improvement — skipping it means every eval is testing the full pipeline at once and regressions will keep sneaking through individual stages.

## Principal Engineer Assessment

*Speaking as the Principal Engineer persona:*

### Technical Health
Architecture is stable. The eval harness is the healthiest it's been — two regression gates, isolated macOS target, 100% baseline. Exercise visual enrichment shipped with on-demand architecture (correct call: no GIF bundle bloat). Food DB at 2,107 with reliable SmartUnits coverage. AIChatView.sendMessage at 491 lines is the biggest structural liability in the codebase right now.

### Technical Debt
- **AIChatView.sendMessage (491 lines)** is the highest-priority refactor. It's the core of the product and it's untestable as a monolith. Every multi-turn improvement, every state machine change, every new routing path has to be jammed into this function. #162 (ViewModel extraction) is the right move — it should unlock coverage for the most critical path in the app.
- **Per-component gold sets are absent** for IntentClassifier, FoodSearch, and SmartUnits. FoodLoggingGoldSetTests covers the happy path but not individual stages. A regression in IntentClassifier alone won't be caught until it shows up in a full pipeline run. #161 closes this.
- **Food DB manual enrichment is hitting a ceiling.** 2,107 is impressive for manual work, but each batch yields diminishing returns. The USDA API integration (in roadmap, already designed) is the correct investment. We should stop adding manual batches and start the USDA integration sprint.

### My Recommendation
This sprint must close #161 (per-component gold sets) before any other AI work. It's a precondition for trusting future eval results. Then #162 (AIChatView ViewModel) before any new multi-turn features — you can't build reliably on a 491-line untestable function. Voice bugs (#159) on device.

## The Debate

**Designer:** Three things on the table: per-component gold sets (#161), AIChatView refactor (#162), voice bugs (#159). Users feel the voice bugs and the AI regressions — the other one (#162) is infrastructure. From a user lens, fix #159 and #161 first.

**Engineer:** #162 isn't optional infrastructure — it's a precondition for #161 being meaningful. If we write per-component gold sets for IntentClassifier while sendMessage is still a 491-line monolith, we'll test the classifier in isolation but the integration path remains untestable. The right order is: #162 → #161 → #159. But if scope forces a choice, #161 and #159 with #162 deferred is acceptable — just don't add more multi-turn features on top of the monolith.

**Designer:** Agreed. I'll accept #162 as a sprint P1 (not P0) as long as it doesn't block #161 and #159 shipping. If it turns out to be a larger refactor than one cycle, defer it — don't let it block the two things users feel.

**Engineer:** Reasonable. Final order: #161 (gold sets, no dep on #162, do first), #159 (voice, device test), #162 (ViewModel extraction, time-box to one cycle). Food DB: stop manual batches, begin USDA API sprint.

**Agreed Direction:** Ship per-component gold sets (#161) and fix voice input bugs (#159) as P0 this sprint. #162 (AIChatView ViewModel) is P1 — attempt this sprint, defer if overscoped. Pause manual food DB batches; begin USDA API integration planning.

## Decisions for Human

1. **USDA API integration** — We've deferred this for 3+ reviews while continuing manual food DB enrichment. 2,107 foods is respectable but far from MFP's 20M. The roadmap has this designed. Should we make USDA integration the next P1 food sprint task and stop adding manual batches?

2. **AIChatView ViewModel extraction (#162)** — This is a refactor with no user-visible change. It unblocks testability of the most critical code path. Should we commit a sprint to it this cycle, or treat it as a background "boy scout" task (do it incrementally whenever touching the file)?

3. **Voice input scope** — #159 has been in Ready for 2 sprints. If device testing reveals the remaining voice bugs need more than a day to fix, should we ship a "voice disabled" toggle in settings until it's solid, or keep shipping with known issues?

---
*Comment on any line for strategic feedback. @ashish-sadh @nimisha-26*
