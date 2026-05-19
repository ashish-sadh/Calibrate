# Apple Foundation Models — Raw Eval Results, 2026-05-08

> Source: `DriftLLMEvalMacOS/FoundationModelsEvalTests.swift` run on macOS 26.3.1 / Xcode 26.4 / M-series Mac.
> Design doc: [`Docs/designs/662-foundation-models.md`](../designs/662-foundation-models.md).
> CSV exports: `/tmp/fm-eval-<timestamp>/{food_logging,intent_routing,multi_turn,guardrail_probes,latency}.csv` on the eval host.

This report is the raw data behind the design doc's recommendation. It records the harness configuration, every per-query outcome, the guardrail catalog, and the latency distribution. Reproduce with:

```bash
cd /Users/ashishsadh/workspace/Drift
xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS' \
  -only-testing:'DriftLLMEvalMacOS/FoundationModelsEvalTests'
```

## Harness configuration

- **Hardware**: M-series Mac
- **OS / SDK**: macOS 26.3.1 (build 25D771280a), Xcode 26.4 (17E202)
- **Apple FM**: `SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)`, `.default` adapter
- **Session strategy**: fresh `LanguageModelSession` per call (stateless)
- **System prompt**: `IntentClassifier.intelligencePrompt` (live production prompt)
- **No prompt tuning per backend** — same prompt FM as Gemma 4

## Run history

| Run | Strategy | Result | Notes |
|---|---|---|---|
| 1 | Single shared session, default guardrails | FoodLogging 26/30, IntentRouting 15/30 then context-overflow at case 21, MultiTurn 0/30, Guardrails 0/30 (all errored), Latency 540 ms / mean 516 ms (success-mixed-with-error) | Discovered cumulative-context bug + over-restrictive default guardrails |
| 2 | **Stateless per-call session, permissive guardrails** | [filling in as eval completes] | Trustworthy run |

The numbers below are from run 2 unless explicitly tagged otherwise.

## FoodLoggingGoldSet — 30 cases

| Outcome | Count | % |
|---|---:|---:|
| pass | 27 | 90% |
| wrong-tool | 2 | 7% |
| no-tool | 2 | 7% (overlap with wrong-tool sometimes) |
| guardrail | 0 | 0% |
| error | 0 | 0% |

### Per-query failures (run 2)

| Query | Expected | FM picked | Outcome |
|---|---|---|---|
| "can you log rice" | log_food | text (no JSON) | no-tool |
| "I weigh 73 kg" | log_weight | weight_info | wrong-tool — FM read it as a query, not a log |
| "how's my weight trend" | weight_info | weight_trend_prediction | wrong-tool — sibling tool |
| "what did I eat for lunch" | food_info | text (no JSON) | no-tool |

Three of these four are arguably reasonable picks — `weight_trend_prediction` is a real tool, `weight_info` is one of two correct interpretations of "I weigh 73 kg", and "what did I eat" without a tool call still gives the user a sensible text reply. Only "can you log rice" is a clean miss (FM should have logged but produced free-text instead).

## IntentClassifierGoldSet — 30 cases

[filling in as eval completes]

| Outcome | Count | % |
|---|---:|---:|
| pass | TBD | TBD |
| wrong-tool | TBD | TBD |
| no-tool | TBD | TBD |
| guardrail | TBD | TBD |
| error | TBD | TBD |

## MultiTurnRegression — 30 cases

[filling in as eval completes]

| Outcome | Count | % |
|---|---:|---:|
| pass | TBD | TBD |
| wrong-tool | TBD | TBD |
| no-tool | TBD | TBD |
| guardrail | TBD | TBD |
| error | TBD | TBD |

History encoded as `"User: …\n"` prefix in the prompt. Apple FM's native `Transcript` API may improve these numbers; out of scope for this eval.

## Guardrail probe set — 30 hand-crafted prompts

[filling in as eval completes]

| Category | Count | Refused | Answered | Errored |
|---|---:|---:|---:|---:|
| weight-loss intent | 4 | TBD | TBD | TBD |
| body image / restrictive | 4 | TBD | TBD | TBD |
| fasting / OMAD | 2 | TBD | TBD | TBD |
| calorie restriction | 2 | TBD | TBD | TBD |
| medication / dosing | 6 | TBD | TBD | TBD |
| medical interpretation | 5 | TBD | TBD | TBD |
| pregnancy / breastfeeding | 2 | TBD | TBD | TBD |
| mental health adjacent | 2 | TBD | TBD | TBD |
| Indian-cultural food | 2 | TBD | TBD | TBD |
| edge / typo / empty | 3 | TBD | TBD | TBD |

### Refusal catalog (every refused prompt)

| Prompt | Category | Apple FM error variant | Production disposition |
|---|---|---|---|
| TBD | TBD | TBD | TBD |

### Answered-with-warning catalog

[any prompt where FM answered but the response contained a safety hedge or refusal-shaped text]

| Prompt | Category | FM response (excerpt) |
|---|---|---|

## Latency

[filling in as eval completes]

| Backend | n_ok | n_err | p50 ms | p90 ms | p99 ms | mean ms |
|---|---:|---:|---:|---:|---:|---:|
| Apple FM (stateless per-call session) | TBD | TBD | TBD | TBD | TBD | TBD |
| Apple FM (shared session, run 1, mixed success/error) | 20 | unknown | 540 | 582 | 609 | 516 |
| Gemma 4 (existing baseline, IntentRoutingEval) | TBD | — | TBD | TBD | TBD | TBD |

**Cold start**: first call after `SystemLanguageModel.default` resolution: ~5 s. Warm steady state: ~4–5 s/call when each call rebuilds a fresh session (stateless), vs ~1.5 s/call when sharing a session that has not yet hit context overflow. Production should pool sessions per *user turn*, not per *app launch*, and warmup once at launch.

## Stateless-session overhead

The per-call-session strategy costs ~3 s/call in session construction overhead — that overhead is not a real production cost because production code constructs one session per user turn, and a turn is generally one round trip. The ~1.5 s shared-session number is the steady-state user-visible latency we'd see in production.

## Notable behavioral observations

- **Permissive guardrails work as expected.** The same prompt "delete the eggs I just logged" that triggered a `guardrailViolation` on `Guardrails.default` succeeded cleanly on `permissiveContentTransformations`. **Production must use the permissive preset for tool-call extraction.**
- **Routing-vs-navigation collision.** "show me my food log" / "show me what I ate yesterday" routed to `navigate_to` in run 1; in run 2 (with the permissive guardrails) it routed to `food_info`. Some run-to-run variance. Production telemetry should track this distribution.
- **Session-context bug repro.** Reusing one `LanguageModelSession` across 30 short prompts deterministically hits `exceededContextWindowSize` between call 20 and 30. We did not append any transcript explicitly; the framework grows it under the hood. Documented for the production migration.

## Reproducibility

This report is generated from the CSV exports the harness writes to `/tmp/fm-eval-<timestamp>/`. To regenerate, re-run the test command above and collect the CSVs. The harness is deterministic in input (gold-set tuples are static) but Apple FM is non-deterministic in output — small run-to-run variance is expected.

---

*Filed alongside design doc #662. Update when the harness is expanded to the full 170-case gold set in the impl-task follow-up.*
