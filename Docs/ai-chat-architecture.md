# AI Chat Architecture

## Overview

Drift's AI chat uses a **tiered pipeline** — fastest path first, LLM only when needed. The architecture separates **language understanding** (LLM) from **tool selection** (rules) and **data operations** (Swift).

```
User Input
    |
    v
┌─────────────────────────────────────────────────────────┐
│  TIER 0: Rules on Raw Input (instant, 0ms)              │
│                                                         │
│  StaticOverrides ─► Swift Parsers ─► View-State Handlers│
│  "calories left"   "log 3 bananas"   "start push day"   │
│  "daily summary"   "I weigh 165"     "remove the rice"  │
│  "took creatine"   "ate avocado"     "smart workout"    │
│                                                         │
│  Catches ~60-70% of queries                             │
└──────────────────────┬──────────────────────────────────┘
                       │ no match
                       v
┌─────────────────────────────────────────────────────────┐
│  TIER 1: LLM Normalizer → Re-run Rules (~3s)           │
│                                                         │
│  LLM rewrites messy input to clean form:                │
│  "I had 2 to 3 banans" → "log 3 banana"                │
│  "how'd I sleep"       → "how is my sleep"              │
│  "set goal to one sixty" → "set goal to 160 lbs"        │
│                                                         │
│  ~80 token prompt, ~20 token output                     │
│  Rewritten query re-enters Tier 0 rules                 │
│                                                         │
│  Catches ~20% more queries                              │
└──────────────────────┬──────────────────────────────────┘
                       │ no match
                       v
┌─────────────────────────────────────────────────────────┐
│  TIER 2: Rule-Based Tool Picker (instant after T1)      │
│                                                         │
│  ToolRanker scores tools by keyword matching:            │
│  "how is my sleep" → sleep_recovery (score 6.5)         │
│  "glucose today"   → glucose (score 7.0)                │
│                                                         │
│  Executes if: topScore >= 4.0 AND gap >= 2.0            │
│  No LLM needed for tool selection                       │
│                                                         │
│  Catches ~10% more queries                              │
└──────────────────────┬──────────────────────────────────┘
                       │ no confident match
                       v
┌─────────────────────────────────────────────────────────┐
│  TIER 3: Full Streaming Response (~10-20s)              │
│                                                         │
│  Context gathering → ranked tools → LLM streaming       │
│  "given my macros, what should I eat for dinner?"       │
│  "how am I doing compared to last week?"                │
│                                                         │
│  ~1200 token prompt, streams answer to UI               │
│  Only for true questions needing reasoning              │
│                                                         │
│  Catches remaining ~5%                                  │
└─────────────────────────────────────────────────────────┘
```

## Detailed Flow: `sendMessage()`

```
User types message
    │
    ├─ 1. StaticOverrides.match()                    [instant]
    │     Emoji, greetings, thanks, help, barcode
    │     Rule engine: "daily summary", "calories left", "copy yesterday"
    │     Deterministic: body comp, goal, inline macros, quick-add cal
    │
    ├─ 2. Pending workout: "done" / "start"          [instant]
    │     Opens ActiveWorkoutView if template pending
    │
    ├─ 3. Confirmation: "yes" / "yeah"               [instant]
    │     Regex extracts weight or activity from last assistant message
    │     Logs via WeightServiceAPI or WorkoutService
    │
    ├─ 4. Delete food: "remove" / "delete" / "undo"  [instant]
    │     FoodService.deleteEntry(matching:)
    │
    ├─ 5. Smart workout / template start              [instant]
    │     ExerciseService.buildSmartSession()
    │     WorkoutService.fetchTemplates() → match
    │
    ├─ 6. Meal logging: "log breakfast/lunch/dinner"  [instant]
    │     Sets pendingMealName, asks "What did you have?"
    │
    ├─ 7. Food intent: "log 3 bananas", "ate eggs"   [instant]
    │     AIActionExecutor.parseFoodIntent()
    │     → extractAmount() → findFood() → open search sheet
    │
    ├─ 8. Activity: "I did yoga 30 min"              [instant]
    │     Parse prefix + duration → confirmation prompt
    │
    ├─ 9. Weight: "I weigh 165"                      [instant]
    │     AIActionExecutor.parseWeightIntent() → log directly
    │
    ├─10. GEMMA PIPELINE (if large model)            [3-20s]
    │     │
    │     ├─ Tier 1: normalizeQuery() → tryRulePick/StaticOverrides
    │     ├─ Tier 2: tryRulePick on original
    │     └─ Tier 3: Full streaming with context
    │
    └─11. SMOLLM PATH (if small model)              [5-15s]
          Remaining Swift handlers → AIChainOfThought → LLM fallback
```

