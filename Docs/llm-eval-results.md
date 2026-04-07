# LLM Tool-Calling Eval Results

**Model:** Qwen2.5-1.5B-Instruct Q4_K_M
**Date:** 2026-04-06
**Prompt:** 6 tools max, LOGGING/QUESTION/CHAT framework, 7 few-shot examples

## Results

| Category | Score | % | Notes |
|----------|-------|---|-------|
| Food Logging (20) | 20/20 | **100%** | Perfect. "I had X" always calls log_food. |
| Food Questions (15) | 6/15 | **40%** | Confuses questions with logging. "What should I eat" → log_food. |
| Exercise Coach (23) | 3/23 | **13%** | Responds naturally, almost never calls exercise tools. |
| Weight (15) | 3/15 | **20%** | Responds naturally. Even "I weigh 165" gets natural response. |

## Key Findings

1. **Food logging is the only reliable tool call.** 100% accuracy on "I had/ate/log [food]" → log_food.
2. **Questions trigger no tool call.** The model prefers to answer naturally rather than call an info tool.
3. **The word "eat" confuses LOG vs QUESTION.** "What should I eat" → log_food (wrong).
4. **Exercise tools are almost never called.** Model just gives advice text.
5. **Weight logging also fails.** "I weigh 165" → natural response instead of log_weight.

## Architecture Decision

Based on data: **hybrid approach**

- **LLM handles:** Food logging (100%), natural conversation, rephrasing data
- **Swift harness handles:** Weight logging (regex), exercise routing (keywords), all data queries (call tool → pass result to LLM)
- **Rule engine handles:** Exact matches (summary, calories left, supplements)

The 1.5B model is a **food logging specialist + conversational rephraser**, not a general tool-caller. The harness must compensate.

## Qwen3-1.7B Comparison (2026-04-07)

| Category | Qwen2.5-1.5B | Qwen3-1.7B |
|----------|-------------|------------|
| Food Logging | **100%** | **30%** |

Qwen3 is WORSE at tool calling. It prefers to respond naturally instead of outputting JSON tool calls. Qwen2.5-1.5B-Instruct remains the best choice — its instruction tuning produces better structured output.

## Architecture Decision (confirmed by data)

1. **Qwen2.5-1.5B** stays as the model
2. **Food logging** → LLM tool calling (100% accurate)
3. **Everything else** → Swift harness routes, calls tools, passes to LLM for phrasing
4. **Food questions** → Swift handles directly (LLM only 40%)
5. **Exercise/weight** → Swift handles directly (LLM only 13-20%)
