# DriftChatSim

A macOS-hosted simulator that drives the **real** Drift chat pipeline
(`StaticOverrides` → `AIToolAgent` + real tools) against a **seeded sample DB**,
so we can run conversations from a terminal, see exactly where each turn routes,
and harden the harness fast — without an iOS build.

## Run

```bash
cd DriftCore
swift run DriftChatSim --once "how am I doing on calories today?"   # single turn
swift run DriftChatSim --repl                                       # interactive multi-turn
swift run DriftChatSim --script turns.json --json > trace.jsonl     # scripted / machine-readable
```

### Backend (`--backend nebius|local|auto`, default `auto`)
- **nebius** — set `NEBIUS_API_KEY` (+ optional `NEBIUS_MODEL_ID`). This is the
  production Coach experience.
- **local** — `~/drift-state/models/gemma-4-e2b-q4_k_m.gguf` (or `--model PATH` /
  `DRIFT_MODEL_PATH`). On-device dual-model path (SmolLM+rules do most routing).
- **auto** — Nebius if key present, else local, else deterministic-only
  (StaticOverrides + tools, no LLM).

### Other flags
`--screen dashboard|food|exercise|...` · `--no-seed` (resume existing DB) · `--json`

### REPL meta-commands
`:phase planningMeals:lunch:0` (stage `ConversationState` to reproduce multi-turn
bugs) · `:state` · `:reseed` · `:quit`

## What v1 covers — and the gap

**Covers:** `InputNormalizer` → `StaticOverrides.match` (Phase 1) →
`AIToolAgent.run` (Phase 8) + real tool execution + real DB reads/writes, with a
per-turn trace (input → normalize → static-override → route → tools+args → DB
before→after diff → response → conversation phase).

**Does NOT cover (yet):** the iOS-resident dispatch Phases 0.5–7 — multi-turn
pick handlers (`handlePendingMealPlan`), `handleFoodIntentParsing`,
clarifications, confirmations. They live in `AIChatViewModel`, not DriftCore, so
the bare-"1" meal-plan pick is **not reproducible end-to-end in v1**. Use
`:phase` to stage state and watch the trace show whether Phase 1 swallows the
input (the bug's mechanism).

## Roadmap

- **v1 (now):** agent-level sim, additive (package-only, zero iOS-target change).
- **v2 (post-launch):** extract the dispatch into a DriftCore `ChatEngine` that
  returns `[ChatEffect]` (append message / open sheet / set phase / speak …); the
  iOS ViewModel becomes a thin renderer. Makes the full dispatch (incl. bare-"1")
  reproducible **and** Tier-0 testable.
- **v3:** promote `--json` transcripts into gold-set regression fixtures
  (Tier-0 for deterministic routing, Tier-3 when LLM-backed).

> Seeding writes the host-local dev DB (`~/Library/Application Support/Drift/`),
> separate from the iOS app. `factoryReset()` gives a clean slate + reseeds foods.