## Component Map

```
┌──────────────────────────────────────────────────────────────────┐
│                        AIChatView.swift                          │
│   sendMessage() — orchestrates all layers, manages UI state      │
│   buildConversationHistory() — last 6 msgs, 600 chars (Gemma)   │
└──────────┬───────────────────┬───────────────────┬───────────────┘
           │                   │                   │
           v                   v                   v
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────────┐
│ StaticOverrides  │ │ AIActionExecutor │ │  AIToolAgent      │
│                  │ │                  │ │                      │
│ Exact matches    │ │ parseFoodIntent  │ │ normalizeQuery()     │
│ Rule engine      │ │ parseWeightIntent│ │ run() — tiered       │
│ Regex handlers   │ │ findFood()       │ │ executeTool()        │
│                  │ │ extractAmount()  │ │                      │
└──────────────────┘ │ SpellCorrect ✓   │ └──────┬───────────────┘
                     └──────────────────┘        │
                                                 v
                     ┌──────────────────────────────────────────┐
                     │            ToolRanker.swift               │
                     │                                          │
                     │ rank() — keyword scoring, top N tools    │
                     │ normalizePrompt() — ~80 token rewriter   │
                     │ quickExtractPrompt() — tool call prompt  │
                     │ tryRulePick() — confident tool selection  │
                     │ buildPrompt() — full context prompt       │
                     │ extractParamsForTool() — param extraction │
                     │                                          │
                     │ 19 tool profiles with:                   │
                     │   triggers, logBoost, queryBoost,         │
                     │   screenAffinity, antiKeywords            │
                     └──────────────────┬───────────────────────┘
                                        │
                     ┌──────────────────────────────────────────┐
                     │       ToolRegistry + ToolSchema          │
                     │                                          │
                     │ 19 registered tools:                     │
                     │   Food: log_food, food_info,             │
                     │         copy_yesterday, delete_food,     │
                     │         explain_calories                 │
                     │   Weight: log_weight, weight_info,       │
                     │           set_goal                       │
                     │   Exercise: start_workout, exercise_info,│
                     │             log_activity                 │
                     │   Health: sleep_recovery, supplements,   │
                     │           add_supplement, mark_supplement│
                     │           glucose, biomarkers,           │
                     │           body_comp, log_body_comp       │
                     │                                          │
                     │ execute(): preHook → validate → handler  │
                     │            → postHook                    │
                     │                                          │
                     │ parseToolCallJSON(): strips ()           │
                     └──────────────────────────────────────────┘
                                        │
                     ┌──────────────────────────────────────────┐
                     │          LocalAIService.swift             │
                     │                                          │
                     │ respond() — non-streaming + systemPrompt │
                     │ respondStreaming() — streaming + sysPrmpt│
                     │ respondDirect() — custom system prompt   │
                     │ respondStreamingDirect() — custom + strm │
                     │                                          │
                     │ Model management: load, unload, health   │
                     └──────────────────┬───────────────────────┘
                                        │
                     ┌──────────────────────────────────────────┐
                     │         LlamaCppBackend.swift             │
                     │                                          │
                     │ Raw llama.cpp C API inference             │
                     │                                          │
                     │ Context: 2048 tokens                     │
                     │ Max prompt: 1776 tokens                  │
                     │ Max generation: 256 tokens               │
                     │ Temp: 0.4, Top-P: 0.9                   │
                     │                                          │
                     │ Chat templates:                          │
                     │   Gemma: <start_of_turn>user/model       │
                     │   ChatML: <|im_start|>system/user/asst   │
                     │                                          │
                     │ Early JSON termination: { } counting     │
                     │ Stop sequences: <end_of_turn>, im_end    │
                     │                                          │
                     │ GPU: 999 layers offloaded (A-series)     │
                     │ CPU fallback if Metal fails              │
                     │ Threads: cores-2 (inference), all (batch)│
                     └──────────────────────────────────────────┘
```

