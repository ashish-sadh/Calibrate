# Product Review Log

Periodic product + engineering reviews. Every 10 cycles of the self-improvement loop.

---

## Review #34 — 2026-04-13 (Cycle 1248)

### Summary
Two sprint items shipped: food diary reorder fix for same-timestamp entries, IntentClassifier coverage pushed 63→99%. Muscle group heatmap remains unshipped (3rd deferral). Sprint: muscle group heatmap (P0), proactive push notifications (P0), sendMessage decomposition (P1), food search miss telemetry (P1), exercise instructions via chat (P2).

### Key Achievement
IntentClassifier at 99% — highest coverage file in the codebase. Validates "test deterministic wrappers, not stochastic LLM output" pattern.

### Key Concern
Exercise visual presentation still text-only after 3 deferrals. Muscle group heatmap is P0 next sprint — no exceptions.

### Sprint Plan (next 20 cycles)
P0: Muscle group heatmap. P0: Proactive push notifications (protein/supplement/workout). P1: sendMessage decomposition. P1: Food search miss telemetry. P2: Exercise instructions via chat.

---

## Review #33 — 2026-04-13 (Cycle 1180)

### Summary
Food diary reorder fixes shipped (cross-meal-group, direction, meal type picker). IntentClassifier coverage pushed 63→78%. P0 bug #30 surfaced: reorder no-op on same timestamps. Sprint: fix bug #30 (P0), IntentClassifier to 80%+ (P0), muscle group heatmap (P1), food DB search miss telemetry (P2).

### Key Achievement
IntentClassifier pure-function extraction approach reversed a 4-review assumption that 63% was the coverage ceiling.

### Key Concern
Exercise visual presentation remains text-only. Muscle group heatmap deferred twice — credibility risk.

### Sprint Plan (next 20 cycles)
P0: Fix bug #30 (same-timestamp reorder). P0: IntentClassifier to 80%+. P1: Muscle group heatmap. P2: Food DB search miss telemetry.

---

## Review #32 — 2026-04-13 (Cycle 1120)

### Summary
TestFlight build 109 published. IntentClassifier refactored for testability (extracting pure functions from LLM-dependent code). Sprint: IntentClassifier to 80% (P0), food search prefix matching (P1), muscle group heatmap (P1), food DB search miss analysis (P2).

### Key Achievement
IntentClassifier coverage approach reversed — extracting deterministic wrappers makes 80%+ achievable without LLM mocking.

### Key Concern
Food search quality is highest-friction user moment. Prefix matching missing. Food DB at 1,500 vs MFP's 14M.

### Sprint Plan (next 20 cycles)
P0: IntentClassifier to 80%+. P1: Food search prefix matching. P1: Muscle group heatmap. P2: Food DB search miss analysis.

---

## Review #31 — 2026-04-13 (Cycle 1088)

### Summary
All five sprint items from Review #30 shipped — 100% completion. 8 confirmation card types cover every chat action (food, weight, workout, navigation, supplement, sleep, glucose, biomarker). Muscle group icons on workout cards. Bug fixes. 19 new tests.

### Key Achievement
Confirmation card architecture complete — every major chat action has structured visual feedback.

### Key Concern
Food DB search miss telemetry is a blind spot. Can't improve what we can't measure.

### Sprint Plan (next 20 cycles)
P0: IntentClassifier to 80%+. P1: Food search prefix matching. P1: Muscle group heatmap. P2: Food DB search miss analysis.

---

## Review #30 — 2026-04-13 (Cycle 1038)

### Summary
ViewModel extraction shipped (P1), supplement/sleep confirmation cards in progress (P1). 2/4 sprint items completed or in progress. MacroFactor launched Workouts app with Live Activities and AI recipe photos. Sprint: finish supplement/sleep cards (P0), glucose/biomarker cards (P0), exercise visual polish (P1), state.md update + TestFlight build 108 (P1), food DB search analysis (P2).

### Key Achievement
ViewModel extraction separated state+logic from rendering, enabling faster iteration on new card types. Supplement and sleep card UI complete, wiring done.

### Key Concern
Exercise vertical is weakest vs competition (text-only while MacroFactor has auto-progression and videos). Need visual polish before next review.

### Sprint Plan (next 20 cycles)
P0: Finish supplement/sleep cards. P0: Glucose + biomarker cards. P1: Exercise visual polish. P1: State.md + TestFlight 108. P2: Food DB search miss analysis.

---

## Review #29 — 2026-04-13 (Cycle 983)

### Summary
Rich confirmation cards shipped (P0) — navigation, activity preview, weight, workout all show structured visual cards in chat. 1/4 sprint items completed. Market validates all-in-one positioning. Sprint: bug hunting (P0), ViewModel extraction (P1), supplement/sleep cards (P1), food DB quality (P2).

### Key Achievement
Every major chat action now has structured visual feedback. The "chat feels like a real messaging app" story is complete.

### Key Concern
P1/P2 slip pattern persists (1/4 shipped). Sprint scope of 4 items is right but P0 must finish faster to protect P1 time.

### Sprint Plan (next 20 cycles)
P0: Bug hunting on recent features. P1: AIChatView ViewModel extraction. P1: Supplement/sleep confirmation cards. P2: Food DB search miss analysis.

---

## Review #28 — 2026-04-13 (Cycle 918)

### Summary
Two features shipped after 3 consecutive zero-feature reviews: workout split builder (multi-turn PPL/upper-lower/full-body design) and voice input UX overhaul (fixed eaten-words bug). TestFlight build 107. Review cadence changed to milestone-based. Sprint: chat confirmation cards (P0), bug hunting (P1), ViewModel extraction (P1), food DB quality (P2).

### Key Achievement
Workout split builder is the second multi-turn dialogue feature (after meal planning), proving the conversational design pattern for daily engagement.

### Key Concern
Competitive gap widening — Whoop has AI Coach with photo parsing, MFP has ChatGPT integration + 20M foods. Privacy moat must be paired with experience quality.

### Competitive Alert
Whoop AI Coach: photo-to-workout, proactive nudges (OpenAI-powered). MFP acquired Cal AI, integrated ChatGPT Health. MacroFactor Workouts app at $72/yr. Boostcamp added muscle engagement viz. All cloud-dependent — our on-device privacy moat holds but experience gap grows.

---

## Review #27 — 2026-04-12 (Cycle 869)

### Summary
Third consecutive review with zero features. Review loop is self-reinforcing — documentation commits trigger the next review. Agreed: suspend reviews until workout split builder ships, then switch to milestone-based cadence (every 2 features, not every 20 commits).

### Key Decision
Reviews suspended until next feature delivery. Sprint plan unchanged from Review #26.

---

## Review #26 — 2026-04-12 (Cycle 849)

### Summary
20 cycles since last review. Zero new user-facing features — all cycles consumed by review process overhead. Previous sprint fully delivered (3/4, 75%). Sprint refreshed: workout split builder (P0), chat UI (P1), bug hunting (P1), food DB (P2). IntentClassifier 63% formally accepted as floor. Review cadence under question.

### Key Achievement
Honest velocity audit: identified review-to-feature ratio inversion and refreshed sprint immediately.

### Key Concern
Review mechanism (every 20 commits) counts review commits toward next trigger, creating a self-reinforcing loop. Recommend time-based or milestone-based cadence.

### Competitive Alert
Whoop launched Women's Health panel (11 biomarkers, cycle-hormone integration). MFP integrated ChatGPT. MacroFactor added Live Activities. All cloud-dependent — our on-device privacy moat holds.

---

## Review #25 — 2026-04-12 (Cycle 829)

