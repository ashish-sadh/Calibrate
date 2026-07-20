# Drift — Current State (May 2026)

## Overview
AI-first local health tracker. AI chat is the primary interface — every data entry doable through conversation. Traditional UI for visual analytics and fallback. No cloud, no accounts. Published on TestFlight as "Drift Fitness" (bundle: com.drift.health).

## Numbers
- **Version:** 0.1.0, Build 356
- **Tests:** ~1274 iOS DriftTests + ~1978 macOS DriftCoreTests (cross-platform pure-logic suite); LLM eval ~160+ cases in DriftLLMEvalMacOS
- **AI Eval:** 400+ scenarios in eval harness + LLM eval (~130-case gold set in IntentRoutingEval)
- **Per-tool Reliability (Gemma 4, 50-query gold set):** log_food 10/10 (100%), edit_meal 9/10 (90%, tuned +10% from 80%), log_weight 10/10 (100%), mark_supplement 10/10 (100%), food_info 9/10 (90%) — overall 48/50 (96%)
- **Foods:** 5,424 (curated down from 11,162 at build 237 — dropped verbose USDA SR Legacy bulk variants; hand-curated Indian-first + international cuisine retained. #1015/#1017 removed 36 duplicate rows, stripped 57 USDA distribution-program name suffixes, and de-title-cased 169 apostrophe names. Ceiling enforced at 6,000, cleanliness by FoodDBSizeTests.)
- **Exercises:** 960 (free-exercise-db)
- **Biomarkers:** 80 across 9 categories. Lab text-parser lives in DriftCore (`LabTextParser`, gold-set tested for accuracy); FM camelCase IDs canonicalized via `BiomarkerCatalogMap`. Indian-lab support (SGPT/SGOT, urea, ESR, Total T3/T4, VLDL). Personalized trends + multi-marker pattern synthesis via `BiomarkerInsights`. Body-comp lean-vs-fat decomposition + energy reconciliation via `BodyCompositionAnalysis`.
- **AI Tools:** 35 registered tools (23 core + 12 insight); 11 analytical insight engines (cross_domain_insight, goal_weight_eta (né weight_trend_prediction — renamed 2026-07-15, name magnetism), glp1_insight, supplement_insight, food_timing_insight, sleep_food_correlation, exercise_volume_summary, glucose_food_correlation, progressive_overload_check, glucose_spike_analysis, cycle_biomarker_correlation)
- **TTFT Benchmark:** ChatLatencyBenchmark (20 queries × 3 runs, 1.3× regression threshold, opt-in via DRIFT_LATENCY_BENCH=1) — 4 scenarios: single-item, multi-item (gates TTFT), confirmation-card (gates completion_ms), clarify-round-trip (gates turn1+turn2 total)
- **Hot-path Benchmark:** HotPathLatencyBench (same DRIFT_LATENCY_BENCH=1 gate) — year-scale DB (6k foods, ~4.4k entries), order-of-magnitude ceilings on Log press / Add Food sheet / dashboard insights / search dedupe; SOP §9 documents the once-in-a-while Xcode Organizer + Instruments checks
- **AI Chat Features:** 25+ (see `Docs/ai-parity.md`); Coach interview "set me up" → TrainingProfile → Qwen-generated weekly routine (equipment-filtered, grounded, offline fallback); "log my usual push day" replay; tappable quick-reply chips; ActiveWorkout command strip ("add face pulls" / "drop curls" / "last bench?")
- **Confirmation Cards:** 8 types (food, weight, workout, navigation, supplement, sleep, glucose, biomarker)

## Tech Stack
- SwiftUI + MVVM, iOS 17+, Swift 6
- GRDB.swift for SQLite (only SPM dependency)
- llama.cpp xcframework (rebuilt from source, Metal GPU)
- XcodeGen for project generation

## Module Layout

Post-DriftCore extraction (Apr 25, 2026, build 174; updated build 224):

- **`DriftCore/`** — Swift package, ~104 files, builds on iOS 17+ and macOS 14+. No `import UIKit/SwiftUI/HealthKit/WidgetKit/AVFoundation/Speech/Photos/AppIntents`.
  - `Models/` (28), `Persistence/` (5), `Adapters/` (4), `Utilities/` (5)
  - `Domain/{Food,Weight,Workout,Health}/` (27)
  - `AI/{Parsing,Classification,Tools,Pipeline,LLM}/` (36)
- **`Drift/`** — iOS app shell. Views, ViewModels, and iOS-bound services only: HealthKit, Widget, Notification, Speech, Photo, CloudVision, OCR.
- **Adapter seams**: `HealthDataProvider`, `WidgetRefresher` — wired in `DriftApp.init()` via `DriftPlatform.health = HealthKitService.shared` + `DriftPlatform.widget = WidgetCenterRefresher()`.

Test infrastructure: macOS-native `swift test` for pure logic (~0.1s warm), iOS simulator only for UI/HealthKit/Widget integration.

## AI System — Tiered Pipeline

### Dual-Model
- **SmolLM2-360M Q8** (368MB) — 6GB devices. Rule-based harness.
- **Gemma 4 E2B Q4_K_M** (2900MB) — 8GB+ devices. Tiered pipeline with normalizer.

### Pipeline (Gemma 4) — 6-Stage
```
Stage 0: Input normalization (InputNormalizer — filler, conjunctions, run-on)
Stage 1: Instant rules (StaticOverrides + Swift parsers)     → ~60-70% of queries
Stage 2: LLM intent classifier (typos, word numbers, tools)  → ~20% more
Stage 3: Domain-specific LLM extraction (food/weight/exercise params)
Stage 4: Tool execution → stream presentation (~5-8s)         → info queries
Stage 5: LLM fallback with context (~10-20s)                  → conversation
```

### Key Components
- **IntentClassifier** — LLM-based intent detection with structured JSON output
- **AIToolAgent** — 6-stage orchestrator with 20s timeout on all LLM calls; 34 registered tools (23 core + 11 insight) + 10 analytical engines
- **StaticOverrides** — Universal deterministic handlers (no model gate)
- **ConversationState** — State machine (idle/awaitingMealItems/awaitingExercises/planningMeals)
- **Early JSON termination** — Bracket counting stops generation when JSON complete
- **Spell correction** — SpellCorrectService + synonym expansion in food search chain

### Backend
- **Default chat backend: on-device llama.cpp/Gemma.** Apple Foundation Models is a user-selectable opt-in, NOT the default. The 2026-05-19 FM cutover was reverted by the #872 NO-GO (FM measured 80.5% overall / 75.0% critical vs the 92.7% Gemma baseline on the chat parity gate); existing FM-default users get a one-time on-device setup download on the build carrying the revert, and FM must re-clear the ≥95%/≥98% parity cutover gate before it can be re-promoted to default (#874).
- Raw llama.cpp C API, Metal GPU (all layers offloaded, ~3GB VRAM)
- Auto-detect: RAM >= 6.5GB → Gemma 4, >= 5.0GB → SmolLM
- Auto-unload after 60s idle
- Context: 2048 tokens, max prompt: 1776, max generation: 256

## AI Chat Capabilities
- Food: log single/multi/meal/gram, nutrition lookup, calorie estimation, macro-specific, delete/undo, suggestions, copy to today, meal planning dialogue
- Weight: log, trend, goal progress, set goal (word numbers), cross-domain analysis
- Exercise: start template, smart workout, log exercises, log activity, suggestion, workout history
- Health: sleep/recovery (weekly), supplements (status/mark/add), glucose, biomarkers, body comp, GLP-1 medication tracking (log_medication)
- Meta: TDEE/BMR, daily/weekly/yesterday summary, calories left, copy yesterday, topic continuation
- Multi-turn: meal continuation ("also add X"), meal planning iteration, history-based context, pronoun resolution
- Input: voice (on-device SpeechRecognizer), text, smart suggestion pills
- Confirmation cards: food (macros), weight (trend), workout (muscle groups), navigation, supplement (taken/remaining), sleep (HRV/recovery), glucose (avg/spikes/zone), biomarker (out-of-range)
- Plant points: ingredient-based counting (57 composite dishes), spice blend expansion, barcode ingredients

## Tab Structure
Today | Food | Workout | Body | More (floating Drift Coach bubble bottom-right)

## Apple Developer
- Team ID: ZJ5H5XH82A
- API Key: 623N7AD6BJ, Issuer: ad762446-bede-4bcd-9776-a3613c669447
- TestFlight: https://testflight.apple.com/join/NDxkRwRq