## Context Gathering

```
User query
    │
    v
AIChainOfThought.plan(query, screen)
    │
    ├─ Keyword classification (50+ patterns):
    │   needsFood, needsWeight, needsSleep, needsWorkout,
    │   needsGlucose, needsBiomarkers, needsDEXA, needsCycle,
    │   needsSupplements, needsOverview, needsComparison
    │
    v
AIContextBuilder
    │
    ├─ baseContext()     — calories, macros, weight trend, goal progress
    ├─ foodContext()     — today's meals, recent foods, 7-day avg
    ├─ weightContext()   — EMA weight, weekly rate, goal progress
    ├─ workoutContext()  — last workout, streak, neglected body parts
    ├─ sleepRecoveryCtx  — hours, REM/deep, HRV, recovery score
    ├─ glucoseContext()  — average, range, spikes
    ├─ biomarkerContext() — lab results, out-of-range markers
    ├─ dexaContext()     — body fat %, BMI, lean mass
    ├─ cycleContext()    — current day, phase, avg length
    └─ supplementCtx()  — taken/total, what's needed
    │
    v
truncateToFit(maxTokens: 500)
    → Ready for LLM prompt
```

## Token Budgets

### Normalizer (Tier 1)
| Component | Tokens |
|-----------|--------|
| System prompt | ~50 |
| Examples | ~30 |
| Chat history (multi-turn) | ~50 |
| User message | ~15 |
| **Total prompt** | **~145** |
| Expected output | ~15 |

### Full Streaming (Tier 3)
| Component | Tokens |
|-----------|--------|
| Chat template | ~24 |
| System instructions + examples | ~200 |
| Ranked tools (top 4) | ~150 |
| Data context | ~500 |
| History | ~150 |
| User message | ~100 |
| **Total prompt** | **~1124** |
| Max generation | 256 |

### Hard Limits
- Context window: **2048 tokens**
- Max prompt: **1776 tokens** (2048 - 256 gen - 16 safety)
- Max generation: **256 tokens**

## Multi-Turn Resolution

The normalizer handles pronoun resolution using compact chat history:

```
Turn 1: "how's my food today"
  → Normalizer: "food info" (no history needed)
  → food_info tool → "1200 cal eaten, 600 remaining..."

Turn 2: "what about protein?"
  → Normalizer sees: "Chat: Q: food today A: 1200 cal..."
  → Rewrites: "how is my protein"
  → StaticOverride match → protein status

Turn 3: "and yesterday?"
  → Normalizer sees: "Chat: Q: protein A: 80g today..."
  → Rewrites: "yesterday food summary"
  → Rule engine match → yesterday summary
```

## Model Paths

| Feature | Gemma 4 (2B) | SmolLM (360M) |
|---------|-------------|---------------|
| Tier 0 rules | Yes | Yes |
| LLM normalizer | Yes (Tier 1) | No (too slow) |
| Rule-based tool pick | Yes (Tier 2) | No |
| Full streaming | Yes (Tier 3) | AIChainOfThought |
| Context budget | 500 tokens | 300 tokens |
| History budget | 600 chars, 6 msgs | 300 chars, 4 msgs |
| Tool list | Ranked top 4 | Screen-filtered, max 6 |
| System prompt | Via ToolRanker | Built-in LocalAIService |

## Food Search Pipeline

```
User: "log 3 bannanas"
    │
    v
parseFoodIntent()
    ├─ Verb detection: "log " → strip → "3 bannanas"
    ├─ extractAmount(): "3" → (3.0, "bannanas", nil)
    └─ FoodIntent(query: "bannanas", servings: 3.0)
    │
    v
findFood(query: "bannanas", servings: 3.0)
    ├─ 1. Exact: searchFoodsRanked("bannanas") → no match
    ├─ 2. Singular: "bannana" → no match
    ├─ 3. Spell correct: "bannana" → "banana" → MATCH ✓
    ├─ 4. Qualifiers: strip "slices of", "cups of", etc.
    └─ 5. First word: try just first word
    │
    v
FoodMatch(food: Banana, servings: 3.0) → open search sheet
```
