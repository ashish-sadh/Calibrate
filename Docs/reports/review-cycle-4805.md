# Product Review — Cycle 4805 (2026-04-16)

## Executive Summary
Since Review #44 (cycle 4666): four P0 AI chat regressions resolved, Smart Units audit saturated at ~65 intentional "serving" foods, food DB grew to 2,067 (+20 foods), and gold set holds at 100%. Sprint planning now shifts focus to LLM-first lab report parsing (#151) as the highest-value unstarted P1, with Smart Units entering a cross-interface consistency pass.

## Scorecard

| Metric | Value | Trend |
|--------|-------|-------|
| Build | 126 | — |
| Tests | 1,564 | stable (since last review) |
| Food DB | 2,067 | +20 |
| AI Tools | 20 | — |
| Gold Set | 100% | stable |
| P0 Bugs Fixed | 4 | #147 #148 #149 #150 |
| Sprint Velocity | 6/6 | all P0+P1 tasks closed |

## What Shipped Since Last Review (cycles 4666→4805)

- **4 P0 AI chat bugs fixed** — "daily summary" was being logged as food, "weekly summary" broken, "log 2 eggs" matched egg benedict instead of eggs, broad AI chat regression from StaticOverrides changes. All fixed with regression tests.
- **Smart Units audit complete** — ~65 foods remain at "serving" (intentional: nuts, canned goods). All other categories now show natural units (piece, cup, tbsp, scoop, bowl, strip, etc.). Consistent across food search.
- **+20 foods added** — Bedmi Puri, Sooji Halwa, Anda Paratha, Churma Ladoo, Rajma Rice, Poha Cutlet, Ghevar, Imarti, Green Moong Dal, Sheer Khurma, Tawa Pulao, Methi Matar Malai, Oats Upma, Navratan Korma, Kathal Ki Sabzi, Lobia, Aloo Baingan, MuscleBlaze Biozyme Whey, Ghost Whey Protein, Masala Chai Powder.
- **Gold set verified** — 55-query eval at 100% after P0 fixes. AI chat quality baseline confirmed.

## Competitive Analysis

- **MyFitnessPal:** Cal AI acquisition (15M downloads, $30M ARR) closed. MFP now claims 20M food DB. ChatGPT Health integration live. Cloud AI photo logging is becoming table stakes — our on-device privacy moat matters here.
- **Boostcamp:** Exercise video/GIF content remains gold standard. We have 960 exercises but text-only — this is the clearest visual gap vs competition.
- **Whoop:** Behavior Insights connecting habits to Recovery scores is compelling. Our insight cards cover similar ground but with limited cross-domain depth.
- **Strong:** Clean minimal workout logging UX. No AI. Privacy-focused positioning overlaps with ours.
- **MacroFactor:** Launched Workouts app (Jan 2026) adding personalized exercise progression. Expanding from nutrition into exercise — direct competition territory.

## Product Designer Assessment

*Speaking as the Product Designer persona:*

### What's Working
- **Smart Units is a real UX win.** Users who log "2 eggs" or "a cup of dal" now see natural units in confirmations — no mental math. This was the #1 complaint and it's largely addressed.
- **AI chat stability.** 4 P0 bugs were filed and closed in one sprint. The gold set at 100% means the regression gate is working as designed. Users get a reliable experience.
- **Food DB breadth.** 2,067 foods with strong Indian coverage is a genuine differentiator for the target user base.

### What Concerns Me
- **Lab reports UI is stale.** #151 has been in the sprint board for two sprints. It's the only deep-health feature users see in Labs. Every cycle it isn't shipped, it signals that Drift is a food/fitness app, not a whole-health tracker.
- **Exercise is text-only.** 960 exercises with zero visual presentation. Every competitor has images or GIFs. A user who wants to know "what does a Bulgarian split squat look like?" leaves to Google.
- **No new user-visible features in this sprint.** Bug fixes and internal quality are necessary, but back-to-back maintenance sprints slow perceived momentum.

### My Recommendation
Ship #151 (lab reports LLM) this sprint — it's been deferred twice, has an approved design doc, and is the feature most likely to impress health-focused testers. Pair with exercise enrichment research (#140) to unblock the visual gap. Smart Units cross-interface check (#156) is the right scope — don't over-rotate on it.

## Principal Engineer Assessment

*Speaking as the Principal Engineer persona:*

### Technical Health
The AI pipeline is stable. 6-stage architecture, StaticOverrides, gold set eval — the foundation is solid. Fixing 4 P0s in one sprint without introducing regressions (gold set held at 100%) is a sign of maturing quality discipline. Test count at 1,564 is healthy.

### Technical Debt
- **AIChatView** remains 400+ lines with `sendMessage` at ~491 lines. No structural debt is accumulating, but this function is the most likely source of future AI chat regressions. Needs ViewModel extraction.
- **Coverage gaps persist.** `LabReportOCR.swift` has no coverage ahead of the planned LLM rewrite. Writing tests for the existing regex path before replacing it would de-risk #151.
- **Context window at 2048 tokens.** Multi-turn conversations are constrained. Once #151 lands and lab report chunking is implemented (~500 tokens/chunk), we'll have learnings on prompt budget management that can inform a context-window expansion experiment.

### My Recommendation
Before #151 goes in, read `LabReportOCR.swift` and write baseline tests for the existing regex path. The LLM rewrite is a high-risk replacement on low-test code. Tests first prevents "it worked in the simulator" bugs from reaching TestFlight. The design doc calls for confidence scoring — that's the right safety net.

## The Debate

**Designer:** Lab reports LLM has been deferred twice. Users with bloodwork want to see AI extract their values automatically — it's a showstopper feature for the health-tracking power user. Ship it this sprint, no more deferral.

**Engineer:** Agreed on priority, not on approach. `LabReportOCR.swift` has no test coverage. We're proposing to replace its internals with Gemma 4 chunked extraction and add confidence scoring. That's a lot of moving parts on an untested foundation. Write baseline tests for the regex path first — it's 2 hours of work that prevents a silent regression.

**Designer:** Fair. The accuracy warning banner in the design doc is already our safety net for users — it sets expectations that LLM parsing isn't perfect. But baseline tests before the rewrite is sensible. Do both: tests first, then implementation.

**Engineer:** That's the right order. Tests → implementation → coverage check. Also worth noting: the `Docs/designs/74-lab-reports-llm.md` doc specifies SmolLM devices fall back to regex-only. Make sure that path is explicitly tested too — it's the code path most likely to be accidentally broken.

**Agreed Direction:** Implement #151 this sprint with tests-first discipline. Regex baseline tests before any LLM code is written. SmolLM fallback path explicitly covered. Confidence scoring and accuracy banner are required — not optional.

## Decisions for Human

1. **Exercise enrichment scope** — #140 is time-boxed research. If Wger/free-exercise-db have usable assets, should we implement images this sprint or defer to a dedicated sprint? Options: (a) implement if research is positive, (b) always defer to next sprint after research, (c) skip research entirely and commit to Boostcamp-parity as a Phase 4 milestone.

2. **Smart Units saturation call** — Serving count is ~65 (intentional nuts/canned). After #156 (cross-interface consistency pass), should Smart Units be declared saturated and removed from the permanent highest-priority focus? Or continue for another sprint?

3. **Food DB strategy** — Manual enrichment at 2,067 foods is reaching diminishing returns. USDA API integration (in roadmap) would unlock verified data at scale. Should we start a design spike for USDA API this sprint?

---
*Comment on any line for strategic feedback. @ashish-sadh @nimisha-26*
