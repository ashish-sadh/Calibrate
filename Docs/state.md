# Drift — Current State (April 2026)

## Overview
AI-first local health tracker. AI chat is the primary interface — every data entry doable through conversation. Traditional UI for visual analytics and fallback. No cloud, no accounts. Published on TestFlight as "Drift Fitness" (bundle: com.drift.health).

## Numbers
- **Version:** 0.1.0, Build 133
- **Tests:** 1677+ (38 test files; LLM eval expanded to ~160+ cases in DriftLLMEvalMacOS)
- **AI Eval:** 400+ scenarios in eval harness + LLM eval (~130-case gold set in IntentRoutingEval)
- **Per-tool Reliability (Gemma 4, 50-query gold set):** log_food 10/10 (100%), edit_meal 9/10 (90%, tuned +10% from 80%), log_weight 10/10 (100%), mark_supplement 10/10 (100%), food_info 9/10 (90%) — overall 48/50 (96%)
- **Foods:** 2,511 (Indian, Mexican, Asian, Thai, Japanese, Korean, Mediterranean, Chinese, Middle Eastern, American classics, fitness staples, coffee drinks, seeds, Indo-Chinese, sushi rolls, meal prep bowls, South Indian, Indian street food, bowls, Kerala dishes, fast food India, Indian fruits, Indian regional, Maharashtrian, Odia, Assamese, Bihari, Rajasthani, Andhra, Karnataka, Goan, Himachal Pradesh, Northeast India, Sindhi, Madhya Pradesh, Coorg, Vietnamese, Latin American, African, Italian expanded, branded protein bars/shakes, bakery, soups, seafood, Bengali fish, Indian snacks, Indian drinks, Filipino, Turkish, Ethiopian, fast food US, supplements, South Indian breakfasts, Karnataka snacks, regional protein shakes, bubble tea/boba, poke bowls, acai bowls, specialty coffee, sports nutrition)
- **Exercises:** 960 (free-exercise-db)
- **Biomarkers:** 65 across 9 categories
- **AI Tools:** 20 registered tools
- **TTFT Benchmark:** ChatLatencyBenchmark (20 queries × 3 runs, 1.3× regression threshold, opt-in via DRIFT_LATENCY_BENCH=1) — 4 scenarios: single-item, multi-item (gates TTFT), confirmation-card (gates completion_ms), clarify-round-trip (gates turn1+turn2 total)
- **AI Chat Features:** 25+ (see `Docs/ai-parity.md`)
- **Confirmation Cards:** 8 types (food, weight, workout, navigation, supplement, sleep, glucose, biomarker)

## Tech Stack
- SwiftUI + MVVM, iOS 17+, Swift 6
- GRDB.swift for SQLite (only SPM dependency)
- llama.cpp xcframework (rebuilt from source, Metal GPU)
- XcodeGen for project generation

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
- **AIToolAgent** — 6-stage orchestrator with 20s timeout on all LLM calls
- **StaticOverrides** — Universal deterministic handlers (no model gate)
- **ConversationState** — State machine (idle/awaitingMealItems/awaitingExercises/planningMeals)
- **Early JSON termination** — Bracket counting stops generation when JSON complete
- **Spell correction** — SpellCorrectService + synonym expansion in food search chain

### Backend
- Raw llama.cpp C API, Metal GPU (all layers offloaded, ~3GB VRAM)
- Auto-detect: RAM >= 6.5GB → Gemma 4, >= 5.0GB → SmolLM
- Auto-unload after 60s idle
- Context: 2048 tokens, max prompt: 1776, max generation: 256

## AI Chat Capabilities
- Food: log single/multi/meal/gram, nutrition lookup, calorie estimation, macro-specific, delete/undo, suggestions, copy to today, meal planning dialogue
- Weight: log, trend, goal progress, set goal (word numbers), cross-domain analysis
- Exercise: start template, smart workout, log exercises, log activity, suggestion, workout history
- Health: sleep/recovery (weekly), supplements (status/mark/add), glucose, biomarkers, body comp
- Meta: TDEE/BMR, daily/weekly/yesterday summary, calories left, copy yesterday, topic continuation
- Multi-turn: meal continuation ("also add X"), meal planning iteration, history-based context, pronoun resolution
- Input: voice (on-device SpeechRecognizer), text, smart suggestion pills
- Confirmation cards: food (macros), weight (trend), workout (muscle groups), navigation, supplement (taken/remaining), sleep (HRV/recovery), glucose (avg/spikes/zone), biomarker (out-of-range)
- Plant points: ingredient-based counting (57 composite dishes), spice blend expansion, barcode ingredients

## Tab Structure
Dashboard | Weight | Food | Exercise | More

## Apple Developer
- Team ID: ZJ5H5XH82A
- API Key: 623N7AD6BJ, Issuer: ad762446-bede-4bcd-9776-a3613c669447
- TestFlight: https://testflight.apple.com/join/NDxkRwRq
