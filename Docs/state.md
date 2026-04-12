# Drift — Current State (April 2026)

## Overview
AI-first local health tracker. AI chat is the primary interface — every data entry doable through conversation. Traditional UI for visual analytics and fallback. No cloud, no accounts. Published on TestFlight as "Drift Fitness" (bundle: com.drift.health).

## Numbers
- **Version:** 0.1.0, Build 87
- **Tests:** 886 (19 test files, 300+ methods)
- **AI Eval:** 380+ scenarios in eval harness + LLM eval
- **Foods:** 1075 (Indian, Mexican, Asian, Mediterranean, Soups, global)
- **Exercises:** 873 (free-exercise-db)
- **Biomarkers:** 65 across 9 categories
- **AI Tools:** 19 registered tools
- **AI Chat Features:** 25+ (see `Docs/ai-parity.md`)

## Tech Stack
- SwiftUI + MVVM, iOS 17+, Swift 6
- GRDB.swift for SQLite (only SPM dependency)
- llama.cpp xcframework (rebuilt from source, Metal GPU)
- XcodeGen for project generation

## AI System — Tiered Pipeline

### Dual-Model
- **SmolLM2-360M Q8** (368MB) — 6GB devices. Rule-based harness.
- **Gemma 4 E2B Q4_K_M** (2900MB) — 8GB+ devices. Tiered pipeline with normalizer.

### Pipeline (Gemma 4)
```
Tier 0: Instant rules (StaticOverrides + Swift parsers)     → ~60-70% of queries
Tier 1: LLM normalizer → re-run rules (~3s)                 → ~20% more
Tier 2: Rule-based tool pick (ToolRanker, instant)           → ~10% more
Tier 3: Tool-first execution → stream presentation (~5-8s)   → info queries
Tier 4: Pure streaming with context (~10-20s)                → conversation
```

### Key Components
- **ToolRanker** — Keyword scoring, 19 tool profiles, `tryRulePick()`, `normalizePrompt()`
- **AIToolAgent** — Tiered orchestrator with 20s timeout on all LLM calls
- **StaticOverrides** — Universal deterministic handlers (no model gate)
- **Early JSON termination** — Bracket counting stops generation when JSON complete
- **Spell correction** — SpellCorrectService in findFood() search chain

### Backend
- Raw llama.cpp C API, Metal GPU (all layers offloaded, ~3GB VRAM)
- Auto-detect: RAM >= 6.5GB → Gemma 4, >= 5.0GB → SmolLM
- Auto-unload after 60s idle
- Context: 2048 tokens, max prompt: 1776, max generation: 256

## AI Chat Capabilities
- Food: log single/multi/meal/gram, nutrition lookup, calorie estimation, macro-specific, delete/undo, suggestions, copy to today
- Weight: log, trend, goal progress, set goal (word numbers), cross-domain analysis
- Exercise: start template, smart workout, log exercises, log activity, suggestion, workout history
- Health: sleep/recovery (weekly), supplements (status/mark/add), glucose, biomarkers, body comp
- Meta: TDEE/BMR, daily/weekly/yesterday summary, calories left, copy yesterday, topic continuation
- Multi-turn: meal continuation ("also add X"), history-based context, pronoun resolution
- Plant points: ingredient-based counting (57 composite dishes), spice blend expansion, barcode ingredients

## Tab Structure
Dashboard | Weight | Food | Exercise | More

## Apple Developer
- Team ID: ZJ5H5XH82A
- API Key: 623N7AD6BJ, Issuer: ad762446-bede-4bcd-9776-a3613c669447
- TestFlight: https://testflight.apple.com/join/NDxkRwRq
