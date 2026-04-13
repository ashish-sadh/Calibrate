# Product Review — Cycle 535 (2026-04-12)
Review covering cycles 450–535. Previous review: cycle 450.

## Executive Summary

Food database hit the 1,500 target and meal planning dialogue is nearly complete — the two P0 items from last sprint. A voice-input crash fix validated real-device behavior. The competitive landscape is intensifying: MFP acquired Cal AI for photo scanning, MacroFactor launched a Workouts companion app, and Whoop overhauled its heart-rate algorithm. Our on-device privacy moat holds, but we need to ship meal planning and accelerate chat polish to stay differentiated.

## Scorecard
| Goal | Status | Notes |
|------|--------|-------|
| Food DB to 1,500 (P0) | Shipped | 1,201 → 1,500+. Chinese, Middle Eastern, American classics, sandwiches, soups, healthy options |
| Meal planning dialogue (P0) | In Progress | Full implementation built: state machine phase, iterative suggestion flow, smart pills. Awaiting commit + testing |
| AIChatView ViewModel extraction (P1) | Not Started | Meal planning was built without it; still technically clean via extensions |
| Chat UI streaming text animation (P1) | Not Started | Displaced by meal planning work |
| Voice input real-device validation (P2) | Partially Done | Voice button crash found and fixed on real device — audio engine needed pre-start before querying format |
| Intent normalizer centralization (P2) | Not Started | |
| Food diary UX improvements (P2) | Not Started | |

**Sprint completion: 1.5/7 shipped (21%).** Down from 50% last sprint. The two P0 items consumed nearly all cycles, with meal planning being substantially more complex than scoped.

## What Shipped (user perspective)

- **300+ new foods** — Chinese dishes (kung pao chicken, mapo tofu), Middle Eastern (shawarma, falafel), American classics (BLT, Philly cheesesteak), soups, sandwiches, and healthy bowl options. Fewer "food not found" moments.
- **Voice button no longer crashes** — Tapping the microphone button on certain devices caused an immediate crash. Fixed.
- **"Plan my meals" is coming** — Nearly complete: ask "plan my meals today" and the AI suggests foods based on your remaining calories and protein, lets you pick by number, ask for more options, or type any food to log it. Smart suggestion pills appear during planning.

## Competitive Position

The market is consolidating around AI + all-in-one platforms. MFP acquired Cal AI (photo food scanning, 15M downloads) and integrated with ChatGPT Health — they're building a cloud AI moat with a 20M food database. MacroFactor launched a separate Workouts app, expanding from nutrition into exercise. Whoop overhauled its heart-rate algorithm and launched women's health biomarker panels. Strong remains focused and minimal (added templates search, measurement widgets). Our edge: on-device privacy, AI chat as primary interface, and all-in-one without subscriptions. Our gap: food DB size (1,500 vs 20M), no photo scanning, and chat still lacks the polish of a shipping product.

## Designer × Engineer Discussion

### Product Designer

I'm concerned about sprint velocity. 21% completion is our worst rate yet, and it's because meal planning turned out to be a bigger feature than we scoped. That said, the feature itself is exactly right — iterative meal-by-meal suggestions based on remaining macros is the kind of sticky daily-use feature that no competitor does on-device. When I mentally walk through "open app → plan my meals → pick suggestions → done," it's genuinely compelling.

The competitive landscape is alarming in one specific way: MFP now has Cal AI's photo scanning AND ChatGPT integration. They're attacking from both sides — visual input and conversational AI. We can't match their DB size or photo capability, but we can win on chat quality and privacy. The fact that their AI is cloud-based and ours is on-device is a real differentiator for privacy-conscious users.

MacroFactor launching a separate Workouts app is interesting. They're fragmenting their experience across two apps while we're all-in-one. That's an advantage for us, but only if our exercise tracking is good enough. Right now it's functional but text-only — no muscle group visuals, no exercise images.

My recommendation: ship meal planning this cycle, then focus hard on chat polish. Streaming text animation and richer confirmation cards would close the perceived-quality gap. The app needs to feel premium before we can credibly pitch it to new TestFlight users.

### Principal Engineer

Meal planning implementation is solid architecturally. The `planningMeals` phase in ConversationState follows the same enum pattern as `awaitingMealItems` and `awaitingExercises` — no new patterns, just extending what works. The handler properly detects topic switches so users aren't trapped in planning mode.

I was wrong last review that ViewModel extraction was required for meal planning. The extensions pattern (`AIChatView+MessageHandling`, `AIChatView+Suggestions`) absorbed the new code cleanly. The view file itself didn't grow. ViewModel extraction remains a good idea but isn't blocking anything.

The voice crash fix was a genuine real-device issue — `AVAudioEngine` needs `prepare()` before you query `inputNode.outputFormat`. Simulator doesn't expose this because it stubs the audio hardware. This validates that we need real-device testing for all hardware-dependent features.

Sprint velocity dropped because meal planning is genuinely complex: state machine phase + iterative suggestion loop + number selection + "more" pagination + topic switch detection + food search fallback + smart suggestion pills. That's 7 distinct behaviors in one feature. We should scope future features more granularly — break meal planning into "basic flow" and "polish" rather than one monolithic item.

One technical concern: `FoodService.suggestMeal()` and `FoodService.topProteinFoods()` are called in the meal planning handler. I haven't verified these methods exist yet. If they don't, the uncommitted code won't compile. We need to validate the full build before committing.

### What We Agreed

1. **Commit and ship meal planning** — validate build, run tests, commit. This is the cycle's deliverable.
2. **Scope sprints tighter** — 5 items max, break complex features into "basic" and "polish" phases
3. **Chat polish is the next priority** — streaming text, richer cards, perceived quality
4. **ViewModel extraction only when blocking** — extensions pattern is working; don't refactor for its own sake
5. **Real-device testing matters** — voice crash proved simulator isn't enough for hardware features
6. **Food DB: pause manual enrichment** — 1,500 is good enough for now. Next DB investment should be USDA API or search quality, not more manual entries

## Sprint Plan (next 20 cycles)
| Priority | Item | Why |
|----------|------|-----|
| P0 | Ship meal planning dialogue | 90% built, just needs build validation + commit. The sticky daily-use feature. |
| P0 | Chat streaming text animation | Text appearing in chunks feels robotic. Character-by-character is the #1 polish gap. |
| P1 | Richer chat confirmation cards | Workout/weight logged confirmations should be structured cards, not plain text. |
| P1 | Food search quality improvements | Better aliases, partial matches, spelling correction. "paneer" should find all paneer dishes. |
| P2 | Voice input real-device validation | Crash is fixed but need systematic testing: ambient noise, accents, partial sentences. |

## Feedback Responses

No feedback received on previous reports.

## Open Questions for Leadership

1. **Food DB strategy inflection**: At 1,500 foods, manual enrichment has diminishing returns. Should we invest in USDA API integration for verified nutrition data at scale, or is the current DB sufficient with better search/aliases?
2. **Exercise visual gap**: Every competitor has exercise images or muscle group diagrams. We have 873 exercises but text-only. Should we prioritize adding visual exercise content (images, muscle maps), or keep focusing on AI chat and nutrition?
3. **TestFlight expansion**: We've been dogfooding with a small circle. When is the right time to invite more external testers — after meal planning ships, after chat polish, or after a specific milestone?