### Summary
23 cycles since last review. 3/4 sprint items shipped (75% — best since Review #21). Chat navigation, USDA chat integration, and systematic bug hunting all complete. 966 tests (+4). AI-first vision complete: every major app action is now conversational (log + query + navigate + plan). Only IntentClassifier coverage (63%) remains unshipped — accepted as LLM code ceiling.

### Key Achievement
USDA food search now works through AI chat, not just the Food tab UI. Users can type "log acai bowl" in chat and get results from USDA/OpenFoodFacts even if it's not in local DB. The AI-first promise extends to food discovery.

### Key Concern
IntentClassifier coverage has been deferred 4 consecutive reviews. Recommend accepting 63% as floor for LLM-dependent code and removing from sprint scope.

### Competitive Alert
Full conversational app control (log + query + navigate + plan) entirely on-device remains unique. MFP and Whoop require cloud for AI features. Privacy moat deepens with each on-device capability.

---

## Review #24 — 2026-04-12 (Cycle 806)

### Summary
21 cycles since last review. Chat navigation shipped — "show me my weight chart" switches tabs via AI chat. Static overrides for common phrases, LLM tool for natural variations. Chat panel collapses on navigation. 962 tests (+16). 1/4 sprint items shipped (P0).

### Key Achievement
Every major app screen is now navigable through AI chat. The AI-first promise is complete: users can log, query, plan, and navigate entirely through conversation.

### Key Concern
Sprint velocity continues at 1/4. Items 2-4 not started. Tight 4-item scope is correct but execution needs to start on P1s earlier.

### Competitive Alert
No competitor offers on-device AI chat navigation. MFP/Whoop/Strong all require manual tab tapping. Our conversational AI moat deepens with each feature that bypasses traditional UI.

---

## Review #23 — 2026-04-12 (Cycle 785)

### Summary
26 cycles since last review. 1/6 sprint items shipped: proactive workout consistency + logging gap alerts (6 alert types, 948 tests). Chat navigation ("show me my weight chart" switches tabs) is in active development — architecture done, wiring up. TestFlight build 106 published.

### Key Achievement
Proactive alerts now cover 6 behavioral patterns on the dashboard — workout gaps, logging gaps, protein streaks, supplement adherence. The app transitions from passive data logger to proactive health coach.

### Key Concern
Sprint velocity remains at ~17% (1/6). Persistent pattern across Reviews #20, #22, #23. Sprint scope reduced to 4 items max for next cycle.

### Competitive Alert
Privacy-first, on-device AI coaching remains differentiated. MFP and Whoop add cloud AI features requiring data off-device. Our moat: proactive cross-domain coaching without sending user data anywhere.

---

## Review #22 — 2026-04-12 (Cycle 739)

### Summary
20 cycles since last review. 1/5 sprint items shipped, but it was the highest-impact one: USDA API Phase 1. Online food search (USDA + OpenFoodFacts) now gated behind privacy-first opt-in toggle (default OFF). Rate limiting, FoodService.searchWithFallback() for AI chat, updated privacy notice. 946 tests. TestFlight build 106 published.

### Key Achievement
Online food search closes the biggest food DB gap — from 1,500 local foods to 300K+ on-demand via USDA. Privacy preserved with opt-in toggle, local caching, and no PII sent.

### Key Concern
Sprint completion rate dropped to 20% (1/5). Chat navigation, proactive alerts, and bug hunting all slipped. Sprint sizing needs to be more honest — one large P0 should mean fewer P1s.

### Competitive Alert
WHOOP AI Coach now has conversation memory and contextual guidance. MacroFactor Workouts adding Apple Health integration. MFP's free tier continues shrinking. Our privacy-first, on-device approach remains differentiated.

---

## Review #21 — 2026-04-12 (Cycle 719)

### Summary
20 cycles since last review. 100% sprint completion — all 6 planned items shipped (3 P0, 2 P1, 1 P2). AI workout intelligence in chat, proactive protein/supplement alerts on dashboard, 3 P0 data-accuracy bugs fixed with regression tests, muscle group chips on workout cards, USDA API design doc, 942 tests.

### Key Achievement
Proactive alerts (protein streak + supplement gap) shipped on dashboard, marking Drift's transition from data logger to proactive health coach. No competitor does this holistically across nutrition, exercise, and supplements on-device.

### Key Concern
Food DB gap (1,500 vs MFP 20M+) remains. USDA API Phase 1 is agreed as next P0 to close this gap. IntentClassifier at 63% is the only file below coverage threshold.

### Competitive Alert
Drift moving into proactive health coaching space — Whoop occupies this for recovery but nobody does it holistically across nutrition/exercise/supplements on-device. Main remaining gaps: food DB breadth and exercise content (text-only vs Boostcamp videos).

---

## Review #20 — 2026-04-12 (Cycle 699)

### Summary
29 cycles since last review. 4/4 P0s shipped: AI workout intelligence in chat, USDA API design document, hardcoded unit audit (7 files), progressive overload alerts. Plus systematic AI pipeline bug hunt found 3 silent P0 data-accuracy bugs. 936 tests, no open user-reported bugs.

### Key Achievement
Systematic bug hunt found three live data-accuracy issues before users did: integer servings silently dropped by AI intent classifier, "calcium" matching the calorie regex, and undo always deleting food regardless of last action. All documented and queued as P0 fixes.

### Key Concern
Product review hook fired 10+ times in one session due to counter being written at end of process rather than start. Fixed: counter now written as first step. Also: `ConversationState.lastWriteAction` is declared but never used — dead infrastructure that needs resolution.

### Competitive Alert
No major new competitor moves observed this sprint. MFP + Whoop continue cloud AI expansion. Our on-device privacy moat remains the primary differentiator.

### Agreed Direction (Cycles 699–719)
1. Fix 3 AI pipeline P0 bugs (integer servings, calcium regex, undo cross-domain) — one-day fixes, do first
2. Proactive insight alerts — protein adherence, supplement streaks (P0)
3. USDA API Phase 1 — cache table + fetch on miss (P1)
4. Bug hunting pass — food logging + weight pipeline (P1)
5. Exercise presentation — muscle group icons (P2)
6. Tests for all three fixed bugs (P2)

---

## Review #19 — 2026-04-12 (Cycle 670)

### Summary
20 cycles since last review. 2/7 sprint items shipped (both P0s): hardcoded unit audit (7 files fixed) and progressive overload alerts in workout history. P1/P2 items deferred. 936 tests, zero open bugs.

### Key Achievement
Exercise vertical improved with proactive overload coaching. Stale preference pattern permanently closed — all weight display paths now respect user preference.

### Key Concern
P1 items keep slipping across sprints. AI chat workout intelligence and USDA design doc need to be elevated to P0.

### Competitive Alert
No major competitor moves this sprint. MacroFactor Workouts continues to be the exercise benchmark.

### Agreed Direction (Cycles 670–690)
1. AI chat workout intelligence — "how's my bench?" (P0)
2. USDA API design document (P0)
3. Proactive insight alerts — protein, supplements (P1)
4. Systematic bug hunting (P1)
5. Exercise presentation — muscle group icons (P2)
6. Coverage maintenance (P2)

---

## Review #18 — 2026-04-12 (Cycle 650)

### Summary
20 cycles since last review. 4/6 sprint items shipped (67%): food diary inline editing, meal re-log, AI meal categorization fix, workout unit fix. Food search partial matching verified as already working — no code change needed. 936 tests (+1).

### Key Achievement
Food diary has a complete editing story — inline macro editing, meal re-log, copy from past days. Table stakes achieved.

### Key Concern
Exercise is our weakest vertical. MacroFactor launched Workouts with progressive overload automation. Our 873 exercises are text-only with no visual guidance or overload tracking.

### Competitive Alert
MFP acquired Cal AI for photo scanning. Whoop raised $575M for AI coaching. Boostcamp added AI-generated programs. MacroFactor launched Workouts app with progressive overload automation.

### Agreed Direction (Cycles 650–670)
1. Progressive overload alerts in workout history (P0)
2. Hardcoded unit audit — grep "lb"/"lbs" across all views (P0)
3. AI chat workout intelligence — "how's my bench?" (P1)
4. USDA API design document (P1)
5. Systematic bug hunting every 5 cycles (P1)
6. Exercise presentation — muscle group icons (P2)
7. Coverage maintenance via boy scout rule (P2)

---

## Review #17 — 2026-04-12 (Cycle 620)

### Summary
85 cycles since last review. 5/5 sprint items shipped (100%): meal planning dialogue, typewriter animation, confirmation cards, food search synonyms, food diary meal grouping. 4 silent data-accuracy bugs fixed via systematic analysis. 935 tests, all services above coverage threshold except IntentClassifier (LLM-dependent).

### Key Achievement
First 100% sprint completion in several reviews. Every item shipped is user-visible.

### Key Concern
Exercise tab has zero visual content (no images, no muscle diagrams). Structural gap vs Boostcamp.

### Competitive Alert
Whoop closed $575M Series G at $10.1B. MFP added AI photo logging + GLP-1 tracking. MacroFactor Workouts added Live Activity timers + cardio.

### Agreed Direction (Cycles 620–640)
1. Food diary inline editing (P0) — tap to edit macros
2. AI chat bug hardening (P0) — systematic analysis every 5 cycles
3. Saved meals / quick re-log (P1)
4. Food search prefix matching (P1)
5. Workout history polish (P2)

---

## Review #16 — 2026-04-12 (Cycle 535)

### Summary
85 cycles since last review. 1.5/7 sprint items shipped (21%): Food DB to 1,500 (P0), voice crash fix. Meal planning dialogue 90% built but not committed. Sprint velocity dropped due to meal planning complexity — 7 distinct behaviors in one feature.

### Key Achievement
Food DB hit 1,500 target. Meal planning dialogue implementation complete (state machine phase, iterative suggestions, smart pills, topic switch detection).

### Key Concern
21% sprint completion is worst rate yet. Complex features need to be broken into phases ("basic flow" + "polish"). P1/P2 items consistently displaced.

### Competitive Alert
MFP acquired Cal AI (photo scanning + body comp). MacroFactor launched Workouts companion app. Whoop overhauled heart-rate algorithm and added women's health biomarker panels. Market consolidating toward AI + all-in-one.

### Agreed Direction (Cycles 535–555)
1. Ship meal planning (P0) — validate and commit
2. Chat streaming text animation (P0) — biggest remaining polish gap
3. Richer chat confirmation cards (P1) — workout/weight structured cards
4. Food search quality (P1) — aliases, partial matches, spelling
5. Voice real-device validation (P2) — systematic testing

---

## Review #15 — 2026-04-12 (Cycle 450)

### Summary
21 cycles since last review. 4/8 sprint items shipped: chat UI bubbles (P0), typing indicator (P0), tool execution feedback (P1), food DB +236 foods (P1 in progress). Sprint completion improved from 33% to 50%.

### Key Achievement
Chat UI transformation — message bubbles, sparkle avatar, animated thinking indicator, and tool execution feedback. The AI chat went from plain text dump to a native messaging experience.

### Key Concern
P1/P2 items continue to slip. Food DB at 1,437/1,500 (close but not done). Voice validation and meal planning not started.

### Competitive Alert
MFP made barcode scanning paid-only. Whoop AI Strength Trainer accepts photo/screenshot input. MacroFactor Workouts public launch confirmed all-in-one trend.

### Agreed Direction (Cycles 450–470)
1. Food DB to 1,500 (P0) — finish what we started
2. Meal planning dialogue (P0) — "plan my meals today" is the sticky daily-use feature
3. AIChatView ViewModel extraction (P1) — required for meal planning state phases
4. Chat UI streaming text animation (P1) — polish
5. Voice input real-device validation (P2) — testing task, not feature build
6. Intent normalizer centralization (P2) — dedup prefix stripping
7. Food diary UX improvements (P2) — complements meal planning

---

## Review #14 — 2026-04-12 (Cycle 429)

### Summary
71 cycles since last review. 2/6 sprint items shipped: voice input prototype (P0), color harmony (P0). 4 items not started — cycles diverted to Command Center tooling. Bug #5 fixed (meal logging intent). TestFlight build 105 published.

### Key Achievement
Voice input shipped — users can speak to AI chat. Color palette is cohesive across all views. Both long-overdue P0s finally delivered.

### Key Concern
33% sprint completion rate. Internal tooling (Command Center) displaced user-facing work. Chat UI remains plain text — most visible quality gap.

### Agreed Direction (Cycles 429–449)
1. Chat UI — message bubbles (P0)
2. Chat UI — typing indicator (P0)
3. Chat UI — tool execution feedback (P1)
4. Food DB enrichment to 1,500 (P1)
5. Voice input real-device validation (P1)
6. Meal planning dialogue (P2)
7. AIChatView ViewModel extraction alongside chat UI (P2)
8. Intent normalizer — centralize prefix stripping (P2)

---

## Review #13 — 2026-04-12 (Cycle 358)

### Summary
67 cycles since last review. 5/6 sprint items delivered: food DB to 1,201, chat food confirmation card, prompt consolidation, multi-turn reliability, coverage maintenance. Voice input deferred 3rd consecutive review — elevated to P0. Zero open bugs/issues.

### Key Achievement
Multi-turn reliability fixes (topic switch detection, stale state cleanup) + structured food confirmation card = AI chat is meaningfully better. Food DB at 1,201 reduces "not found" frustration.

### Competitive Alert
MFP acquired Cal AI (AI photo, 15M downloads) + ChatGPT Health + Intent (meal planning). Whoop launched Passive MSK (auto muscular load). MacroFactor launched Workouts app. The market is moving fast on AI.

### Agreed Direction (Cycles 358–378)
1. Voice input prototype (P0) — SpeechRecognizer → chat, go/no-go at Review #14
2. Color harmony (P0) — App-wide palette refresh, one cycle
3. Chat UI — bubbles, typing indicator, tool feedback (P1)
4. Food DB to 1,500 (P1)
5. Meal planning dialogue (P2)
6. AIChatView ViewModel extraction alongside chat UI (P2)

---

## Review #12 — 2026-04-12 (Cycle 291)

### Summary
92 cycles since last review. First sprint with 100% completion: all 6 items delivered (coverage sprint, theme overhaul, state machine refactor, food DB enrichment, dashboard redesign, behavior insights v2). Adaptive TDEE reverted (safety). TestFlight build 104 published. Zero open bugs.

### Key Achievement
Macro rings on dashboard + premium dark theme = first time the app looks premium. State machine refactor (ConversationState.Phase) eliminated invalid state combinations.

### Agreed Direction (Cycles 291–311)
1. Food DB enrichment batch 2-3 (P0) — Target 1,200+ foods
2. Chat food confirmation card (P1) — First structured card in chat
3. Prompt consolidation (P1) — Compress token usage
4. Multi-turn reliability (P1) — Test and fix 3-turn flows
5. Voice input research (P2) — SpeechRecognizer feasibility, go/no-go at next review
6. Coverage maintenance (P2) — Boy scout rule, ongoing

---

## Review #11 — 2026-04-12 (Cycle 199)

### Summary
29 cycles since last review. Major milestone: DDD routing complete (83+ DB calls eliminated). AIToolAgent coverage 0%→20%. TestFlight build 103. Zero open bugs. Autopilot consolidated into single loop.

### Key Concern
29 cycles of infrastructure with zero user-visible improvements. Must rebalance to 80% user-facing work.

### Agreed Direction (Cycles 199–219)
1. Coverage sprint (P0) — AIToolAgent/IntentClassifier/AIRuleEngine to 50%
2. UI theme overhaul (P0) — One bold cycle, all views
3. State machine refactor (P1) — After coverage gate met
4. Food DB enrichment (P1) — 50 most-wanted foods
5. Dashboard redesign (P1) — Macro rings, hierarchy
6. Behavior insights v2 (P2) — Sleep/recovery, chat UI polish, multi-turn

---

## Review #1 — 2026-04-12 (Cycle 10)

### Product Designer Persona
_Background: 2yr each at MyFitnessPal, Whoop, MacroFactor, Strong, Boostcamp_

#### Competitive Landscape (April 2026)

| App | Recent Moves |
|-----|-------------|
| **MyFitnessPal** | AI photo-based meal scanning (take a photo, get macros), ChatGPT integration for nutrition Q&A, meal planner with dietitian-reviewed recipes, full app redesign in progress |
| **Boostcamp** | Bodyweight tracker linked to lifting analytics, muscle engagement visualization per program/workout, workout notes |
| **Whoop** | Behavior Insights (connect habits to Recovery scores with 90-day data), Advanced Labs Uploads (PDF/screenshot upload, any language), healthspan focus with proactive biomarker tracking |
| **Strong** | Templates search, measurement widgets, exercise renaming, simple timers. Staying minimal and focused. |
| **MacroFactor** | Launched separate MacroFactor Workouts app, expenditure modifier with step-informed data, micronutrient tracking, Apple Health integration coming |

#### Drift Strengths
1. **AI chat is genuinely unique.** No competitor has on-device conversational AI for health tracking. MFP's ChatGPT integration is cloud-based and limited to recipes/Q&A — it can't log food, start workouts, or cross-reference your data. Drift's AI can do all of this locally.
2. **Cross-domain coverage in one app.** Food + weight + exercise + sleep + supplements + glucose + biomarkers + body comp + cycle tracking. Competitors are single-domain or require multiple apps.
3. **Privacy as a feature.** Zero cloud, zero accounts. In 2026 where MFP sends your data to ChatGPT and Whoop uploads labs to their servers, "everything stays on your phone" is a real differentiator.
4. **Dual-model tiered pipeline** is architecturally sound. Tier 0 instant rules handle 60-70% of queries with zero latency. Smart fallback to LLM when needed.

#### Drift Gaps vs Competitors
1. **Food DB breadth** — 1041 foods vs MFP's 14M+. This is the #1 user-facing gap. Common foods are covered but long tail is missing.
2. **Photo food logging** — MFP now has AI photo scanning. This is becoming table stakes for nutrition apps. Drift has no photo input.
3. **Visual exercise presentation** — Boostcamp has muscle group diagrams and engagement visualization. Drift has 873 exercises but text-only. Major visual gap.
4. **Behavior-outcome insights** — Whoop connects daily behaviors to Recovery with statistical evidence. Drift has cross-domain queries but no automated insight generation (e.g., "you sleep 23 min more on days you don't eat after 8pm").
5. **Adaptive calorie targets** — MacroFactor's expenditure algorithm adjusts targets based on real weight trends + step data. Drift has static TDEE.
6. **UI polish** — MFP is redesigning. Strong is famously clean. Drift's UI is functional but rough compared to these polished apps.

#### New Ideas
1. **Automated behavior insights** — "Your weight drops faster in weeks where you log 5+ workouts." Correlate food/exercise/sleep patterns with weight trends. Low-lift with existing cross-domain data.
2. **Lab PDF upload with on-device OCR** — Whoop just launched this. We already have biomarker tracking + VisionKit is built into iOS. Natural extension.
3. **Muscle group heatmaps** — Boostcamp's muscle engagement view but for workout history. "This week: heavy chest/back, light legs." Visual and motivating.
4. **Adaptive TDEE** — Use actual weight trend data to back-calculate true expenditure and auto-adjust calorie targets. This is MacroFactor's killer feature.

#### Proposed Roadmap Changes
- Promote **Adaptive TDEE** from Later to Now (Weight section) — it's a differentiator and we have the weight trend data
- Add **Automated behavior insights** to Now (new section) — low effort, high perceived value
- Move **Photo food logging** from Next to Now (Food section) — table stakes in 2026
- Add **Muscle group heatmaps** to Next (Exercise section) — medium effort, high visual impact

---

### Principal Engineer Persona
_Background: 10yr each at Amazon and Google_

#### Assessment of Designer's Proposals

**Agree: Adaptive TDEE → Now.** This is achievable. We have `WeightTrendService` with trend calculation and `NutritionService` with daily calorie data. The algorithm is: compare predicted weight loss (based on logged calories vs TDEE) to actual weight trend, compute the delta, adjust TDEE estimate. MacroFactor published their approach — it's a moving average, not rocket science. Can be a pure service with tests. **Ship it.**

**Agree: Automated behavior insights → Now, but scoped tightly.** Don't build a general correlation engine. Start with 3-5 hardcoded insights: (1) workout frequency vs weight trend, (2) protein hitting target vs weight trend, (3) sleep duration vs recovery score. Each is a single SQL query over existing tables. Display on dashboard as a card. No ML, no statistical significance testing — just descriptive stats with thresholds. **Ship the simple version.**

**Push back: Photo food logging → Now.** This requires Core ML integration, a food classification model, UI for photo capture + result confirmation, and accuracy that won't embarrass us. MFP uses cloud AI for this — their model is huge. On-device food classification models (MobileNetV3 fine-tuned on food) exist but accuracy on Indian food, mixed dishes, and restaurant plates is poor. We'd ship a feature that works for a banana and fails for dal makhani.

**Counter-proposal:** Keep photo food logging in Next. Instead, prioritize **barcode scanning coverage** (we have the scanner but limited DB) and **voice input via iOS SpeechRecognizer** (text-to-speech → pipe to existing AI chat). Voice is higher ROI: it makes the AI chat faster, works with our existing pipeline, and requires no new model. SpeechRecognizer is on-device in iOS 17+.

**Agree: Muscle group heatmaps → Next.** Good visual feature but not urgent. Our exercise DB has muscle group tags — the data is there. When we get to it, it's a view layer addition, not an architectural change.

#### Technical Sustainability Check

Current architecture is solid for Phase 3c goals:
- **GRDB + SQLite** handles all data needs. No ORM migration risk.
- **Tiered AI pipeline** is the right design. Tier 0 rules keep latency low while LLM handles complex queries.
- **Concern: WeightViewModel stale state pattern** (the LB/KG bug). This isn't just a unit bug — it's a pattern where `@Observable` view models capture `Preferences.*` at init and never re-read. Audit all view models for this pattern when fixing the bug. Don't just fix WeightViewModel — fix the pattern.
- **Test count (729+) is healthy** but coverage has gaps. The coverage-check hook is the right forcing function. Keep it.

#### Sequencing Recommendation
1. **Fix LB/KG bug + audit stale preference pattern** (current sprint P0 — already identified)
2. **Adaptive TDEE** (new service + tests, ~2 cycles)
3. **3-5 hardcoded behavior insights on dashboard** (~1-2 cycles)
4. **UI polish pass** (ongoing, every cycle)
5. **Voice input** via SpeechRecognizer → AI chat pipe (Phase 4 pull-forward, ~2-3 cycles)

---

### Consensus & Roadmap Updates

Both personas agree on:
1. **Adaptive TDEE → Now** in Weight section
2. **Behavior insights (scoped) → Now** as new section
3. **Photo food logging stays in Next** — voice input is higher ROI for Phase 3c
4. **Voice input pulled forward** from Phase 4 to late Phase 3c / early Phase 4
5. **Muscle group heatmaps → Next** in Exercise section
6. **Stale preference pattern audit** added to Quality Now section

---

## Review #2 — 2026-04-12 (Cycle 68)

### Progress Since Review #1

Shipped all 3 priority items from Review #1 sequencing in ~5 cycles:
1. **LB/KG unit switching** — Fixed stale preference pattern in WeightViewModel, extended to all exercise/workout views. DB stays in canonical units, conversion at view boundaries.
2. **Adaptive TDEE** — EMA-smoothed (alpha=0.2) adaptive estimation from weight trend data. 3-point safety ramp-up. 0.4 dampening factor. Persists in TDEEConfig.
3. **Behavior insight cards** — 3 insights on dashboard: workout frequency vs weight trend, protein adherence, logging consistency. Minimum data thresholds before showing.

Also fixed: flaky CycleCalculation test (DST edge case with `Date()` vs midnight-normalized dates).

Coverage check reveals **8 files below threshold** — a quality debt that needs attention.

### Product Designer Persona
_Background: 2yr each at MyFitnessPal, Whoop, MacroFactor, Strong, Boostcamp_

#### Competitive Landscape Update (April 2026)

| App | Moves Since Last Review |
|-----|------------------------|
| **MyFitnessPal** | New "Today" tab redesign (streaks, habits, cleaner macro display), GLP-1 medication tracking (dose, timing, injection site, reminders), AI photo meal logging rolled out to all iOS users, dietitian-reviewed "Blue Check" recipe collection |
| **Boostcamp** | Muscle volume tracking (hit/neglect by group), auto-progression math, free tier still includes core tracking + most programs |
| **Whoop** | Behavior Insights matured (connect habits→Recovery, 5+ yes/no threshold, 90-day analysis), new Trend Views (weekly/monthly/6-month), major heart rate algorithm overhaul (Feb 2026), Passive MSK for strength strain — auto-estimates musculoskeletal load from wrist motion |
| **MacroFactor** | Launched **separate** MacroFactor Workouts app, expenditure modifier (step-informed + goal-based), AI food logging improvements, $5.99-11.99/mo pricing |
| **Strong** | Templates search, measurement widgets, exercise renaming, simple timers. Staying minimal. $4.99/mo. |

#### Drift Strengths (Updated)
1. **AI chat remains unique.** MFP's ChatGPT integration is cloud-based and limited to recipes/Q&A. Drift logs food, starts workouts, queries cross-domain data — all locally. No competitor matches this.
2. **Cross-domain in one app.** MacroFactor just *split* into two separate apps (nutrition + workouts). We do food + weight + exercise + sleep + supplements + glucose + biomarkers + body comp + cycle tracking in one. That's our moat.
3. **Privacy.** MFP sends photos to cloud AI. Whoop uploads labs. MacroFactor requires an account. Drift: zero cloud. In post-DOGE surveillance anxiety, this matters more than ever.
4. **Adaptive TDEE shipped.** We now match MacroFactor's marquee feature. Our implementation uses EMA smoothing on actual weight trend data — the same algorithmic approach, running entirely on-device.
5. **Behavior insights shipped.** Basic v1 matches Whoop's concept — correlating behaviors with outcomes.

#### Drift Gaps (Updated)
1. **UI polish — now the #1 gap.** MFP redesigned their Today tab with streaks, habits, and cleaner layout. Our dashboard works but looks dated by comparison. This is the most visible gap to new users.
2. **Test coverage debt.** 8 files below threshold. AIToolAgent at 0%, IntentClassifier at 36% — these are core AI paths. Shipping features without coverage is accumulating risk.
3. **Food DB breadth.** Still ~1004 vs 14M+. MFP added AI photo logging which further leverages their massive DB. Our AI chat compensates (flexible parsing) but the long tail is missing.
4. **Behavior insights depth.** Whoop's implementation is more sophisticated: 90-day analysis, 5+ data point threshold, calendar visualization of behavior patterns. Our v1 is simpler — 14-day window, 3 hardcoded insights.
5. **Photo food logging.** Now shipping on MFP for all iOS users. Becoming table stakes. We still have no photo input.
6. **GLP-1/medication tracking.** New category MFP is pursuing. Niche but growing market (40M+ Americans on GLP-1s).

#### New Ideas
1. **Dashboard redesign inspired by MFP's Today tab.** Streaks, progress rings, better hierarchy. Scannable at a glance. This is the highest-impact visual change we can make.
2. **Behavior insights v2** — Add sleep duration vs recovery correlation (our 4th insight). Extend window from 14→30 days. Add streak visualization like Whoop's calendar view.
3. **Medication/supplement schedule** — We already track supplements. Adding dose timing, reminders, and adherence streaks would compete with MFP's GLP-1 feature while leveraging existing supplement infrastructure.
4. **Voice input** — iOS SpeechRecognizer → pipe to AI chat. Higher ROI than photo since it leverages our existing pipeline. Still the best Phase 4 pull-forward candidate.

#### Proposed Roadmap Changes
- Mark **LB/KG unit switching** and **Adaptive TDEE** as DONE in roadmap
- Mark **Behavior Insights v1** as DONE, add v2 (sleep correlation, 30-day window, streaks) to Next
- **Elevate UI/Dashboard work** — this is now the highest priority gap. Competitors are redesigning.
- **Add coverage recovery** as explicit Quality Now item — 8 files below threshold is unacceptable for core AI code
- Add **medication/supplement scheduling** to Later (monitoring MFP's GLP-1 play)

---

### Principal Engineer Persona
_Background: 10yr each at Amazon and Google_

#### Assessment

**Execution since Review #1: excellent.** Shipped 3 major features in ~5 cycles. The adaptive TDEE implementation is clean — EMA smoothing, safety ramp-up, dampening factor. The behavior insights are appropriately scoped. LB/KG fix addressed the root pattern, not just the symptom.

**Coverage debt is the top technical concern.** 8 files below threshold:

| File | Coverage | Target | Risk |
|------|----------|--------|------|
| AIToolAgent | 0% | 50% | **Critical** — orchestrates entire AI pipeline |
| SupplementService | 10.20% | 50% | Medium — simple CRUD |
| ExerciseService | 15.33% | 50% | Medium — workout operations |
| AIRuleEngine | 25.37% | 50% | High — core AI routing |
| FoodService | 30.03% | 50% | High — primary logging path |
| IntentClassifier | 36.00% | 80% | **Critical** — AI entry point |
| AIResponseCleaner | 72.68% | 80% | Low — close to target |
| CycleCalculations | 76.60% | 80% | Low — close to target |

AIToolAgent at 0% and IntentClassifier at 36% are concerning. These are the brain of the AI pipeline. Any refactor (like the state machine) without test coverage is playing with fire.

**Agree: Dashboard/UI redesign → top priority.** But scope it carefully. A "theme overhaul touching every view" in one cycle is risky without snapshot tests. Recommendation: start with dashboard-only redesign (highest user impact), then propagate the design language outward. Ship → get TestFlight feedback → iterate.

**Push back: Behavior insights v2 now.** The v1 shipped and works. Expanding to 30-day windows and calendar visualizations is feature creep when we have 8 files below coverage threshold and zero UI polish shipped. The v1 insights are fine. Revisit after coverage and UI are addressed.

**Push back: Medication scheduling.** MFP has millions of GLP-1 users — it's a scale play. We have one beta tester. Don't chase competitor features for markets we're not in. Our supplement tracking is sufficient.

**Agree: Voice input remains the best Phase 4 candidate.** SpeechRecognizer pipes directly into existing chat. Low architectural cost, high usability gain. But it's Phase 4, not 3c.

#### Sequencing Recommendation
1. **Coverage recovery** — Write tests for AIToolAgent, IntentClassifier, FoodService, AIRuleEngine. This unblocks safe refactoring.
2. **Dashboard redesign** — New information hierarchy, progress indicators, cleaner layout. One view, done well.
3. **State machine refactor** — Only after AIToolAgent/IntentClassifier have coverage. This is the most impactful AI architecture improvement.
4. **Chat UI polish** — Typing indicators, message bubbles, streaming UX. Visual layer only.
5. **Food DB enrichment** — Ongoing background task, not a blocking priority.

#### Technical Notes
- `state.md` numbers are stale (Build 87, 729 tests). Should be updated to reflect actual counts.
- The `Preferences.*` stale capture audit should continue — WeightViewModel was fixed but other view models likely have the same pattern.
- Consider adding a `@Preference` property wrapper that auto-refreshes from UserDefaults — would eliminate the entire class of stale preference bugs.

---

### Consensus & Roadmap Updates

Both personas agree:
1. **Mark LB/KG, Adaptive TDEE, Behavior Insights v1 as DONE** in roadmap
2. **Coverage recovery is the #1 technical priority** — 8 files below threshold, 2 critical (AIToolAgent 0%, IntentClassifier 36%)
3. **Dashboard redesign is the #1 product priority** — competitors are redesigning, this is the most visible gap
4. **Sequence: coverage → dashboard → state machine → chat UI** — tests first, then safe to refactor
5. **Behavior insights v2 deferred** — v1 is sufficient, revisit after coverage and UI
6. **Medication scheduling → Later** — monitoring MFP but not chasing their market
7. **Voice input stays Phase 4** — confirmed as best input expansion candidate
8. **Update state.md** with current test count, build number

---

## Review #3 — 2026-04-12 (Cycle 93)

### Progress Since Review #2

Since the last review (cycle 68→93 = 25 cycles), the focus has been **code quality improvement** — systematic refactoring of the largest, most complex files in the codebase:

**Code-improvement cycles completed (13 refactoring units):**
- **WorkoutView.swift** — 4 extractions: ActiveWorkoutView (737 lines), ExercisePickerView (194), WorkoutDetailView (142), CreateTemplateView (190). File went from 2067→800 lines.
- **HealthKitService.swift** — Extracted cycle tracking (270 lines) to extension. 
- **FoodTabView.swift** — 2 extractions: PlantPointsCardView (187), EditFoodEntrySheet (250). File went from 891→765 lines.
- **AppDatabase.swift** — Extracted food usage tracking (201 lines) to extension.
- **FoodSearchView.swift** — Extracted ManualFoodEntrySheet (136 lines). Reduced @State vars from 25→16.
- **AIChatView.swift** — Extracted suggestions/insight/fallbacks (178 lines) to extension.
- **AIContextBuilder.swift** — Extracted 5 health contexts (154 lines) to extension.
- **DashboardView.swift** — Extracted TDEE + calorie balance cards (276 lines) to extension.
- **LabReportOCR.swift** — Extracted biomarker extraction + aliases (300 lines) to extension.
- **AIChatView.swift** — In progress: extracting 620+ lines of message handling (sendMessage + 13 intent handlers) to AIChatView+MessageHandling.swift. File going from 836→214 lines.

**Net effect:** ~3,200 lines moved from monolithic files into focused, single-responsibility extensions. Largest files reduced by 40-60%. No behavior changes — all refactoring-only.

No new features shipped in this window (by design — code-improvement mode).

### Product Designer Persona
_Background: 2yr each at MyFitnessPal, Whoop, MacroFactor, Strong, Boostcamp_

#### Competitive Landscape (April 2026)

| App | Latest Moves |
|-----|-------------|
| **MyFitnessPal** | **Acquired Cal AI** (March 2026) — the viral teen-built calorie app. AI Meal Scan photo logging now on all iOS (Premium+). New Today screen with streaks/habits. GLP-1 medication tracking (dose, timing, reminders). Instacart integration for meal planning. Pricing: Premium $79.99/yr, Premium+ $99.99/yr. |
| **Whoop** | **Women's health push** — specialized female blood biomarker panel (11 markers), hormonal symptom insights with cycle predictions. Heart rate algorithm overhaul (Feb 2026). Strength training trend views. Pricing: $199-239/yr (hardware included). |
| **Boostcamp** | Bodyweight tracker, muscle engagement visualization per program, workout notes. AI program creation. Core tracking still free. Focused on strength programming niche. |
| **Strong** | v6.1.11 (March 2026): templates search, measurement widgets, exercise renaming, simple timers. Muscle heat map added. Still the minimalist gold standard. $4.99/mo. |
| **MacroFactor** | Launched **MacroFactor Workouts** as separate app. Favorites feature for staple foods. Upcoming: Apple Health integration, Live Activities for lock screen workout data, photo/text recipe upload. |

#### Key Industry Trends
1. **AI consolidation** — MFP acquiring Cal AI signals that AI food logging is becoming table stakes, not a differentiator by itself. The differentiator is now *how well* the AI integrates with your data.
2. **App splitting vs unification** — MacroFactor split into two apps (nutrition + workouts). MFP stays unified but bloated. Drift's single-app approach is a strength *if* the UI doesn't feel overwhelming.
3. **Women's health** — Whoop's female biomarker panel is a new category. We have cycle tracking but no biomarker correlation.
4. **Hardware bundling** — Whoop includes hardware in subscription. Strong and MFP are pure software. We're pure software — no hardware dependency is an advantage for distribution.

#### Drift Strengths (Updated)
1. **AI chat still unique and expanding.** MFP bought Cal AI for photo scanning; their chat is still cloud-based recipe Q&A. Drift's on-device AI does food logging, workouts, cross-domain queries — no competitor matches this breadth locally.
2. **Code quality investment paying off.** 13 refactoring cycles means the codebase is now significantly more maintainable. WorkoutView went from a 2067-line monolith to 5 focused files. This makes future feature work faster and safer.
3. **Single unified app.** MacroFactor just split into two apps. We cover 9 health domains in one app. That's a genuine UX advantage — users don't context-switch between apps.
4. **Privacy moat widening.** MFP sends photos to cloud, acquired a company that processes food photos server-side. Whoop uploads lab results. Drift: everything on-device. As AI regulation tightens, this becomes more valuable.

#### Drift Gaps (Updated)
1. **UI polish remains the #1 product gap.** Review #2 flagged this. Still not addressed. MFP redesigned their Today tab. Strong's muscle heat map is beautiful. Our dashboard and chat UI are functional but not polished. Every cycle that passes without UI work increases this gap.
2. **Coverage debt still blocking.** Review #2 flagged 8 files below threshold. The code-improvement cycles improved structure but didn't add tests. AIToolAgent is still at 0% coverage. This blocks the state machine refactor which is the most impactful AI architecture improvement.
3. **Food DB breadth.** ~1004 foods vs MFP's growing DB (now with Cal AI's data). Our AI chat compensates but the search-first flow suffers.
4. **No photo input.** MFP rolled out AI Meal Scan to all Premium+ users. Cal AI acquisition signals doubling down. We have zero photo capability.
5. **Women's health gap opening.** Whoop added female biomarker panels and hormonal insights. We have basic cycle tracking but no biomarker-cycle correlation.

#### New Ideas
1. **Cycle-biomarker correlation** — We have both cycle tracking AND biomarker tracking. Correlating menstrual cycle phase with iron, vitamin D, and other biomarkers is a unique cross-domain insight no competitor offers (Whoop's panel is separate from their cycle tracking). Low effort: query existing data, display correlation card.
2. **Live Activities for meal tracking** — MacroFactor is adding lock screen widgets for workouts. We could show remaining macros/calories on the lock screen. iOS Dynamic Island during active workout. High visibility, moderate effort.
3. **"Smart search" for food DB** — Instead of growing the DB to 14M entries, invest in smarter search: fuzzy matching, common misspellings, LLM-assisted food estimation ("a plate of biryani" → estimate from known ingredients). Leverage AI to compensate for DB size.

#### Proposed Roadmap Changes
- **Elevate dashboard redesign urgency** — flagged in Reviews #1 and #2, still not shipped. This is now overdue.
- **Add cycle-biomarker correlation** to Biomarkers Next section
- **Add Live Activities** to UI Next section
- Move **prompt consolidation** higher in AI Chat Now — token efficiency matters as context window is tight (2048 tokens)

---

### Principal Engineer Persona
_Background: 10yr each at Amazon and Google_

#### Assessment of Code Quality Investment

The 13 refactoring cycles were **well-executed and valuable.** Specific wins:
- WorkoutView decomposition (2067→800 lines across 5 files) follows the SwiftUI best practice of small, focused views
- Extension pattern (+Suggestions, +Health, +Biomarkers, +MessageHandling) is idiomatic Swift and consistent across the codebase
- No behavior changes — clean refactoring with build verification at each step

**However, the refactoring focused on file size, not the architectural issues flagged in Review #2.** The biggest technical debts were:
1. AIToolAgent at 0% test coverage → still 0%
2. State machine refactor for chat → still not done (blocked by #1)
3. Stale preference pattern audit → partially done (WeightViewModel fixed, others unknown)

The code-improvement loop has been doing "outer" refactoring (extract subviews, split files) when the "inner" refactoring (test coverage, state management, architectural patterns) is more urgently needed.

#### Assessment of Designer's Proposals

**Agree: Dashboard redesign is overdue.** This was flagged as #1 product priority in Review #2. Three reviews in a row saying "dashboard needs work" means it's time to actually do it. The code quality investment means the dashboard code is now cleaner (DashboardView+Cards extraction), making the redesign easier.

**Agree: Prompt consolidation should be elevated.** With 2048 token context and 1776 max prompt, every wasted token hurts response quality. A single pass to audit and compress the prompt could improve AI quality more than any feature addition.

**Push back: Cycle-biomarker correlation now.** This is a niche feature. How many beta testers track both cycles and biomarkers? Build the correlation engine when there's user data to validate it. Log the idea, don't prioritize it.

**Push back: Live Activities now.** Dynamic Island and lock screen widgets require WidgetKit extensions, App Groups for shared data, and careful state management. This is a Phase 4+ feature, not Phase 3c. The ROI doesn't justify the architectural complexity during a polish phase.

**Push back: "Smart search" for food DB.** We already have spell correction, fuzzy matching, and LLM-assisted normalization in the tiered pipeline. The food DB gap is about *data*, not search quality. Adding 500 common foods (top USDA items, popular restaurant meals) would close more of the gap than any algorithm improvement.

#### Technical Sustainability Check

Architecture remains sound. Specific observations:
- **AIChatView+MessageHandling extraction (in progress)** is the right move — sendMessage() at 476 lines was the single worst Clean Code violation in the codebase. The 13 handler methods follow guard-and-return-early pattern correctly.
- **31,388 total Swift lines** is healthy for the feature set. The refactoring hasn't added bloat.
- **GRDB + SQLite** continues to be the right persistence choice. No migration pressure.
- **llama.cpp xcframework** is stable. Gemma 4 E2B is performing well as the large model.

**Concern: the code-improvement loop has diminishing returns on file decomposition.** The largest files are now 600-800 lines — reasonable for SwiftUI views with complex business logic. Further splitting risks creating too many small files with unclear ownership. The loop should shift focus to:
1. Test coverage for untested services
2. DDD violations (business logic in views)
3. Design pattern improvements (dependency injection, protocol abstractions)

#### Sequencing Recommendation (Updated)

Review #2's sequence was: coverage → dashboard → state machine → chat UI. This remains correct but with refinement:

1. **Finish AIChatView+MessageHandling extraction** (in progress, ~1 cycle)
2. **Coverage recovery sprint** — AIToolAgent, IntentClassifier, FoodService, AIRuleEngine. Target: all 8 files above threshold. (~4-6 cycles)
3. **Dashboard redesign** — New hierarchy, progress rings, cleaner macro display. Ship to TestFlight, get feedback. (~2-3 cycles)
4. **Prompt consolidation** — Audit token usage, compress system prompt, single source of truth for tool schemas. (~1-2 cycles)
5. **State machine refactor** — Replace scattered pending* state vars with proper conversation state machine. Now safe because AIToolAgent has tests. (~2-3 cycles)
6. **Chat UI polish** — Better bubbles, streaming UX, tool execution feedback. (~1-2 cycles)

---

### Consensus & Roadmap Updates

Both personas agree:
1. **Code quality investment was valuable** — 13 refactoring cycles, 3200+ lines reorganized, major files decomposed. Codebase is significantly more maintainable.
2. **Shift code-improvement focus** from file decomposition to test coverage, DDD violations, and architectural patterns. File sizes are now reasonable.
3. **Dashboard redesign is now 3-reviews overdue** — must be the next product priority after coverage recovery
4. **Coverage recovery remains the #1 technical priority** — still 8 files below threshold, still blocking state machine refactor
5. **Prompt consolidation elevated** — tight context window (2048 tokens) means every token matters. Audit and compress.
6. **Cycle-biomarker correlation → Later** — good idea but niche; wait for user data
7. **Live Activities → Phase 4** — architectural complexity doesn't fit Phase 3c
8. **Food DB: add common foods** over algorithmic improvements — the gap is data, not search quality
9. **Sequence: finish current extraction → coverage → dashboard → prompt consolidation → state machine → chat UI**

---

## Review #4 — 2026-04-12 (Cycle 105)

### Progress Since Review #3

Only 12 cycles since Review #3 (same day). Two code-improvement cycles completed:
1. **AIChatView.swift** — Extracted 476-line sendMessage() god function into AIChatView+MessageHandling.swift with 13 focused handler methods. File went from 836→214 lines. Committed.
2. **GoalView.swift** — Extracting profile card (155 lines of complex form bindings) to GoalView+Profile.swift. In progress.

**Critical observation:** Review #3 explicitly recommended "shift code-improvement focus from file decomposition to test coverage, DDD violations, and architectural patterns." The loop continued doing file decomposition anyway. This is because the code-improvement program's survey step ("pick the largest un-recently-touched file") naturally biases toward decomposition. The steering notes need to be updated to redirect this behavior.

No new features shipped. No competitive landscape changes (same day as Review #3).

### Product Designer Persona
_Background: 2yr each at MyFitnessPal, Whoop, MacroFactor, Strong, Boostcamp_

#### Assessment

Competitive landscape unchanged since Review #3 (same day). Key competitive facts remain:
- MFP acquired Cal AI, rolled out photo scanning to all Premium+ users
- Whoop added women's health biomarker panels
- MacroFactor split into two apps
- Strong added muscle heat map

**The product gap assessment from Review #3 stands unchanged.** Dashboard redesign remains the #1 product priority, flagged in 4 consecutive reviews now.

#### Observation: Code Quality vs User-Facing Progress

15 code-improvement cycles have now reorganized ~3,500+ lines. The codebase is cleaner. But from a user's perspective, zero visual changes have shipped since behavior insight cards (cycle ~68). The app looks identical to what it looked like 37 cycles ago.

This is the risk of extended code-improvement runs: invisible progress. The code is better *for developers*, but users see no difference. At some point, the next TestFlight update needs to show *something* visually new.

**Recommendation:** After finishing the current GoalView extraction, the code-improvement loop should end. Switch to the self-improvement program to tackle coverage recovery and dashboard redesign — work that produces both technical and visible progress.

### Principal Engineer Persona
_Background: 10yr each at Amazon and Google_

#### Assessment

**The code-improvement loop has reached its natural endpoint for file decomposition.**

File size survey after 15 refactoring cycles:
- Largest file: FoodTabView at 768 lines (already refactored twice)
- Next: ActiveWorkoutView 763, FoodSearchView 728
- Most files in the 500-650 range — healthy for SwiftUI views with charts and forms

Further file splits would be splitting 600-line files into 300+300 — marginal gains with increased navigation cost. The loop's directive was "find the worst violation, fix it, biggest wins first." The biggest wins from decomposition are done.

**The unfixed architectural issues are more urgent than further decomposition:**
1. **AIToolAgent: 0% test coverage** — flagged in Reviews #2, #3, and #4. This is the AI pipeline orchestrator. Zero tests for 4 reviews running. Unacceptable.
2. **State machine refactor** — AIChatView+MessageHandling now has 13 handler methods with complex state transitions (pendingMealName, pendingWorkoutLog, etc.). The extraction made the handlers visible, but the underlying state management is still scattered @State vars. This is the next high-impact refactoring, but it requires test coverage first.
3. **Dashboard redesign** — 4 reviews saying "do it." The code is ready (DashboardView was decomposed to 373 lines in cycle 9). The blocker isn't code quality — it's that the code-improvement loop can't do UI work (refactoring only, no behavior changes).

#### Recommendation: Update Code-Improvement Steering Notes

The code-improvement loop's `_Focus:_` directive should be changed from `ALL` to something like `"DDD violations and design patterns only — no more file splitting"`. Or better: set `_Override: STOP` and switch to the self-improvement program for the next phase of work.

#### Updated Sequencing (Refined)

1. **Finish GoalView+Profile extraction** (~this cycle)
2. **STOP code-improvement loop** — switch to self-improvement program
3. **Coverage recovery sprint** — AIToolAgent, IntentClassifier, FoodService, AIRuleEngine (~4-6 cycles in self-improvement mode)
4. **Dashboard redesign** — New hierarchy, better cards (~2-3 cycles)
5. **Prompt consolidation** (~1-2 cycles)
6. **State machine refactor** (~2-3 cycles, now safe with test coverage)

---

### Consensus & Roadmap Updates

Both personas agree:
1. **Code-improvement loop has reached diminishing returns on decomposition** — 15 cycles, ~3,500 lines reorganized, file sizes now healthy
2. **Stop code-improvement loop after GoalView extraction** — switch to self-improvement program for coverage + features
3. **Dashboard redesign is now 4-reviews overdue** — this MUST be in the next batch of work
4. **AIToolAgent at 0% coverage is now 4-reviews flagged** — the single most critical technical debt
5. **Update code-improvement steering notes** to prevent future decomposition-only drift
6. **No roadmap changes needed** — Review #3's updates are still current (same day)
7. **Next self-improvement sequence: coverage → dashboard → prompt consolidation → state machine**

---

## Review #5 — 2026-04-12 (Cycle 116)

### Progress Since Review #4

Since Review #4 (cycle 105→116 = 11 cycles), the code-improvement loop shifted focus per Review #4's recommendation. Steering notes updated to: `"DDD violations and design patterns only — NO more file splitting"`. Results:

1. **FoodSearchView** — Routed all 22 direct AppDatabase.shared calls through FoodService. Zero database imports remain in view.
2. **FoodTabView** — Routed 4 favorites-related DB calls through FoodService.
3. **EditFoodEntrySheet** — Routed 6 DB calls through FoodService (3 new FoodService methods: fetchFoodById, updateFoodEntryName, updateFoodEntryMacros). In progress at time of review.
4. **FoodService** — Grew from 11 to 19 methods as the DDD boundary for all food-domain database access.

**Net effect:** 32 direct AppDatabase calls eliminated from 3 view files. FoodService is now the proper DDD boundary for food domain. This is the architectural pattern improvement Review #4 requested (not file splitting).

No new features shipped. No coverage work done (still code-improvement mode).

### Product Designer Persona
_Background: 2yr each at MyFitnessPal, Whoop, MacroFactor, Strong, Boostcamp_

#### Competitive Landscape Update (April 2026)

| App | Moves Since Review #4 |
|-----|----------------------|
| **MyFitnessPal** | Winter 2026 release: redesigned **Today Screen** with weekly macro insights in new Progress Tab. Photo Upload meal logging (AI-powered) rolled out to all iOS. Improved Meal Planner with Recipes tab. Blue Check Collection (dietitian-reviewed). Instacart grocery integration. GLP-1 medication tracking. Premium $79.99/yr, Premium+ $99.99/yr. |
| **Whoop** | WHOOP 5.0 + WHOOP MG (medical-grade) hardware tiers. New signal processing algorithm for heart rate. **AI-powered coaching** from bloodwork + wearable data. Healthspan longevity feature connects biomarkers to Sleep/Strain/Fitness pillars. FDA-cleared ECG, Blood Pressure Insights. 600+ new hires (scaling aggressively). 65 biomarkers in Advanced Labs panel. |
| **Boostcamp** | 130+ expert programs, 1M+ lifters, 300M+ workouts. Auto-adjusting weights based on performance. No major 2026-specific announcements beyond steady growth. |
| **Strong** | xRM estimations (Brzycki/Epley), RPE tracking, updated calendar design, Apple Health integration (calories burned), Plate Calculator, improved superset mechanics, rebuilt share links. Still the minimalist gold standard for logging speed. |
| **MacroFactor** | **Live Activities coming** (lock screen workout data, Dynamic Island rest timer — "finishing touches" as of March 2026). Favorites feature for staple foods. Label scanner for nutrition labels. Step-informed expenditure modifier. Smart progression in Workouts app. Apple Health integration upcoming. $71.99/yr bundle. |

#### Key Industry Shifts Since Last Review
1. **AI coaching is becoming standard.** Whoop now offers AI-powered coaching that interprets bloodwork + wearable data and adapts recommendations. MFP has AI photo logging for all iOS. The bar for "AI in health apps" is rising — Drift's on-device chat is still unique but the gap narrows when competitors add cloud AI coaching.
2. **Live Activities / lock screen presence.** MacroFactor is shipping Live Activities for workouts. This puts your tracking data on the lock screen and Dynamic Island. For meal-tracking apps, showing remaining macros on the lock screen is becoming the next expected convenience.
3. **Healthspan / longevity framing.** Whoop is pivoting from "performance" to "healthspan" — connecting biomarkers to daily habits for longevity insights. This is a broader health narrative that resonates beyond athletes.

#### Drift Strengths (Updated)
1. **AI chat remains the strongest differentiator.** Whoop added AI coaching but it's cloud-based and limited to bloodwork interpretation. MFP's AI is photo scanning (cloud). Neither can do: "log 2 eggs and toast for breakfast, also add coffee" → parse, split, resolve, log — all locally. Drift's conversational AI for multi-domain tracking is still unmatched.
2. **DDD architectural investment.** The FoodService boundary means food views no longer touch the database directly. This is invisible to users but enables faster, safer feature development. When dashboard redesign happens, the clean data access layer will pay dividends.
3. **Cross-domain unification.** MacroFactor split into two apps. Whoop requires hardware. MFP is nutrition-only with add-on features. Drift covers 9 health domains in one app with no hardware dependency.
4. **Privacy moat continues widening.** Whoop's AI coaching sends bloodwork to cloud. MFP sends photos to cloud. Drift: everything on-device. Regulatory pressure on health data (HIPAA, EU AI Act) makes this more valuable over time.

#### Drift Gaps (Updated)
1. **Dashboard redesign — now 5 reviews flagged.** This is embarrassing. MFP shipped a redesigned Today Screen. Strong has a clean calendar. MacroFactor has widgets. Our dashboard has been "the #1 product priority" for 5 consecutive reviews and zero visual changes have shipped. This is the single most urgent product gap.
2. **Coverage debt — 5 reviews flagged.** AIToolAgent still at 0%. IntentClassifier at 36%. These block the state machine refactor. Every review flags this. It must happen.
3. **No lock screen presence.** MacroFactor is shipping Live Activities. We have no widgets or lock screen data. For a tracking app, being invisible outside the app is a missed opportunity.
4. **Food DB breadth.** ~1004 foods vs MFP's ever-growing DB + Cal AI acquisition + label scanner. Our AI compensates but the gap is real for search-first users.
5. **No AI coaching narrative.** Whoop frames their AI as "coaching" — personalized plans that adapt. Our AI is "logging assistant" + "query answerer." Reframing our AI as a "health coach" that proactively suggests based on cross-domain data would elevate the product narrative.

#### Proposed Roadmap Changes
- **STOP the code-improvement loop NOW.** DDD routing work is valuable but 5 consecutive reviews flagging dashboard and coverage means the loop is not addressing the highest-priority work. Switch to self-improvement.
- **Add "AI Health Coach" narrative** to AI Chat Later section — proactive suggestions based on cross-domain patterns (not just reactive Q&A).
- **Promote Live Activities** from Phase 4 to late Phase 3c — MacroFactor is about to ship this. Remaining macros on lock screen is high-visibility, moderate-effort.

---

### Principal Engineer Persona
_Background: 10yr each at Amazon and Google_

#### Assessment of DDD Routing Work

**The DDD work since Review #4 was correct and valuable.** Review #4 said "shift to DDD violations and design patterns." The loop did exactly that:
- 32 direct DB calls eliminated from 3 view files
- FoodService grew from 11→19 methods as proper domain boundary
- Pattern is clean: views call FoodService, FoodService calls AppDatabase
- No behavior changes — pure architectural improvement

This is the *right kind* of code quality work. It makes the food domain testable (you can mock FoodService), maintainable (change DB schema in one place), and consistent (all food access goes through one gateway).

**However: 5 reviews flagging the same 2 items (dashboard, coverage) without progress is a process failure.** The code-improvement loop *by design* cannot ship UI redesigns (refactoring only, no behavior changes). And it hasn't prioritized coverage work. The loop needs to either stop or explicitly add coverage as a focus area.

#### Assessment of Designer's Proposals

**Agree: Stop code-improvement loop.** The DDD routing work was the last high-value architectural improvement achievable in refactoring-only mode. Remaining DDD violations (WeightTabView 8 calls, DashboardView 5 calls, etc.) are smaller wins with diminishing returns. The highest-impact work now requires behavior changes: coverage tests, dashboard redesign, prompt consolidation.

**Push back: Live Activities in Phase 3c.** MacroFactor shipping Live Activities doesn't mean we need to rush it. Live Activities requires:
- WidgetKit extension target
- App Groups for shared data container
- ActivityKit configuration
- Separate extension build/test cycle
- XcodeGen configuration for new target

This is 3-5 cycles of infrastructure work that doesn't advance our core differentiators (AI chat, cross-domain tracking). Keep it in Phase 4 Next. Our competitive advantage isn't convenience features — it's intelligence.

**Push back: "AI Health Coach" reframing.** The narrative is appealing but the technical reality is: our LLM has a 2048-token context window. Proactive coaching requires: (1) background analysis of cross-domain data, (2) generating unprompted insights, (3) remembering user context across sessions. Items 2-3 are Phase 5 features (conversation memory, proactive triggering). We can add the vision to the roadmap but don't let narrative reframing create scope creep. The behavior insight cards on the dashboard already serve this purpose in a simpler way.

**Agree: Dashboard is now a blocking priority.** 5 reviews is beyond "overdue" — it's a systemic failure to prioritize. The code quality investment (DashboardView decomposed to 373 lines, DDD boundaries established) means the dashboard code is now *ready* for a redesign. No technical blockers remain. This should be cycle 1 of the next self-improvement run.

#### Technical Sustainability Check

Architecture is in good shape for Phase 3c completion:
- **FoodService DDD boundary** is the pattern to replicate for other domains (WeightService, WorkoutService already exist; ExerciseService, SupplementService could follow)
- **31,510 total Swift lines** — stable, no bloat from refactoring
- **File sizes healthy** — largest is 768 lines (FoodTabView), most files 500-650
- **GRDB + SQLite** — no migration pressure
- **llama.cpp** — stable, Gemma 4 E2B performing well

**Concern: the code-improvement loop's "DDD violations" focus could continue indefinitely.** There are 52+ remaining AppDatabase calls across 13 view files. Routing all of them through services is theoretically correct but practically diminishing returns. The 3 files done (FoodSearchView, FoodTabView, EditFoodEntrySheet) covered the most-touched food views. The remaining files (WeightTabView, DashboardView, BarcodeScannerView, etc.) have fewer calls and are less frequently edited. Don't let perfect DDD compliance prevent shipping user-facing work.

#### Sequencing Recommendation (Final)

This is the 5th time both personas agree on this sequence. It should not change again until items are completed:

1. **STOP code-improvement loop** — commit current EditFoodEntrySheet changes, update log
2. **Coverage recovery** — AIToolAgent, IntentClassifier, FoodService, AIRuleEngine. Get all 8 files above threshold. (~4-6 cycles)
3. **Dashboard redesign** — New hierarchy, progress indicators, macro display. Ship to TestFlight. (~2-3 cycles)
4. **Prompt consolidation** — Audit token usage, compress system prompt. (~1-2 cycles)
5. **State machine refactor** — Now safe with test coverage. (~2-3 cycles)

---

### Consensus & Roadmap Updates

Both personas agree:
1. **DDD routing work was correct and valuable** — 32 DB calls eliminated, FoodService is now a proper domain boundary. This was the right focus per Review #4's steering.
2. **STOP the code-improvement loop NOW** — 5 reviews flagging dashboard and coverage without progress. The loop cannot deliver the highest-priority work (UI redesign, coverage). Commit current work, switch to self-improvement.
3. **Dashboard redesign is 5-reviews overdue** — this is the #1 product priority and must be cycle 1 of the next self-improvement run
4. **AIToolAgent coverage is 5-reviews flagged at 0%** — the #1 technical priority
5. **Live Activities stays Phase 4** — infrastructure cost doesn't justify during polish phase
6. **"AI Health Coach" vision added to roadmap Later** — aspirational narrative, not Phase 3c scope
7. **Remaining DDD violations (52 calls across 13 files) are not blocking** — food domain is clean, other domains are lower priority. Address opportunistically, not as a dedicated sprint.
8. **Final sequencing: STOP loop → coverage → dashboard → prompt consolidation → state machine**

---

## Review #6 — 2026-04-12 (Cycle 126)

### Progress Since Review #5

10 cycles (116→126). Same day as Review #5. Code-improvement loop continued DDD routing despite Review #5's recommendation to stop:

1. **WeightTabView** — 8 AppDatabase calls → WeightServiceAPI (2 new methods: latestBodyComposition, saveBodyComposition). Also consolidated duplicate fetch calls.
2. **QuickAddView** — 5 AppDatabase calls → FoodService (3 new methods: fetchRecentFoods, fetchFoodsByCategory, saveRecipe). Removed stored `db` property. In progress at time of review.

**Cumulative DDD progress:** 45 direct DB calls eliminated from 5 view files. FoodService: 22 methods. WeightServiceAPI: 2 new methods.

No competitive landscape changes (same day). No new features. No coverage work.

### Product Designer Persona

**Assessment:** The DDD routing is correct architectural work, but this is now the 6th consecutive review flagging dashboard and coverage. The code-improvement loop is producing diminishing returns. Every additional view file routed through a service boundary is incremental improvement on an already-solid architecture, while the two highest-impact items (dashboard redesign, test coverage) remain untouched.

**Recommendation:** The code-improvement loop's steering notes say `_Override: CONTINUE` — this should be changed to `STOP`. The loop has done excellent work (45 DB calls eliminated, clean service boundaries for food and weight domains) but the marginal value of routing the remaining ~40 calls across 16 files is low compared to shipping a dashboard redesign or writing AIToolAgent tests.

### Principal Engineer Persona

**Assessment:** The DDD work continues to be technically sound. WeightServiceAPI now has body composition methods, FoodService has grown to 22 methods covering the entire food domain. The pattern is consistent and clean.

**However, this confirms Review #5's concern:** the DDD focus can continue indefinitely. There are still ~40 AppDatabase calls across 16 view files (DashboardView 5, AIChatView+Suggestions 5, BarcodeScannerView 4, etc.). At the current rate of ~5 calls per cycle, that's 8 more cycles of DDD routing — none of which produces user-visible improvement.

**The code-improvement loop cannot address the top priorities.** It's constrained to "no behavior changes" which means:
- Cannot write new tests (coverage recovery)
- Cannot redesign the dashboard (UI changes)
- Cannot consolidate prompts (behavioral change to AI)

The loop should stop. The remaining DDD violations are not blocking any feature work.

### Consensus

Both personas agree (reaffirming Review #5):
1. **Change `_Override: CONTINUE` to `_Override: STOP`** in code-improvement.md steering notes
2. **DDD work was valuable but is now complete enough** — food and weight domains are clean, remaining violations are low-priority
3. **Dashboard and coverage remain the top priorities** — now flagged in 6 consecutive reviews
4. **No roadmap changes** — Review #5's updates are still current
5. **Sequence unchanged: STOP → coverage → dashboard → prompt consolidation → state machine**

---

## Review #7 — 2026-04-12 (Cycle 136)

### Progress Since Review #6

10 cycles (126→136). Same day. Code-improvement loop continued DDD routing:

1. **AIChatView+Suggestions** — 5 AppDatabase calls → FoodService/GlucoseService/BiomarkerService. Added hasDataToday() and hasResults() helpers.
2. **BarcodeScannerView** — 4 AppDatabase calls → FoodService. Added fetchCachedBarcode() and cacheBarcodeProduct() methods. In progress at time of review.
3. **DashboardView** — 5 AppDatabase calls → WeightServiceAPI. Added saveWeightEntry() method.

**Cumulative DDD progress (all sessions):** 59 direct DB calls eliminated from 8 view files. FoodService: 24 methods. WeightServiceAPI: 3 new methods. GlucoseService: +1 method. BiomarkerService: +1 method.

### Both Personas — Joint Assessment

This is the 7th consecutive review. The competitive landscape is unchanged (same day as Reviews #5 and #6). The assessment is unchanged. The DDD routing work is technically correct but we are deep into diminishing returns territory.

**Remaining AppDatabase calls in views:** ~25 across 13 files, most with 1-3 calls each (SupplementsTabView 3, WorkoutView 3, FoodTabView 3, MoreTabView 2, plus 9 files with 1 call each). These are low-frequency, low-impact violations.

**The code-improvement loop has now produced 7 consecutive reviews all saying the same thing:**
1. Dashboard redesign is overdue (flagged since Review #2)
2. AIToolAgent coverage at 0% is critical (flagged since Review #2)
3. The loop should stop

The loop continues because `_Override: CONTINUE` in steering notes. The loop is functioning correctly per its instructions — it finds DDD violations and fixes them. But the highest-value work (coverage, dashboard) cannot be done in refactoring-only mode.

### Consensus

Reaffirming Reviews #5 and #6. No roadmap changes. No new recommendations. The same sequence applies:
**STOP loop → coverage → dashboard → prompt consolidation → state machine**

---

## Review #8 — 2026-04-12 (Cycle 146)

Same day as Reviews #5-7. Competitive landscape unchanged.

**Progress since Review #7 (10 cycles):** WorkoutView (3 calls → WorkoutService), SupplementsTabView (3 calls → SupplementService), FoodTabView (3 remaining calls → FoodService). 9 more DB calls eliminated. **Cumulative: 68 DB calls eliminated from 11 view files.**

**Remaining:** ~16 calls across 12 files, all with 1-2 calls each. These are the long tail — diminishing returns.

**Both personas:** Assessment unchanged for 4th consecutive review. DDD routing is near-complete. The loop should stop. Sequence: STOP → coverage → dashboard → prompt consolidation → state machine.

---

## Review #9 — 2026-04-12 (Cycle 160)

Same day as Reviews #5-8. Competitive landscape unchanged.

**Progress since Review #8 (14 cycles):** Batch of 7 view files routed through services (AIChatView+MessageHandling, GoalView, GoalView+Profile, TemplatePreviewSheet, CreateTemplateView, WeightInsightsView, PlantPointsCardView). Then tackled the final domain services: BiomarkerService (+8 CRUD methods), GlucoseService (+2 methods), new DEXAService (6 methods). Fixed BiomarkersTabView, LabReportUploadView, LabReportDetailView, BiomarkerDetailView, GlucoseTabView, DEXAOverviewView, DEXAEntryView, MoreTabView (food export). **Cumulative: ~83 DB calls eliminated from 18 view files. All domain services now have clean boundaries.**

**Remaining AppDatabase.shared calls in views:** ~1 (MoreTabView factory reset — cross-cutting system operation, not a domain concern). DDD routing is effectively complete.

### Both Personas — Joint Assessment

The DDD routing initiative is **done**. 83+ direct database calls have been eliminated from view files across 18 views, routed through 7 domain services (FoodService, WeightServiceAPI, WorkoutService, SupplementService, GlucoseService, BiomarkerService, DEXAService). The only remaining call is factory reset in MoreTabView, which is a legitimate cross-cutting concern.

**This is the correct stopping point for the code-improvement loop.** The architecture is now clean — views never touch the database directly, all access goes through typed service boundaries. Continuing the loop would find only cosmetic improvements.

**The same priorities from Reviews #5-8 remain the top items:**
1. **Coverage recovery (P0)** — AIToolAgent 0%, IntentClassifier 36%, AIRuleEngine 25%. Now flagged in 6+ consecutive reviews.
2. **Dashboard redesign** — The most visible gap vs competitors. Flagged since Review #2.
3. **Prompt consolidation** — Token budget is tight at 2048/1776.
4. **State machine refactor** — Requires AIToolAgent coverage first.

### Consensus

**The code-improvement loop should stop now.** DDD routing is complete. Roadmap unchanged. Sequence: **STOP → coverage → dashboard → prompt consolidation → state machine.**

---

## Review #10 — 2026-04-12 (Cycle 170)

Same day as Reviews #5-9. Competitive landscape unchanged.

**Progress since Review #9 (10 cycles):** Tests confirmed passing (729+). No new code changes — the loop surveyed remaining files (ActiveWorkoutView, CycleView, SleepRecoveryView) and found no DDD violations. Business logic extraction (e.g., saveWorkout's 70-line set construction) is possible but would be more invasive refactoring with diminishing returns.

**Both personas — Final assessment:** The code-improvement loop has achieved its goals:
- **83+ direct DB calls eliminated** from 18 view files
- **7 domain services** with clean boundaries (FoodService, WeightServiceAPI, WorkoutService, SupplementService, GlucoseService, BiomarkerService, DEXAService)
- **File decomposition complete** (15 cycles, 3500+ lines reorganized)
- **DDD routing complete** — only cross-cutting factory reset remains

This is the 6th consecutive review recommending STOP. The remaining code quality work (business logic extraction, DI improvements) is better done alongside feature work that needs those changes, not in a blanket refactoring loop.

**Final consensus: STOP the code-improvement loop. Next: coverage → dashboard → prompt consolidation → state machine.**
