# AI Improvement Ideas (Curated)

## Implemented So Far
- Raw llama.cpp C API (bypasses Metal crash on A19 Pro)
- Chain-of-thought with visible "thinking" steps
- Token streaming (word-by-word text appearance)
- Screen awareness (11 views tracked)
- Full context: food, weight, sleep, glucose, biomarkers, DEXA, cycle, supplements, workouts
- Multi-food logging, weight entry via chat
- Natural phrasing ("I just had a samosa")
- AI-enhanced lab report parsing
- Few-shot examples in system prompt
- Pre-computed insights ("losing at healthy pace", "low protein by afternoon")
- Response cleaner (artifacts, disclaimers, deduplication)
- Quality gate (filters generic/repetitive/garbage responses)
- Instant food logging for known foods (no search sheet needed)
- Multi-food natural phrasing ("I just had chicken and rice" → both logged)
- Weekly summary, yesterday comparison with calorie target
- Compound food handling (mac and cheese not split)
- Pronoun resolution ("log it" after discussing banana)
- Screen-aware fallback responses with actionable suggestions
- Data-aware greetings (guides new users to add data)
- Help command with structured capability list
- Undo handling with clear guidance
- Weight logging via chat ("I weigh 165")
- LOG_WEIGHT action from LLM responses
- Conversation memory (last 2 exchanges)
- Auto-scroll during streaming
- Time-aware calorie warnings
- Restaurant/eating out meal estimation guidance
- Emoji-only message handling
- Weekly suggestion pill on weekends/evenings
- Biomarker improvement tips for out-of-range markers
- Recovery assessment for training readiness
- Glucose health assessment (well controlled/elevated)
- DEXA body fat classification (athletic/fit/average)
- Workout template suggestions based on recent training
- Food context grouped by meal type (breakfast/lunch/dinner)
- Automatic dependency injection (weight plateau → food data)
- Context regurgitation detection
- Format echo stripping ("A:", "Assistant:")
- Mechanical preamble removal
- Experimental warning only shown once
- Nutrition lookup from DB ("how many calories in banana?")
- Comparison context (this week vs last week)
- Pronoun resolution ("log it" after discussing banana)
- Token budget management (800 token context cap + backend truncation)
- Data-aware greetings

## Research Findings (from web search)
1. Small models (< 2B) benefit from:
   - Very explicit, terse instructions over verbose prompts
   - 1-2 few-shot examples (more wastes tokens)
   - Temperature 0.3-0.5 for factual responses
   - Doing ALL math in Swift, model just phrases it
   - Structured output formats (fill-in-the-blank over free-form)
   - Short responses (hallucination increases with length)
   - repeat_penalty 1.1-1.3

2. "LLM is the voice, Swift is the brain":
   - Calculate deficits, projections, trends in Swift
   - Model's job: turn structured data into friendly sentences
   - Never ask model to do arithmetic or retrieve from memory

## Evaluation Harness Baseline (AIEvalHarness.swift)

| Metric | Score | Target |
|--------|-------|--------|
| Food logging precision | 19/19 (100%) | >= 85% |
| Food logging false positives | 0/8 (0%) | <= 10% |
| Weight logging precision | 6/6 (100%) | >= 83% |
| Weight false positives | 0/4 (0%) | 0% |
| Chain-of-thought routing | 15/15 (100%) | >= 85% |
| Amount parsing | 9/9 (100%) | >= 78% |
| Compound food protection | 3/3 (100%) | 100% |
| Response quality cleaner | Pass | Pass |

Run: `xcodebuild test -only-testing:'DriftTests/AIEvalHarness'`

## Claude Code Harness Patterns (Applied to 1.5B)

Key insight: "harness intelligence + model intelligence = total intelligence"
With 1.5B, shift ratio heavily toward harness intelligence.

1. **Narrow tool surface per turn** — show only relevant action schemas
2. **Inject state every turn** — prepend current screen, last action, user goal
3. **Pre-parse intent in harness** — keywords pick category, model fills details
4. **Compress aggressively** — old turns summarized, context truncated
5. **Structured output enforcement** — grammar-based sampling in llama.cpp

Already implemented: #2 (screen-aware context), #3 (food/weight/workout parsers),
#4 (conversation history truncation, context budgeting)

TODO: #1 (dynamic action schema per screen), #5 (grammar sampling)

## Ideas for Next Session

### High Impact
- [x] **Direct food logging without search sheet** — DONE: when exact DB match found, logs immediately
- [ ] **"Ask AI" in food search no-results** — when search finds nothing, show "Ask AI to estimate" button that uses LLM to estimate nutrition
- [ ] **Meal plan builder** — "plan my meals for today" generates a full day plan based on remaining macros and user's food history
- [ ] **Smart time-of-day suggestions** — at 7am, suggest breakfast items; at 6pm, dinner items with remaining macro targets
- [ ] **Exercise recommendation** — based on last 7 days of workouts, suggest which body part hasn't been trained

### Medium Impact
- [ ] **Image-based food logging** — take a photo of food, describe it to LLM, auto-log (needs MLX vision model or simple image classifier)
- [ ] **Voice input** — iOS speech-to-text → AI chat, hands-free food logging
- [ ] **Weekly AI summary push notification** — generate a weekly insight via background task
- [ ] **Goal adjustment recommendations** — "based on your 30-day trend, consider adjusting your deficit to -300kcal/day"
- [ ] **Supplement interaction warnings** — flag when supplements might interact or when timing matters

### Research Required
- [ ] **On-device embedding for semantic search** — MiniLM or similar for better food matching
- [ ] **Exercise form videos** — link exercises to demonstration videos (YouTube API or bundled clips)
- [ ] **Fine-tuning the model** — create a small dataset of health Q&A pairs and fine-tune Qwen2.5-1.5B
- [x] **Metal GPU FIXED** — Found exact bug (#17986) and fix (PR #18456). Rebuilt xcframework from b7400 (which has the bfloat/half kernel fix). GPU context should now work on A19 Pro. Device: n_gpu_layers=999 with CPU fallback.
- [ ] **Larger context window** — increase to 4096 tokens for more context (needs memory testing on device)
- [ ] **Model distillation** — fine-tune SmolLM2-360M to match Qwen2.5-1.5B quality for faster inference
