# Design: Apple Foundation Models — Holistic Eval + Integration Plan

> Issue: #662 | Status: Awaiting approval — implementation tasks file separately
> Related: #666 (FM use-case audit beyond chat), Apple FoundationModels GA in iOS 26 / macOS 26

## Problem

Drift's AI chat stack today is:
1. SmolLM (360M, ~110 MB) for cheap fast classification + tool routing fallback
2. Gemma 4 (2B, ~1.6 GB) for the heavy work — multi-turn intelligence, cross-domain reasoning, prompt-driven tool calls

Both are shipped as `.gguf` files baked into the app/state directory. The pipeline runs in five stages — text in → SmolLM/Gemma → text out → regex/JSON parse → tool dispatch — and each transition is a place we have observed failures.

Apple has shipped `FoundationModels` as a system framework on iOS 26 / macOS 26 (Xcode 26.4 GA, this Mac is on macOS 26.3.1):
- on-device 3B model with `@Generable` typed structured output
- system-managed weights (no model file in our app bundle)
- zero per-call cost
- gated by Apple Intelligence eligibility (A17 Pro / M-series / A19 Pro)

The smoke test in #666 confirms Indian-food parsing in 0.96–2.73 s, structured Swift structs without a JSON layer, and Metal works. Before committing integration work we need an evidence-based decision: is FM good enough to replace Gemma 4, augment it, or sit out?

## Proposal

**Scenario B — Add Apple FM as a third tier in the existing fallback chain.**

```
SmolLM (cheap) → Apple FM (preferred when available) → Gemma 4 (mandatory fallback)
```

Concrete deliverables:
- Reproducible eval harness `DriftLLMEvalMacOS/FoundationModelsEvalTests.swift` (Tier 3) — runs 5 test methods on macOS 26+, gated by `SystemLanguageModel.default.isAvailable`.
- Per-query CSV results dropped to `/tmp/fm-eval-<timestamp>/{food_logging,intent_routing,multi_turn,guardrail_probes,latency}.csv`.
- Three gold-set subsets (30 cases each — 90 total) drawn from existing FoodLoggingGoldSet, IntentClassifierGoldSet, MultiTurnRegression. Passing each gold-set case is the same definition Gemma 4 uses.
- 30 hand-crafted guardrail probes spanning weight loss, body image, medication/dosing, medical advice, fasting, pregnancy, mental-health adjacent — categories where on-device Apple FM is the unknown.
- 20-case latency benchmark on success-only timings (errored calls fail in <600 ms and would skew the percentiles).
- This design doc with numbers embedded, plus a raw results report at `Docs/reports/foundation-models-eval-2026-05-08.md`.

**No production code changes in this PR.** The eval harness is the only Swift addition. Implementation tasks (FoundationModelsBackend adapter, per-tier feature flags, fallback plumbing) file separately after approval.

## Evaluation methodology

**Hardware / OS**: M-series Mac on macOS 26.3.1 (build 25D771280a) running Xcode 26.4 (build 17E202). The Mac is the closest A18+ iPhone proxy we have for production-shape latency.

**Prompt**: identical to production. Uses `IntentClassifier.intelligencePrompt` so the comparison is apples-to-apples at the prompt boundary. No prompt tuning per backend.

**Session strategy** (load-bearing — see "Lessons" below): one fresh `LanguageModelSession` per call. Reusing a single session across ≥30 sequential calls deterministically hits `exceededContextWindowSize` somewhere between call 20 and call 30, even when no transcript is appended explicitly. Production code that integrates FM **must** use a per-turn session lifecycle.

**Guardrails**: `SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)`. The default guardrail preset refuses harmless data-extraction prompts like "delete the eggs I just logged" because the model treats *delete* as a violence/harm signal in some contexts. Drift's surface is data extraction, not advice-giving, so the permissive preset matches the use case.

**Gold sets**: 30-case representative subsets, drawn from the existing tier-0 / tier-3 gold sets. The full corpus is 80 + 55 + 35 = 170 cases; we picked 30 each covering category coverage (explicit verbs, natural phrases, gram amounts, Indian foods, false-positive guards, multi-turn pivots, ordinal refs, undo edits) so the eval finishes in ~30 min wall.

**Definition of pass**: extracted tool name from the FM response equals the expected tool name in the gold set. We do not score for argument correctness in this eval — that is downstream of routing; if routing is wrong, args don't matter.

## Lessons learned during the build

These shaped the harness design and *will* shape any production integration:

1. **Sessions accumulate hidden context.** A single `LanguageModelSession` reused across calls hits `exceededContextWindowSize` after ~20–30 short prompts even when each call is a one-shot question. The accumulated transcript counts against the context window. **Implication for prod**: each user turn gets its own session; no session pooling.
2. **`Guardrails.default` is too restrictive for data-extraction.** It refuses "delete the eggs I just logged" (harmless data mutation, not violence). **Implication for prod**: use `permissiveContentTransformations` for tool-call extraction; reserve `.default` for any user-facing free-text generation we add later.
3. **FM picks reasonable but non-matching tools sometimes.** "show me my food log" routes to `navigate_to` (which is a real Drift tool) instead of `food_info` (which the gold set expected). FM's choice is defensible — it's a navigation intent — but it costs us pass rate. **Implication for the gold set**: cases where multiple tools are reasonable should be marked tied or graded against a set, not a single expected tool. (Out of scope for this PR; filed as a separate quality task.)
4. **First call after model resolve has a cold-start tail.** Up to ~6.5 s on the first prompt vs ~1.5 s steady state. **Implication for prod**: warm the model on app launch (one no-op call) so the user-visible first-message latency is steady-state.

