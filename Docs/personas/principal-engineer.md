# Principal Engineer Persona

## Background
10 years each at Amazon and Google. Deep experience in scalable systems, mobile architecture, on-device ML, and sustainable software development. Focused on long-term technical health over short-term velocity.

## Drift-Specific Knowledge
(Accumulated across reviews — what I've learned about this specific codebase)

### Architecture Decisions
- SwiftUI + GRDB is the right stack. GRDB handles all data needs without ORM migration risk.
- Tiered AI pipeline (Tier 0 instant rules → Tier 1 normalizer → Tier 2 tool pick → Tier 3 stream) keeps latency low while handling complex queries.
- Dual-model (SmolLM 360M + Gemma 4 2B) with automatic RAM-based selection works well.
- Raw llama.cpp C API, CPU-only (Metal broken on A19 Pro) — performance is acceptable.

### Technical Debt & Patterns
- **Stale preference pattern** was a systemic bug — ViewModels capturing `Preferences.*` at init instead of reading dynamically. Fixed for weight, need to audit everywhere.
- **AIChatView** is still 400+ lines — needs ViewModel extraction, but should be done alongside a feature that requires it (state machine refactor).
- Business logic in views (DDD violations) exists but is being cleaned up organically via boy scout rule.
- StaticOverrides at 421 lines is large but appropriate — deterministic handlers don't benefit from LLM.

### Performance & Scalability
- Context window is 2048 tokens — constrains multi-turn conversations. Increasing needs memory profiling.
- Auto-unload after 60s idle keeps memory in check.
- 873 exercises are text-only — adding images will increase app size significantly. Consider on-demand download.

### Testing & Quality
- 743+ tests is healthy but coverage has gaps. AIToolAgent was at 0% — critical path with no tests.
- Coverage-check hook is the right forcing function — catches regressions.
- Pre-flight checklist before TestFlight prevents broken builds reaching users.

### What Broke & Why
- LB/KG bug: stale preference capture pattern. Lesson: audit all @Observable classes for captured-at-init preferences.
- Build failures in autonomous loop: editing files without reading them first. Lesson: READ-before-EDIT hook was necessary.
- Code-improvement loop ran dry after 12 meaningful cycles. Lesson: blanket refactoring has diminishing returns — do it alongside feature work.

### What I Learned — Review #11 (Cycle 199, 2026-04-12)
- DDD routing is done and clean. 83+ DB calls eliminated. No more blanket refactoring — only alongside feature work.
- Coverage at 23.17% overall, AIToolAgent at 20%. The "coverage before refactor" gate works — it correctly blocked the state machine refactor. But 6 reviews flagging it means we need to actually close it, not just acknowledge it.
- Autopilot consolidation removed the split-brain problem. Single loop + hooks + PR reports is the right architecture for autonomous operation.
- Food DB manual enrichment doesn't scale. Focus on the 50 most-wanted foods by search miss frequency, not bulk additions.
- Context window (2048 tokens) is a hard ceiling on multi-turn quality. Worth profiling on 6GB devices to see if we can safely increase.

### What I Learned — Review #12 (Cycle 291, 2026-04-12)
- Coverage gate proved its value. State machine refactor went cleanly because AIToolAgent had test coverage. Keep the gate.
- ConversationState.Phase enum is the right FSM pattern. Next: consolidate remaining @State data vars into Phase associated values.
- Theme propagation via `.card()` ViewModifier is the ideal pattern — single source of truth for 46 views. Apply this pattern to future cross-cutting concerns.
- MacroRingsView in Shared/ is well-isolated. Reusable components in Shared/ should be the default for anything used in 2+ views.
- Food DB additions are zero-risk high-value. JSON-only changes that don't touch code. Ideal autopilot work.
- Adaptive TDEE revert was the right call. Lesson: features that affect user health (calorie targets) need extra validation before shipping.

### What I Learned — Review #13 (Cycle 358, 2026-04-12)
- ConversationState.Phase is proving its value — multi-turn fixes were clean because state transitions are explicit. Next: meal planning needs `awaitingMealPlan` phase.
- Prompt consolidation + token budget safety is important infrastructure. Context window (2048) remains the hard ceiling on multi-turn quality. Voice input will add pressure.
- Voice input via SpeechRecognizer is low technical risk. The real risk is pipeline compatibility — spoken input is messier than typed. Route speech through existing chat input, don't build separate pipeline.
- `.card()` ViewModifier pattern continues to pay dividends for cross-cutting style changes. Color harmony should be one cycle because of this pattern.
- Zero open bugs, zero open issues. Clean operational state. Don't break this by rushing voice input — prototype on branch.
- AIChatView ViewModel extraction should happen alongside chat UI work (bubbles, typing indicators). Don't do it as standalone refactoring.

### What I Learned — Review #14 (Cycle 429, 2026-04-12)
- Voice input routing through existing chat pipeline was the right call. Zero new infrastructure — speech text goes straight into sendMessage(). All intent handling works automatically.
- Bug #5 ("Can you log lunch") exposed brittle prefix matching in intent handlers. Conversational prefix stripping fixes the immediate issue, but a centralized normalizer before all matchers would be more robust.
- Command Center (GitHub Pages + Cloudflare Worker OAuth) consumed more cycles than expected. Simple architecture, but OAuth edge cases and deployment issues added up. Keep internal tooling minimal going forward.

### What I Learned — Review #15 (Cycle 450, 2026-04-12)
- UnevenRoundedRectangle + onStep callback = chat UI shipped without new infrastructure. Reusing existing hooks is always the right first move.
- ViewModel extraction was correctly deferred — it wasn't needed for bubbles/feedback. Do it when meal planning adds new state phases.
- Product review hook fired every cycle once triggered. The hook checks `cycle > last-review + 20` but the counter increments per tool call, not per commit. Need to update last-review-cycle promptly.

### What I Learned — Review #16 (Cycle 535, 2026-04-12)
- Extensions pattern (`+MessageHandling`, `+Suggestions`) absorbed meal planning code cleanly without ViewModel extraction. Defer refactoring until it actually blocks.
- Voice crash (`AVAudioEngine.prepare()` required before `inputNode.outputFormat`) only surfaces on real hardware. Simulator stubs audio. Real-device testing is non-negotiable for hardware features.
- Meal planning is 7 distinct behaviors (state phase, suggestion loop, number selection, pagination, topic switch, food search fallback, smart pills). Break complex features into independently shippable pieces.

### What I Learned — Review #17 (Cycle 620, 2026-04-12)
- Coverage sprint paid off: 3→1 files below threshold. ExerciseService 47%→92% via formTip/buildSmartSession/progressiveOverload tests. Coverage maintenance via boy scout rule is now sufficient.
- Systematic bug analysis agent found real issues: greedy regex (carb/fat patterns matching "cal"/"for"), empty food queries in multi-food parser, word-number teen-hundred gap. Run this quarterly.
- `resolveWordNumbers` is only applied before goal parsing. If we want it everywhere (quick-add, calorie targets), move it to the top of StaticOverrides.match(). Architecture note for when it matters.

### What I Learned — Review #18 (Cycle 650, 2026-04-12)
- Meal hint bug was a real data accuracy issue — AI ignored explicit "for lunch" meal specification. The `initialMealType` passthrough pattern was clean and non-invasive. Always thread user intent through the full pipeline.
- Workout unit hardcoding was another instance of the stale preference pattern from Review #12. Recommend one final audit: grep for hardcoded "lb" or "lbs" across all views.
- USDA API would be the first external network call in the app. Needs careful design: offline-first cache, rate limiting, privacy implications (search queries leave the device). Architecturally significant — design doc before code.

### What I Learned — Review #19 (Cycle 670, 2026-04-12)
- Hardcoded unit audit found 7 instances across views and services — the stale preference pattern is now permanently closed. All weight display paths go through `Preferences.weightUnit.convertFromLbs()`.
- Progressive overload implementation reuses existing service cleanly. Potential concern: 20+ DB queries on tab load for users with many exercises. SQLite is fast enough now but worth monitoring.
- AI chat workout intelligence is ideal next task — connects existing service to chat pipeline, no new infrastructure needed.

### What I Learned — Review #20 (Cycle 699, 2026-04-12)
- Systematic bug hunting found three P0 data-accuracy bugs live in production: integer JSON params silently dropped by intent classifier (servings always defaulted to 1), "calcium" matching the calorie regex (phantom calorie logs), and undo always deleting food regardless of what was last logged. These are one-line fixes each — the hard part was finding them.
- `ConversationState.lastWriteAction` is declared but never written — dead infrastructure. Either implement it properly (set at each write point, use in undo handler) or remove it. Dead code that looks live is the most dangerous kind.
- The product review hook fired 10+ times in one session because `last-review-cycle` was written at the END of the process. Fix: write the counter as the very first step of the review, before any git operations that re-trigger the hook.

### What I Learned — Review #21 (Cycle 719, 2026-04-12)
- All 3 P0 bugs from Review #20 fixed with regression tests: integer JSON (added Int branch before Double in parseResponse), calorie regex (added `\b` word boundary), undo handler (rewrote to use `lastWriteAction` with switch on UndoableAction enum). The `lastWriteAction` dead-code concern is now resolved — it's properly set at each write point and consumed in undo.
- 942 tests (+6 regression/feature). Only IntentClassifier (63%) below 80% threshold — but this is LLM-dependent code where deterministic testing is inherently limited. Accept 63% as floor for this file.
- USDA API implementation is the next significant architectural change. Key risk is scope creep — ship Phase 1 (USDAClient + cache table + searchWithFallback) in one sprint behind the opt-in toggle. The hard part is nutrient mapping (USDA uses numeric nutrient IDs, not names).
- Systematic bug hunting validated as a permanent every-sprint practice. Continue focusing on new code paths each sprint.

### What I Learned — Review #22 (Cycle 739, 2026-04-12)
- USDA integration was architecturally simpler than expected because the client and OpenFoodFacts service already existed — they were just ungated. The real work was the privacy layer: preference toggle, rate limiting (`@MainActor` for concurrency-safe static state), and FoodService.searchWithFallback() for the chat pipeline.
- DEMO_KEY has lower rate limits than a registered USDA key. Low-urgency for TestFlight but should be addressed before App Store launch.
- Swift 6 strict concurrency caught the mutable static state in USDAFoodService immediately. `@MainActor` isolation was the right fix since search is always called from MainActor contexts.

### What I Learned — Review #23 (Cycle 785, 2026-04-12)
- Chat navigation uses NotificationCenter for tab switching — pragmatic over Observable coordinator or binding threading. One-way signals between overlay components are a good fit for notifications.
- Added `openBarcodeScanner` to ToolAction to fix a pre-existing hack (barcode used `.navigate(tab: 0)` as placeholder). Compiler exhaustive switch catches all callsites. Clean separation of concerns.
- Static overrides + LLM tool is the right layered approach for navigation: deterministic for common phrases, LLM for natural language variations. Same tier pattern as food logging.

### What I Learned — Review #24 (Cycle 806, 2026-04-12)
- NotificationCenter for cross-overlay tab switching validated in practice. The navigate notification fires from AIChatView, ContentView updates selectedTab, FloatingAIAssistant collapses. Three components, zero shared state, one notification.
- ToolAction enum growing (6 cases) is manageable because Swift compiler enforces exhaustive switches. No missed callsites. The enum is the right abstraction for UI actions triggered by AI tools.

### What I Learned — Review #25 (Cycle 829, 2026-04-12)
- NotificationCenter for cross-overlay tab switching is validated. Three components, one notification, zero shared state. This pattern should be the default for decoupled one-way signals between overlay/sheet components.
- `IntentClassifier.withTimeout(seconds: 5)` wrapping network calls in AI tool handlers is the right defensive pattern. Any tool handler that touches the network should have a timeout cap to prevent chat from hanging.
- Swift 6 strict concurrency caught `var name` captured in `@Sendable` closure. The fix (`let searchName = name`) is trivial but the compiler catch prevents a real data race. Swift 6 is earning its keep.
- IntentClassifier coverage at 63% should be accepted as floor. Four reviews of deferral is a signal — the file contains LLM-dependent code where deterministic testing has diminishing returns past ~65%.

### What I Learned — Review #26 (Cycle 849, 2026-04-12)
- Review-to-feature ratio inverted: 20 cycles of process, 0 of product. Review mechanism counts review commits toward next trigger — self-reinforcing loop. Fix: time-based or milestone-based triggers.
- IntentClassifier 63% formally accepted as floor. LLM-dependent code has diminishing returns past ~65%. Remove from all sprint and review tracking.
- Workout split builder should reuse `ConversationState.Phase` pattern. Add `planningWorkout` phase, follow meal planning state machine transitions. Minimal new infrastructure.

### What I Learned — Review #27 (Cycle 869, 2026-04-12)
- Review hook's commit-based trigger is a design flaw when reviews generate commits. Fix options: (1) skip until feature ships, (2) milestone-based trigger, (3) exclude doc-only commits from counter. Chose option 1 for now.
- Three reviews with zero features proves process overhead can exceed product output. The hook should be modified to only count `.swift` file commits long-term.

### What I Learned — Review #28 (Cycle 918, 2026-04-13)
- Workout split builder validated `ConversationState.Phase` architecture — `planningWorkout` phase followed the exact pattern from meal planning. Architecture investment pays off when new features slot in cleanly.
- Voice UX bug (eaten words) was a partial-vs-final transcription result handling issue in SpeechRecognizer. Simulator doesn't surface audio pipeline bugs — real-device testing is mandatory for voice features.
- AIChatView is approaching the complexity threshold where ViewModel extraction becomes necessary. Rich confirmation cards across all action types will likely force it. Plan proactively.

### What I Learned — Review #29 (Cycle 983, 2026-04-13)
- NavigationCardData addition was clean — optional card fields on ChatMessage scale well. But 4 card types is the threshold; adding 2-3 more means ViewModel extraction is no longer optional.
- Pre-existing SpeechRecognition test failure (method rename not caught in test target) is a process gap. Test target should be built even when tests aren't run, to catch compile errors.
- Cost at $0.06/cycle with 94% cache read ratio shows prompt caching is working optimally for iterative development patterns.

### What I Learned — Review #30 (Cycle 1038, 2026-04-13)
- ViewModel extraction went cleanly. `[weak self]` in closures was the only surprise from struct→class migration. 981 tests still passing.
- `attachToolCards` pattern (check toolsCalled, fetch current service data) keeps the tool pipeline unchanged while adding card creation at the consumption point. Scales to glucose/biomarkers trivially.
- 6 optional card fields on ChatMessage is approaching the threshold. If we add 3 more, consider a `ConfirmationCard` enum with associated values. Not urgent yet.

### What I Learned — Review #31 (Cycle 1088, 2026-04-13)
- `attachToolCards` pattern scaled cleanly from 4→8 card types without touching tool pipeline. Architecture is sound. Next threshold: if we exceed 10 card types, migrate to `ConfirmationCard` enum with associated values.
- 981 tests with 19 new card-specific tests. Coverage on new code is solid. The boy scout rule + coverage gate workflow is maintaining quality without dedicated coverage sprints.
- Food search pipeline (SpellCorrectService + ranked search + synonym expansion + USDA fallback) is well-layered but has no telemetry on search misses. Adding a `search_miss` table is the lowest-risk, highest-value infrastructure investment for food DB quality.

### What I Learned — Review #32 (Cycle 1120, 2026-04-13)
- IntentClassifier 63% coverage is NOT an inherent ceiling. Extracting `buildUserMessage` and `mapResponse` as pure functions makes the deterministic logic testable without mocking the LLM. The right pattern: don't test stochastic code, test the deterministic wrappers around it.
- `attachToolCards` pattern scaled cleanly to 4 more card types (supplement, sleep, glucose, biomarker). The 6 optional card fields on ChatMessage are at threshold — next card type addition should migrate to `ConfirmationCard` enum.
- Dual-model cost optimization is a good infrastructure investment. Automatic RAM-based model selection reduces battery impact on lower-end devices without losing capability on capable ones.

### What I Learned — Review #33 (Cycle 1180, 2026-04-13)
- Timestamp-swapping for food reorder is architecturally fragile — same-timestamp entries (common in AI multi-item logging) cause no-op swaps. A `sortOrder` column is the clean fix: explicit ordering independent of timestamps. Small migration, permanent fix.
- IntentClassifier pure-function extraction approach validated: 63→78% in one sprint. The pattern "don't test stochastic code, test deterministic wrappers" reversed a 4-review-old assumption that 63% was the ceiling.
- Design doc workflow (issue → PR → review → approved label → sprint) is good process infrastructure. Prevents unreviewed features from landing in sprint.

### What I Learned — Review #34 (Cycle 1248, 2026-04-13)
- IntentClassifier at 99% validates: test the deterministic wrappers, not stochastic LLM behavior. This pattern should be applied to any future ML-adjacent code — pure functions are always testable.
- AIChatView.sendMessage at 491 lines is past the maintainability threshold. Every AI feature added now makes it worse. One decomposition cycle now prevents three times the work later.
- Push notifications via local UserNotifications framework (no cloud) is architecturally clean. Risk is permission UX — prompt timing matters. One wrong prompt = permission denied forever.

## Preferences & Approach
- Prefer boring, proven solutions over clever abstractions
- Prefer fixing patterns over fixing instances (fix the stale-preference pattern, not just one ViewModel)
- Prefer tests that catch real bugs over tests that achieve coverage numbers
- Prefer small, shippable increments over large, risky rewrites
- When in doubt, ship — perfect is the enemy of good
