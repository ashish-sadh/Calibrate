# Product Review Log

Periodic product + engineering reviews. Every 10 cycles of the self-improvement loop.

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
