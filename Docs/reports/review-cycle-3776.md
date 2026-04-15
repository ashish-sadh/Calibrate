# Product Review — Cycle 3776 (2026-04-15)

## Executive Summary
Design doc #65 (AI chat structural fix) fully reviewed, revised, approved, and merged. New sprint planned: 8 tasks across 4 phases to implement the multi-stage LLM pipeline (normalize → intent classify → domain extract → validate → confirm → execute). Food DB reached 1,814. All confirm-first paths are now gated.

## Scorecard

| Metric | Value | Trend |
|--------|-------|-------|
| Build | 122 | +2 from last review |
| Tests | 1321+ | stable |
| Food DB | 1,814 | +198 from last review |
| AI Tools | 20 | stable |
| AI Eval | 55-query gold set, 100% baseline | new metric |
| P0 Bugs Fixed | 2 (confirm-first bypass, flaky test) | |
| Sprint Velocity | 100% (5/5 tasks closed) | |

## What Shipped Since Last Review

- Design doc #65 revised addressing all 3 owner review comments, merged (PR #112)
- Food confirm-first flow enforced on all 5 paths (Log Again, Copy to Today, Quick+, copy yesterday, empty diary copy)
- Food DB +198 foods (branded protein bars/shakes, Indian regional, African, Italian)
- AI eval harness expanded to 15+ queries per tool with DB state pollution fix
- Pipeline research documented (OpenAI, Rasa, Dialogflow patterns)

## Competitive Analysis

- **MyFitnessPal:** Continues expanding AI-powered food logging with Cal AI acquisition. Cloud-based photo scanning improving but still weak on non-Western food. 20M+ food DB remains the benchmark.
- **Boostcamp:** Still the gold standard for exercise content with video/GIF instructions. No major changes.
- **Whoop:** AI Strength Trainer now accepts text AND photo input for workout creation. Cloud-based. Behavior insights remain best-in-class.
- **Strong:** Clean, minimal workout logging. Steady. No AI features.
- **MacroFactor:** Workouts app expanding with personalized progression. Adaptive TDEE remains their killer feature.

## Product Designer Assessment

*Speaking as the Product Designer persona:*

### What's Working
- **Confirm-first is now universal** — every food logging path shows the user what's about to be logged. This prevents the #1 user frustration: wrong food silently recorded.
- **Gold set eval gives measurement** — for the first time we can quantify AI chat quality (55 queries, 100% baseline). This is table stakes for iterating on the pipeline.
- **Food DB breadth** — 1,814 foods with strong Indian, regional, and branded coverage. Users can find most of what they eat.

### What Concerns Me
- **AI chat is still brittle despite the confirm safety net.** The design doc identifies the root cause (single LLM call doing intent + extraction) but we haven't fixed it yet. Users still see misclassifications.
- **No voice-to-action testing in the field.** Voice input shipped but we haven't stress-tested the full voice → parse → confirm → log pipeline with real ambient noise, accents, etc.
- **Exercise tab is still text-only.** 960 exercises with zero visual content. Boostcamp gap is widening.

### My Recommendation
Ship the multi-stage pipeline (sprint tasks #92-#95). This is the single biggest quality improvement we can make. A chat that correctly understands "log 2 eggs and toast for breakfast" on the first try beats any new feature.

## Principal Engineer Assessment

*Speaking as the Principal Engineer persona:*

### Technical Health
- **Architecture is clean** after DDD cleanup. 7 domain services, proper separation. Ready for the pipeline refactor.
- **Test coverage is healthy** at 1321+ tests but needs refresh after the pipeline rewrite lands.
- **Dual-model strategy is sound.** SmolLM path stays untouched during refactor — zero regression risk for 6GB devices.

### Technical Debt
- **AIChatView.sendMessage at 491 lines** — the pipeline refactor is the right time to decompose this. Don't refactor for its own sake; refactor as part of the multi-stage pipeline work.
- **StaticOverrides at 421 lines** — will naturally shrink as the LLM pipeline takes over Gemma-path handling.
- **mark-in-progress hook fires on every Bash call** — reads `git log -1` regardless of whether the Bash command was a git commit. Minor but causes label churn.

### My Recommendation
Execute the pipeline refactor in strict phase order. Phase 1 (intent classifier) is the riskiest — if the 2B model can't reliably classify intents in a focused prompt, the whole architecture needs rethinking. Validate Phase 1 thoroughly before investing in domain extractors.

## The Debate

**Designer:** Users need the pipeline to work correctly. Every misclassification erodes trust. Ship #92 (intent classifier) as fast as possible and get it into TestFlight for real-world testing.

**Engineer:** Agreed on priority, but I want to gate on the gold set eval, not just "it builds." The 55-query baseline at 100% must hold. If the intent classifier drops accuracy, we stop and tune the prompt before moving to domain extractors.

**Designer:** Fair. But don't over-engineer the eval. 55 queries is a good start — add 10-15 more covering the pipeline boundary cases (food vs nutrition query, exercise log vs exercise info) and that's sufficient.

**Engineer:** Deal. I also want to point out: the SmolLM path staying unchanged means we can ship a TestFlight where Gemma users get the new pipeline and SmolLM users get the old one. Natural A/B test.

**Agreed Direction:** Ship Phase 1 (intent classifier + pipeline skeleton) with expanded eval coverage. Gate on gold set. Get to TestFlight quickly so real-world voice + chat feedback can inform Phase 2 (domain extractors).

## Decisions for Human

1. **Pipeline Phase 1 approach:** Should we ship the intent classifier to TestFlight before Phase 2 (domain extractors), or wait until the full pipeline is ready? Early ship = real feedback faster but partial improvement. Full ship = cleaner but slower.
2. **Exercise visuals (#66):** Design doc is approved but implementation deferred. When should this get sprint slots — after pipeline ships, or parallel track?
3. **Lab reports (#74):** P1 feature request with LLM parsing. Deferred this sprint. Should this move to next sprint or stay in backlog?

---
*Comment on any line for strategic feedback. @ashish-sadh @nimisha-26*
