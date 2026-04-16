# Product Review — Cycle 5228 (2026-04-16)

## Executive Summary
Since Review #45 (cycle 4805): LLM-first lab report parsing shipped (#151 — two-sprint deferred, now done), food DB grew by 100 foods (2,067→2,167), macOS LLM eval harness launched with full E2E pipeline eval, IntentClassifier prompt tuning resolved CoT false-positives and routing gaps, and Smart Units cross-interface consistency closed 4 bugs. Sprint is now planned around eval expansion (#158/#160), voice input hardening (#159), and exercise visual enrichment (#66).

## Scorecard

| Metric | Value | Trend |
|--------|-------|-------|
| Build | 128 | +2 (from 126) |
| Tests | 1,564 | stable |
| Food DB | 2,167 | +100 |
| AI Tools | 20 | — |
| Gold Set | 100% | stable |
| P0 Bugs Fixed | 2 | CoT false-positive, TypingDotsView timer leak |
| Sprint Velocity | 7/7 | all tasks closed |

## What Shipped Since Last Review (cycles 4805→5228)

- **LLM-first lab report parsing (#151)** — Gemma 4 as primary extractor (chunked ~500 tokens/chunk), regex as validation layer, confidence scoring, report date extraction with fallback, AI-parsed badge in biomarker history, accuracy warning banner. SmolLM devices fall back to existing regex-only path. Tests required and written.
- **macOS LLM eval harness** — New `DriftLLMEvalMacOS` target wired and building. Full E2E pipeline eval (InputNormalizer → LLM classify → MockToolExecutor) gives integration-level regression gate. LLM eval quality loop formalized as 50% permanent sprint task.
- **IntentClassifier prompt improvements (#158/#160/#161)** — Prompt example ordering fixed (front-loaded for Gemma 4 attention), greedy decoding enforced for routing, CoT false-positive on "today"-containing workout queries fixed, duplicate example removed. E2E pipeline eval added as second regression gate alongside FoodLoggingGoldSetTests.
- **Smart Units cross-interface consistency (#156)** — 4 bugs fixed (Butter Chicken/tbsp, Chicken Parmesan/tbsp, Vindaloo/serving, Chicken Stock/serving). 5 regression tests added. All 3 interfaces verified consistent.
- **Food DB +100 foods (2,067→2,167)** — Five enrichment batches: Goan/Maharashtrian seafood, regional Indian staples, South Indian breakfasts, protein bars/supplements, international dishes (Filipino, Ethiopian, Turkish, Vietnamese).
- **Exercise enrichment research (#140)** — Design doc at `Docs/designs/133-exercise-enrichment.md`: GO decision, free-exercise-db (MIT) for GIFs, YouTube manual curation for top 50.
- **TypingDotsView timer resource leak** — Timer now invalidated on `onDisappear`. Silent memory leak fixed.
- **TestFlight build 128** — Published.

## Competitive Analysis

- **MyFitnessPal:** Cal AI acquisition closed (20M food DB). ChatGPT Health live in Premium+. Photo-to-log, voice log behind paywall ($20/mo Premium+). Our free on-device AI remains a genuine differentiator.
- **Boostcamp:** Exercise GIFs/video content still gold standard. No AI. Our exercise text-only gap remains the starkest visual comparison point.
- **Whoop:** AI Coach now has conversation memory and contextual nudges. Behavior Trends (habits → Recovery correlation) is the cross-domain pattern we should extend. Our on-device privacy moat still differentiates.
- **Strong:** Clean minimal UX, no AI. Privacy-focused. Positioning overlap. MacroFactor Workouts app (Jan 2026) is now the stronger competitive threat in exercise logging.
- **MacroFactor:** Workouts app added AI recipe photo logging and auto-progression at $72/yr. Cloud-based — our free + private story is the counter.

## Product Designer Assessment

*Speaking as the Product Designer persona (read Docs/personas/product-designer.md):*

### What's Working
- **Lab reports LLM finally shipped.** After two deferred sprints, it's in. Users with bloodwork can now see AI-extracted values with confidence scores. The accuracy banner sets the right expectations. This is the feature most likely to impress health-focused testers and position Drift as a whole-health tracker, not just a food/fitness app.
- **LLM eval harness is real now.** A macOS-buildable eval target with E2E pipeline coverage means every AI change has a safety net. The gold set at 100% post all recent prompt changes shows the discipline is working.
- **Food DB at 2,167 with strong Indian + regional coverage.** No competitor matches this on-device without cloud lookup. It's a quiet but real competitive advantage for the target user.

### What Concerns Me
- **Exercise is still text-only.** Research is done, design doc is approved — but we've had an approved plan for exercise visuals for 3+ reviews and nothing shipped. Boostcamp users see GIFs. Drift users see text. This is the most glaring visual gap vs. any competitor.
- **Voice input bugs unresolved.** Build 128 shipped with #159 still in the Ready column. Voice is a differentiator on paper, but unresolved bugs undermine trust with the single biggest input UX improvement we shipped.
- **No new UI surface since dashboard redesign.** iOS widgets were Phase 4. The app's visual experience hasn't changed in several reviews. Users on TestFlight who were impressed by the theme overhaul are now seeing a static product. Need a visible UI win this sprint.

### My Recommendation
Ship exercise visual enrichment (#66) this sprint — the design doc is done, the asset source is decided (free-exercise-db MIT), and every cycle it isn't shipped is a cycle the "text-only exercises" comparison to Boostcamp persists. Pair with voice input hardening (#159) since voice is the input differentiator. Eval work (#158/#160) is always required but should be the background rhythm, not the headline.

## Principal Engineer Assessment

*Speaking as the Principal Engineer persona (read Docs/personas/principal-engineer.md):*

### Technical Health
The AI pipeline is the most mature it's ever been: 6-stage architecture, E2E macOS eval harness, two regression gates (FoodLoggingGoldSetTests + PipelineE2EEval), 100% gold set. Lab reports LLM implementation followed the design doc's tests-first discipline. `DriftLLMEvalMacOS` as a separate target is the right architecture — eval runs on macOS without simulator, faster CI.

### Technical Debt
- **`DriftLLMEvalMacOS` requires models at `~/drift-state/models/`** — not portable across machines, not CI-able. The eval harness is valuable but fragile: a missing model silently skips all LLM eval. Consider a build flag that fails fast if models are absent rather than silently passing.
- **Food DB at 2,167 manual entries is hitting diminishing returns.** 100 foods in one sprint is impressive, but USDA API integration (already designed in roadmap) would provide verified data at scale without manual effort. Manual enrichment has an obvious upper bound; USDA does not.
- **Coverage: new code from #151 (LabReportOCR LLM path) needs verification.** The design doc required tests — confirm they cover the SmolLM fallback path explicitly, as that's the code path most likely to break silently.

### My Recommendation
Run `./scripts/coverage-check.sh` early in the next sprint to confirm #151's coverage is above threshold before layering more features on top. Start exercise enrichment (#66) with an on-demand asset download approach — bundling 960 GIFs will bloat the app. Design the download layer before writing the UI.

## The Debate

**Designer:** Exercise visual enrichment has been "approved and pending implementation" for three reviews. The pattern is clear from push notifications: when something keeps slipping, make it the only P0 with no competing priorities. That's what this sprint needs to be for exercise GIFs.

**Engineer:** Agreed on priority, with one structural note: free-exercise-db has GIFs for ~800 exercises — we can't bundle those at launch. The implementation needs an on-demand download layer (download on first exercise view, cache locally) before any UI can ship. That's a day of infrastructure before the first GIF appears. Account for it in sprint sizing.

**Designer:** Fine — that's scope definition, not a reason to defer. Infrastructure day one, GIF display day two, top-50 curated by end of sprint. The user-visible outcome (exercises with visuals) is achievable this sprint if we don't let infra become a blocking conversation.

**Engineer:** One more item: #159 (voice bugs) should be tested on device before this sprint closes, not left in Ready. Voice is a shipped feature with known outstanding bugs. Every build that goes to TestFlight with unfixed voice bugs is a trust issue for the testers using it daily.

**Agreed Direction:** This sprint: eval (#158/#160) as background rhythm, voice bugs (#159) fixed on device before next TestFlight, exercise visual enrichment (#66) with on-demand download architecture — infra first, then GIF display for top 50. No new P1s added until these three close.

## Decisions for Human

1. **Exercise asset strategy** — Should we bundle a small set (top 50 GIFs, ~50MB) at install time, or always on-demand download? Bundling is simpler and works offline; on-demand keeps app size down but requires network on first exercise view. Which tradeoff fits our privacy-first, local-first identity better?

2. **USDA API key** — `DEMO_KEY` is rate-limited and was flagged in Review #41. Food DB is at 2,167 manual entries — the right investment now is a registered USDA API key, not more manual enrichment. Should we register a key this sprint?

3. **Voice input: ship or scope down?** — #159 has been in Ready since the sprint started. If device testing reveals bugs that need >1 day to fix, should we scope voice to "fix the known bugs only" and not attempt new voice features, or is voice quality a P0 blocker for the next TestFlight?

---
*Comment on any line for strategic feedback. @ashish-sadh @nimisha-26*