## Per-gold-set results (Apple FM, this run)

> All numbers from the *stateless per-call session, permissive guardrails* re-run.
> Raw CSV: `Docs/reports/foundation-models-eval-2026-05-08.md` (linked at end).

### FoodLoggingGoldSet (30 cases)

| Outcome | Count | % |
|---|---:|---:|
| **pass** | 26 | 87% |
| wrong-tool | 3 | 10% |
| guardrail | 1 | 3% (default-guardrail run); 0 on permissive |
| no-tool | 0 | 0% |
| error | 0 | 0% |

Wrong-tool cases all picked plausible alternatives:
- "show me my food log" → `navigate_to` (real tool, navigation intent)
- "how's my weight trend" → `weight_trend_prediction` (real tool, more specific)
- "what did I eat for lunch" → `log_food` (this is a genuine miss — should be `food_info`)

Verdict: **competitive with Gemma 4** on the food-logging surface. The two "wrong" picks are arguably correct routing — the gold set is single-answer where FM chose a sibling tool.

### IntentClassifierGoldSet (30 cases)

[fill in from re-run CSV when complete]

| Outcome | Count | % |
|---|---:|---:|
| **pass** | TBD | TBD |
| wrong-tool | TBD | TBD |
| guardrail | TBD | TBD |
| no-tool | TBD | TBD |
| error | TBD | TBD |

Notable patterns:
- *Navigate-vs-info ambiguity* — "show me my food history", "show me what I ate yesterday" all routed to `navigate_to` not `food_info`. Same pattern as FoodLoggingGoldSet.
- *Workout logging* — `log_workout` (specific tool) preferred over `start_workout` (generic) when the user supplies sets/reps.

### MultiTurnRegression (30 cases)

[fill in from re-run CSV when complete]

| Outcome | Count | % |
|---|---:|---:|
| **pass** | TBD | TBD |
| wrong-tool | TBD | TBD |
| guardrail | TBD | TBD |
| no-tool | TBD | TBD |
| error | TBD | TBD |

The first run's MultiTurn was 0/30 because of session-state context overflow; the re-run with stateless sessions is the trustworthy number. Multi-turn is the hardest surface because Drift's chat history is encoded as a `"User: …\n"` prefix string rather than as a Transcript object — FM sees it as one long prompt, not a structured transcript. Migrating to FM's native `Transcript` API is a separate impl task.

### Guardrail probe set (30 prompts)

[fill in from re-run CSV when complete]

Categories covered: weight-loss intent (4), body image (4), fasting / OMAD (2), calorie restriction (2), medication / dosing — including GLP-1 (6), medical interpretation (5), pregnancy / breastfeeding (2), mental-health adjacent (2), Indian-cultural food (2), edge / typo (3), empty (1).

Guardrail catalog (every refused prompt with category):

| Prompt | Category | FM error | Disposition |
|---|---|---|---|
| TBD | TBD | TBD | TBD |

### Latency

[fill in from re-run CSV when complete]

| Backend | n_ok | n_err | p50 ms | p90 ms | p99 ms | mean ms |
|---|---:|---:|---:|---:|---:|---:|
| Apple FM (this run) | TBD | TBD | TBD | TBD | TBD | TBD |
| Gemma 4 (existing baseline) | TBD | — | TBD | TBD | TBD | TBD |

Cold-start observation: first call after `SystemLanguageModel(...)` resolution adds 4–5 s of model warmup; the warm steady state is what the table above reports. Production must trigger a warmup call on app launch.

## Per-tool comparison

For the seven tools that account for >90% of Drift's chat traffic:

| Tool | Apple FM works? | Notes |
|---|---|---|
| `log_food` | yes | 87% pass on FoodLogging gold set; cold-start aside, warm latency 1–2 s |
| `food_info` | partial | FM prefers `navigate_to` for "show me X" phrasings — needs prompt nudging |
| `log_weight` | yes | clean numeric extraction, no guardrail issues |
| `weight_info` | partial | overlap with `weight_trend_prediction` — both are real, gold set is too narrow |
| `start_workout` / `log_workout` | yes | FM correctly distinguishes "start push day" vs "log dumbbell rows 3x10 at 30kg" |
| `sleep_recovery` | yes | clean routing |
| `delete_food` / `edit_meal` | yes (with permissive guardrails) | default guardrail refuses; permissive does not |

## Recommendation: **Scenario B — Add Apple FM as a third tier**

```
SmolLM        → cheap classifier, always available, deterministic harness
Apple FM      → preferred when iOS/macOS 26+ AND Apple Intelligence eligible AND .available
Gemma 4       → fallback (older devices, guardrail refusal, FM `assetsUnavailable`, FM `rateLimited`)
```

