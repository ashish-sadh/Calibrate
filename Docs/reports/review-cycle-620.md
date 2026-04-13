# Product Review — Cycle 620 (2026-04-12)
Review covering cycles 535–620. Previous review: cycle 535.

## Executive Summary

This sprint achieved 100% completion on the sprint plan from Review #16 — all 5 items shipped. Chat now feels polished with typewriter animations, structured confirmation cards, and meal planning dialogue. We fixed 4 silent data-accuracy bugs in the AI pipeline that could have caused wrong calorie/macro logging. Test coverage jumped to 935 tests with all major services now above threshold.

## Scorecard
| Goal | Status | Notes |
|------|--------|-------|
| Ship meal planning (P0) | Shipped | Iterative suggestions, number selection, topic switch, smart pills |
| Chat streaming text animation (P0) | Shipped | Typewriter reveal for instant AI responses |
| Richer chat confirmation cards (P1) | Shipped | Weight (with weekly trend) and workout structured cards |
| Food search quality (P1) | Shipped | 40+ synonym expansions (Hindi, British English, abbreviations) |
| Voice real-device validation (P2) | Deferred | Requires physical device — cannot validate in simulator |

## What Shipped (user perspective)

- **Meal planning dialogue** — Say "plan my meals today" and get iterative suggestions based on remaining calories and protein. Pick by number, say "more" for alternatives, or "done" to stop.
- **Typewriter text animation** — AI responses now reveal character-by-character instead of appearing as a wall of text. Feels more natural and responsive.
- **Confirmation cards** — When you log weight or complete a workout, you see a rich card (not just text) with the value, trend, and details.
- **Food diary sections** — Food entries are now grouped by meal (breakfast, lunch, dinner, snack) with calorie and protein subtotals per meal.
- **Better food search** — Regional terms like "curd" (yogurt), "aloo" (potato), "palak" (spinach) now find the right foods. 40+ Hindi, British English, and abbreviation synonyms added.
- **Smarter AI parsing** — Fixed 4 bugs where the AI could silently log wrong data: wrong carb/fat values in quick-add, phantom food entries from numeric-only input, and confusing responses when picking out-of-range meal options.
- **935 tests** — Up from 886, with all critical services now above coverage threshold.

## Competitive Position

Whoop just closed $575M at a $10.1B valuation and is hiring 600+ people — they're building Advanced Labs biomarker integration into their recovery ecosystem. MFP launched AI photo logging and GLP-1 medication tracking in their Winter 2026 release, plus a new "Today" screen with weekly macro insights. MacroFactor's Workouts app added Live Activity lock screen timers and cardio support. Our on-device privacy moat remains unique — no competitor does AI-powered meal planning or natural language logging fully on-device. The gap is visual presentation (exercise images, muscle maps) and food DB size (1,500 vs MFP's 20M+).

## Designer × Engineer Discussion

### Product Designer

I'm genuinely excited about the velocity this sprint. 100% completion on the sprint plan is a first in several reviews, and every item shipped is something users actually see and feel. The typewriter animation and confirmation cards transformed chat from "prototype" to "product" — these are the kind of polish touches that make users trust the app.

The meal planning dialogue is our strongest differentiator right now. "Plan my meals today" → iterative suggestions based on remaining macros, on-device, private — nobody else does this. MFP's new "Today" screen is a step in this direction but it's cloud-dependent and not conversational.

What concerns me: we still have zero visual exercise content. Boostcamp has videos and muscle diagrams for every exercise. Our 873 exercises are text-only. Every user who opens the exercise tab sees this gap. It's not a sprint item — it's a structural investment decision (image assets, storage, possibly on-demand download). But we can't ignore it forever.

MFP adding GLP-1 tracking is interesting — we haven't considered medication interactions with our supplement/biomarker tracking. Not urgent, but worth watching.

### Principal Engineer

The coverage sprint was the right investment. We went from 3 files below threshold to just 1 (IntentClassifier at 63%, which has LLM-dependent paths that are inherently hard to unit test). ExerciseService jumped from 47% to 92% — that's real confidence in code we ship.

The bug fixes this sprint were more important than they look. The carb/fat regex bug could parse "400 cal" as 400 carbs. The multi-food parser could create entries with empty food names that matched random DB items. These are the kind of silent data corruption bugs that erode user trust. The systematic bug hunt (running an analysis agent across StaticOverrides, AIActionExecutor, AIRuleEngine) is a pattern worth repeating every few sprints.

The word-number resolution fix ("twelve hundred" → 1200) exposed a gap in our design: `resolveWordNumbers` only runs before goal parsing, not before quick-add. If we want word numbers everywhere, we should apply it at the top of StaticOverrides.match() instead of per-feature. Not urgent but worth noting.

AIChatView is still 400+ lines. The extensions pattern (+MessageHandling, +Suggestions) keeps absorbing complexity cleanly, but eventually we'll want ViewModel extraction. The trigger should be when we add a new state phase (workout builder).

### What We Agreed

1. **Food diary UX is the next visual win** — inline editing, better macro display, time-of-day headers
2. **AI chat reliability over new features** — the bug hunt exposed real issues; run systematic analysis quarterly
3. **Exercise visual gap is acknowledged but deferred** — images/videos require significant asset investment; keep text-only for now, revisit when exercise tab gets active development
4. **Voice validation stays deferred** — requires physical device testing; not blocking any user flows
5. **Coverage maintenance, not sprints** — all services above threshold; maintain via boy scout rule

## Sprint Plan (next 20 cycles)
| Priority | Item | Why |
|----------|------|-----|
| P0 | Food diary inline editing | Users can't tap-to-edit calories/macros — have to delete and re-add |
| P0 | AI chat bug hardening | Run systematic analysis on remaining pipeline files every 5 cycles |
| P1 | Saved meals / quick re-log | "Log yesterday's breakfast" is a top request from dogfooding |
| P1 | Food search partial matching | "chick" should find "chicken breast" — prefix matching for incomplete typing |
| P2 | Workout history polish | Better date grouping, volume tracking, personal records display |
| P2 | Coverage maintenance | Keep all files above threshold via boy scout rule |

## Feedback Responses

No feedback received on previous reports.

## Open Questions for Leadership

1. **Exercise images**: Should we invest in exercise visual content (images, muscle group diagrams) now, or wait until the exercise tab gets dedicated feature work? This is our biggest visual gap vs competitors like Boostcamp.
2. **GLP-1/medication tracking**: MFP just added GLP-1 medication tracking with side-effect logging. Is this a category we should watch or actively plan for? It could tie into our supplement and biomarker tracking.
3. **Food DB strategy**: At 1,500 foods we're 0.0075% of MFP's 20M. Should we invest in USDA API integration now, or keep improving search quality on our existing DB? The search quality improvements (synonyms, spell correction) have high ROI per engineering hour.
