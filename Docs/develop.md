# Development Guide

> **The development workflow — module layout, building, the test tier map, AI
> eval, the chat simulator, and the feature checklist — lives in
> [`Docs/development-sop.md`](development-sop.md).** This file keeps only the
> setup notes unique to it.

## Prerequisites
- macOS with Xcode 16+, Swift 6.x
- `brew install xcodegen`
- Physical iPhone for real HealthKit testing
- Local LLM work: gguf models in `~/drift-state/models/`; cloud coach: Nebius key
  in `~/drift-state/nebius-key.txt`

## Quick Start
```bash
cd /Users/ashishsadh/workspace/Drift
xcodegen generate
xcodebuild build -project Drift.xcodeproj -scheme Drift \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
Where code goes (DriftCore vs the iOS app) and how to test it: see the SOP §0–§4.

## USDA FoodData Central API Key

`USDAFoodService` uses a free USDA API key for online food search. The default
`DEMO_KEY` is capped at 1,000 req/day — fine for development, a launch blocker at
scale.

**Register a key (2 min):**
1. Go to https://fdc.nal.usda.gov/api-guide.html and click "Get an API Key"
2. Enter your email — the key arrives immediately
3. Set it once at app startup (e.g. in `DriftApp.init()`):
   ```swift
   Preferences.usdaApiKey = "YOUR_KEY_HERE"
   ```

Stored in `UserDefaults`, persists across launches; `USDAFoodService` falls back
to `DEMO_KEY` only when the preference is empty. Registered keys: 3,600 req/hour.

## Dependencies
- **GRDB.swift** v7.x (SQLite) — primary external SPM dependency
- **ZIPFoundation** — backup archive zipping
- **llama.xcframework** — embedded, rebuilt from llama.cpp (Gemma 4, Qwen, SmolLM)
- Cloud coach runs on **Nebius AI Studio** (OpenAI-compatible); everything else is
  Apple-native
