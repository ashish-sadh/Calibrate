# AI Auto-Research Pipeline Optimizer

Karpathy-style prompt optimization loop for the full AI pipeline. Every sprint, run this loop to find the best pipeline configuration, apply it automatically, and push if regression-free.

**Core idea:** Prompt is the program. Eval is the objective function. The loop is the engineer.

---

## Pipeline Map (Everything Is Fair Game)

```
Stage 0  InputNormalizer.normalize()           [Services/InputNormalizer.swift]
Stage 1  StaticOverrides.match()               [Services/StaticOverrides.swift]
Stage 2  IntentClassifier.classifyFull()       [Services/IntentClassifier.swift]
Stage 2b AIToolAgent.validateExtraction()      [Services/AIToolAgent.swift:228]
Stage 3  AIToolAgent.streamPresentation()      [Services/AIToolAgent.swift:310]
Stage 4  ToolRanker.buildPrompt() fallback     [Services/ToolRanker.swift]
```

The optimizer can mutate any stage — prompts, code logic, stage order, stage additions, StaticOverride removals. The eval score is the only arbiter.

---

## Files

| File | Purpose |
|------|---------|
| `DriftLLMEvalMacOS/HardEvalSet.swift` | 100 eval cases (70 train / 30 held-out), grows every sprint |
| `DriftLLMEvalMacOS/PromptOptimizer.swift` | Optimization engine + source file applicator |
| `DriftLLMEvalMacOS/AutoResearchTests.swift` | XCTest harness (baseline always-on, loop gated) |
| `Drift/Services/IntentClassifier.swift` | `static var systemPrompt` — mutated by optimizer |
| `Drift/Services/AIToolAgent.swift` | `static var presentationPrompt` — mutated by optimizer |

---

## Eval Scoring (End-to-End)

| Dimension | Weight | What it checks |
|-----------|--------|----------------|
| Tool routing | 35% | Did the right tool get called? |
| Param quality | 35% | Were extracted params correct (food name, quantity, screen)? |
| Response | 30% | Was the response sensible? (rubric-checked, no LLM judge) |

Response rubric is deterministic:
- Logging → response must contain food/supplement name
- Info queries → response must contain a number or fact
- Navigation → response must contain screen name  
- `mustNotContain` → hallucination guard (no made-up data)

---

## Eval Categories

| Category | Cases | What it covers |
|----------|-------|----------------|
| `foodRouting` | 25 | Implicit logging — Indian food, emoji, typos, no "log" keyword |
| `regression` | 25 | Must NOT log — questions, future intent, sentiment statements |
| `multiTurn` | 15 | History-dependent continuations |
| `supplement` | 10 | mark_supplement vs supplements() disambiguation |
| `navigation` | 8 | Typos, slang, alternate screen names |
| `contextSwitch` | 5 | Topic change mid-conversation (food→sleep, weight→supplement) |
| `quickReplyPills` | 7 | Pill suggestions that must never regress |

**Growing:** Add 3–5 cases per sprint from real failures. Future categories: `calorieEstimation`, `macroQuery`, `crossDomain`, `mealSuggestion`, `imageFood` (when model is ready).

---

## Mutation Priority (per round)

1. **Classifier example injection** — add/replace few-shot example for failing routing case
2. **Rule addition** — when 3+ failures share same wrong-tool pattern, add RULES clause  
3. **Presentation prompt fix** — when routing is right but response fails rubric (topic switch, tone)
4. **Extraction/validation fix** — when routing is right but params are wrong
5. **StaticOverrides removal** — when LLM handles pattern at ≥95% on train set
6. **Navigation alias** — when navigation fails due to unknown alias
7. **New tool** — only when multiple cases reveal a consistent capability gap

**Token budget:** classifier ≤800 words, presentation ≤200 words. Variants over budget are discarded.

---

## Auto-Apply Protocol

1. Run loop → find best `PipelineConfig` on held-out set
2. Apply winner to source files (`IntentClassifier.swift`, `AIToolAgent.swift`)
3. Run regression guard (core IntentRoutingEval cases)
4. **If held-out ≥+1% AND regression delta ≥-2%** → commit + push `feat(ai): autoresearch — +X% held-out`
5. **Otherwise** → `git checkout` source files, log rejection reason

The winner report is always written to `~/drift-state/autoresearch/winner-<timestamp>.txt` regardless of apply outcome.

---

## Growing IntentRoutingEval

IntentRoutingEval grows via two channels:
- **Graduation:** HardEvalSet train cases that pass 100% after a winning mutation get added to IntentRoutingEval as permanent regression tests
- **Enrichment:** Real failures from practice get added to HardEvalSet first, then graduate once solved

Target: 150 cases today → 300+ cases over several sprints.

---

## Sprint Commands

```bash
# Record baseline at sprint start (~5 min)
xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS' \
  -only-testing:AutoResearchTests/testBaseline

# Sanity check (no model, ~2s)
xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS' \
  -only-testing:AutoResearchTests/testHardEvalSetSanity \
  -only-testing:AutoResearchTests/testBaselineTokenBudget

# Full optimization loop (~40 min)
DRIFT_AUTORESEARCH=1 xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS' \
  -only-testing:AutoResearchTests/testAutoResearch
```

---

## Success Criteria

| Metric | Target |
|--------|--------|
| Held-out score | ≥78% (from ~72% baseline) |
| Full 100-case score | ≥82% |
| contextSwitch category | ≥65% (from ~45%) |
| IntentRoutingEval regression | 0 (hard gate) |