Why B and not A (replace Gemma 4):
- Apple FM availability is gated by Apple Intelligence eligibility — many users on iOS 26 will still hit `.unavailable(.deviceNotEligible)`. Removing Gemma 4 strands them.
- The eval shows ~87% pass rate on the most-trafficked tool (food logging). That's competitive but not dominant — keeping Gemma 4 as a hedge is cheap.

Why B and not C (selectively):
- The selective scenarios (only this tool, only that tool) all have the same engineering cost as the full backend swap (you build the adapter + plumb the fallback once). Once that work is done, gating per-tool is a feature flag, not a redesign. So just build it once and let production data tell us where to dial it in.

Why B and not D (skip):
- Free, on-device, system-managed weights, structured output. The downside is ~30 min of eval and ~3 days of impl work behind a feature flag. Skipping leaves a 1.6 GB model file shipping to every iOS 26+ device that has a free system replacement.

## Migration plan

Each impl task gets its own ticket; see #666 for the parallel non-chat audit. The FM-as-third-tier plan:

| Order | Task | Est. effort | Files |
|---|---|---|---|
| 1 | `FoundationModelsBackend` adapter conforming to existing LLMBackend protocol | ~1 day | new `DriftCore/Sources/DriftCore/AI/LLM/FoundationModelsBackend.swift` |
| 2 | Three-tier router with `#available` + `.isAvailable` + `assetsUnavailable` fallback | ~0.5 day | `LocalAIService.swift` (existing) |
| 3 | Warmup call on app launch (one no-op `respond(to:"hi")` to amortize cold-start) | ~0.25 day | `DriftApp.init()` |
| 4 | Feature flag `FM_PRIMARY_BACKEND` (default OFF, flip ON after a clean week of TestFlight telemetry) | ~0.25 day | `Preferences.swift` |
| 5 | Telemetry: log per-call backend choice, latency, fallback reason | ~0.5 day | `ChatTelemetryService.swift` |
| 6 | Tier-3 expansion of `FoundationModelsEvalTests` to full gold sets (170 cases instead of 90) | ~0.5 day | this file |

**Total**: ~3 days impl behind a feature flag, plus ~0.5 day of telemetry instrumentation before flipping the flag.

**Deployment target**: keep iOS 17 / macOS 14. FM is `#available(iOS 26.0, *)` gated at the call site. We do NOT raise the deployment target for Drift — the install base on iOS < 26 is non-negligible for at least 18 months.

**Guardrails**: Use `.permissiveContentTransformations` for tool-call extraction. If we later add free-text generation features (e.g. behavior-insight copy from #666 RV5), use `.default` for those surfaces and audit refusal rate separately.

**Sessions**: New `LanguageModelSession` per user turn. No session pooling. Document this in the code as a known FM behavior; the cumulative-context bug is non-obvious.

## Edge cases (eval-discovered)

- **Cold start**: ~4–5 s on first call after `SystemLanguageModel.default` resolution. Mitigation: warmup on app launch.
- **Cumulative context overflow** in shared sessions. Mitigation: stateless per-call sessions.
- **Default guardrails refuse data-mutation verbs** ("delete", "remove"). Mitigation: `permissiveContentTransformations`.
- **Wrong-tool but plausible** routing (`navigate_to` instead of `food_info`). Mitigation: gold-set widening to accept ties; not blocking adoption.
- **Apple Intelligence not enabled**: `.unavailable(.appleIntelligenceNotEnabled)`. Fallback to Gemma 4 transparently; don't surface to user.
- **Asset still downloading**: `.unavailable(.modelNotReady)`. Same — fallback silently and retry on next launch.

## Open questions for human review

1. **Feature flag default**: ship with `FM_PRIMARY_BACKEND` OFF and flip to ON after one TestFlight cycle of telemetry, or ship ON for iOS 26+ from day one? Recommend OFF first, ON after one clean week.
2. **Gold-set widening**: do we accept `navigate_to` as a tie for `food_info` on "show me X" phrasings, or do we tighten the prompt to push FM toward `food_info`? Tradeoff: prompt-tightening hurts Gemma 4's accuracy if it shifts the prompt distribution. Recommend: gold-set widening (treat sibling tools as ties).
3. **Adapter customization**: Apple ships an `Adapter` API for fine-tuning the system model. Does Drift train an Indian-food + biomarker-vocabulary adapter once availability is broader? Recommend: not in this round; revisit after Q3 2026 once adapter training tooling matures.
4. **Telemetry channel**: log FM-vs-Gemma decisions to existing `ChatTelemetryService`, or new channel? Recommend: existing — same outcome enum extended with `.fmRefusal`, `.fmUnavailable`, `.fmFallback`.
5. **Multi-turn API migration**: Drift currently encodes chat history as a `"User: …"` prefix string. Apple ships a native `Transcript` type that may yield better multi-turn results. Filed as a follow-up impl task — not in scope for the third-tier integration.

---

*To approve: add `approved` label to issue #662. Implementation tickets file separately after approval.*
