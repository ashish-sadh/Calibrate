# Future Ideas (Deferred from Self-Improvement Sessions)

These are larger changes identified during autonomous sessions that require human decision-making.

## Architecture
- **UserDefaults key centralization**: 30+ hardcoded string keys across 10+ files. Create a Constants.swift enum.
- **DateFormatter allocation**: 22 views create DateFormatter instances in functions. Could be moved to static lazy properties for performance.
- **DEXA data model**: 14 optional Double fields could be a flexible key-value schema for easier expansion.

## Features
- **Workout streak tracking**: Show current streak and longest streak alongside the consistency chart.
- **Food logging reminders**: Optional notification if no food logged by a certain time.
- **Export data**: Allow users to export their weight, food, workout data as CSV.
- **Widget support**: iOS home screen widget showing today's calories remaining or recovery score.

## Performance
- **Cache recovery baselines**: Dashboard fetches 14-day HRV/RHR/sleep history (42 HealthKit queries) on every load. Should cache baselines for 6 hours.
- **Accessibility labels**: Zero VoiceOver labels in the entire app. Needs systematic pass.

## TDEE
- **Schofield equation as alternative base**: Research shows the sex-averaged Schofield BMR (10.1*W + 851) × activity factor is more accurate than our sqrt scaling (16-20% higher). Could swap in as base formula when no Mifflin profile exists. Trade-off: higher estimates might feel alarming to users in deficit. Current conservative approach is safer but could be configurable.
- **Hard ceiling at 4000 kcal**: Research suggests capping no-profile TDEE at 4000 kcal (covers 140kg very-active). Only elite athletes exceed this. Current soft cap at 2700 is aggressive but matches user preference.

## Lab Report OCR
- **Epic MyChart format**: ~35% of US hospitals use Epic. Format: `Component | Value | Flag | Standard Range | Units` with H/L/HH/LL flags. Adding this parser would cover the biggest gap.
- **Cerner/Oracle Health format**: ~25% of hospitals. Format: `Test Name | Result Value | Units | Reference Range | Interpretation` with Normal/High/Low words.
- **Inline flag parsing (VA/older systems)**: Some formats put flag inline with value: `GLUCOSE 102 H mg/dL 74-100`. Need to strip trailing H/L from numeric value.
- **Colon-separated format (DTC brands)**: `Glucose: 89 mg/dL (65-99)`. Used by LetsGetChecked, some wellness brands.
- **Additional providers to detect**: BioReference Laboratories, ARUP Laboratories, Life Extension, Ulta Lab Tests, Mayo Clinic Labs.

## Apple Health Integration
- **Body fat percentage**: Could enable Katch-McArdle BMR formula for more accurate TDEE when body fat is known from smart scales.
- **VO2 Max**: Fitness level indicator from Apple Watch. Could factor into recovery scoring or activity recommendations.
- **Walking heart rate average**: More stable than resting HR for recovery estimation on days without formal workouts.

## Food Logging UX (researched)
- **Multi-add / batch select**: Check multiple foods from search results and add all at once. MFP's top feature.
- **Meal templates / saved meals**: Save "My usual breakfast" as a single-tap entry. Beyond individual food favorites.
- **Copy from any previous day**: Not just yesterday — let user pick any past day to copy from.
- **Inline editing**: Tap any number in the diary to edit directly without opening a sheet.

## Small Delights (researched, 1-2 hours each)
- **Weekday weight pattern**: "You tend to weigh least on Wednesdays" — group historical weights by day-of-week, show insight. Users never think to check this.
- **Macro rings on Food tab**: Concentric rings (like Apple Fitness) showing P/C/F progress toward targets. "Close the ring" motivation.
- **Time since last meal**: Dashboard shows "Last logged 4h ago" when it's been a while. Non-annoying awareness without push notifications.

## UI
- **Dark theme variant**: Some users may prefer a slightly lighter dark (OLED black vs dark gray).
- **Haptic feedback**: Add subtle haptics to key interactions (logging food, completing a set, finishing a workout).

## Exercise Media / Demonstrations (researched April 2026)

### What the open databases offer

- **free-exercise-db** (already in Drift, 874 exercises): Includes 2 JPG images per exercise (start/end position). Total ~809 KB for images. Public domain. Images hosted on GitHub raw CDN: `https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/{name}/0.jpg`. No video, no GIFs.
  - Source: [yuhonas/free-exercise-db](https://github.com/yuhonas/free-exercise-db)

- **ExerciseDB API**: 11,000+ exercises with animated GIFs showing full rep cycle. Resolution varies by subscription tier. Requires API calls (cloud, not local-first). Was RapidAPI-hosted, now has open-source self-hostable version.
  - Source: [ExerciseDB/exercisedb-api](https://github.com/ExerciseDB/exercisedb-api)

- **wger**: 500+ exercises with images under CC-BY-SA 3.0. Self-hostable Django app. Could scrape exercise images but license requires attribution. AGPL codebase.
  - Source: [wger-project/wger](https://github.com/wger-project/wger)

### How the commercial apps do it

- **Hevy**: ~400 exercises with short looping demo animations (looks like animated illustrations, not video). "How to" tab per exercise with animation + text steps.
- **Fitbod**: 900+ exercises with HD video demonstrations. Likely the most media-heavy of the three.
- **Strong**: Minimalist approach -- no exercise demos. Just logging. Users are expected to already know the movements.
- **Takeaway**: There is a spectrum from zero media (Strong) to full video (Fitbod). Animated illustrations (Hevy) are the middle ground.

### Lottie animations -- the lightweight option

- **VectorFitExercises.com**: 1,470+ exercise animations in Lottie format. Full library is ~90 MB as JSON, or ~12 MB as dotLottie (8-9x smaller). Designed for fitness apps. Vector-based, scalable, works offline, loads instantly. Also exports to MP4/MOV/GIF.
  - Source: [vectorfitexercises.com](https://vectorfitexercises.com)
- **LottieFiles / IconScout**: Free individual fitness animations available, but not a systematic exercise database. Better for decorative use than "demo for bench press."
- **Key advantage**: dotLottie at ~12 MB for 1,470 exercises could be bundled in-app with minimal size impact. No server needed. Matches Drift's local-first philosophy.

### Storage/bandwidth considerations for iOS

- Apple's cellular download limit is 200 MB. App Store recommends keeping initial download under 50-100 MB for adoption.
- **On-Demand Resources (ODR)**: Apple's built-in system for lazy-loading assets. Tag exercise images by body part, download only when user navigates to that exercise. Apple hosts the assets. Tags should be <=64 MB each. Zero impact on initial download.
  - Source: [Apple On-Demand Resources Guide](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/On_Demand_Resources_Guide/index.html)
- **Background Assets framework**: For larger media packs downloaded after install.
- **Rough math**: 960 exercises x 2 JPGs (free-exercise-db) at ~1 KB each = ~2 MB total. Trivial to bundle. 960 exercises as Lottie dotLottie = estimated 8-10 MB. Also bundleable. 960 exercises as GIFs at ~200 KB each = ~190 MB. Needs ODR or lazy loading.

### YouTube linking option

- Deep link format: `https://www.youtube.com/watch?v=VIDEO_ID&t=SECONDS` or `vnd.youtube://VIDEO_ID?t=SECONDS` (opens native YouTube app).
- Could curate a JSON mapping of exercise name to YouTube video ID + timestamp. Zero storage cost.
- Downside: requires internet, leaves the app, videos get deleted/changed, no control over quality.
- Could work as a fallback for exercises without bundled media.

### Recommendation tiers (not prioritized -- just options)

1. **Free, zero-effort**: Show the 2 static JPGs from free-exercise-db that Drift already ships. Add an image viewer to the exercise detail screen.
2. **Lightweight upgrade**: License or create Lottie animations for the top 100 most-used exercises. ~1 MB. Bundle in-app.
3. **Full library**: Use VectorFitExercises or similar for all 960+ exercises as dotLottie. ~12 MB bundled or via ODR.
4. **Hybrid**: Static images bundled + YouTube deep links as "Watch Video" button for users who want more.

---

## AI-Assisted Logging -- Reducing Form-Filling (researched April 2026)

### AI food logging -- current state of the art

- **Photo recognition**: Cal AI claims 97% accuracy on simple meals. SnapCalorie, Nutrola, MyFitnessPal all offer snap-to-log. Accuracy drops significantly on mixed meals, sauces, restaurant dishes, and anything with hidden ingredients. Most still need manual corrections.
  - Sources: [Jotform AI calorie trackers 2026](https://www.jotform.com/ai/best-ai-calorie-tracker/), [Welling AI photo accuracy](https://www.welling.ai/articles/ai-food-tracker-photo-recognition-calories-2026)

- **Voice logging**: Apps like TalkFood, Nutrola, SpeakMeal, JustAddTofu let users say "two eggs and toast with butter" and parse it into food entries. Multilingual (90+ languages). Fast -- under 10 seconds per meal.
  - Source: [SpeakMeal](https://speakmeal.framer.ai/), [TalkFood](https://apps.apple.com/us/app/talkfood-voice-calorie-tracker/id6757200636)

- **Natural language text**: Type "chicken breast 200g, cup of rice, side salad" and the app parses it. Base2Diet and others use NLP APIs to convert free-form text to structured nutrition data.

- **Privacy-first examples**: TalkFood stores all data locally. JustAddTofu uses no accounts and no cloud -- Core Data only. These prove the pattern can work without a server.

### What Apple provides on-device (iOS 26)

- **SpeechAnalyzer / SpeechTranscriber** (new in iOS 26): Fully on-device speech-to-text. DictationTranscriber handles free-form speech with punctuation. SpeechTranscriber handles structured commands. Language models stored in system asset catalog -- zero impact on app bundle size.
  - Source: [Apple WWDC25 SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/), [iOS 26 SpeechAnalyzer Guide](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide)

- **Core ML food models**: Open-source Food101-CoreML classifies food images into 101 categories. See-Food adds nutritional estimates. MobileNetV3 is the practical choice for on-device (quantizes well, low power). Custom models can be trained with Create ML.
  - Sources: [Food101-CoreML](https://github.com/ph1ps/Food101-CoreML), [See-Food](https://github.com/chaitanya-ramji/See-Food), [Apple Core ML Models](https://developer.apple.com/machine-learning/models/)

- **Core ML 4.0**: Up to 45 TOPS on Apple Silicon. Vision framework runs entirely on-device -- zero API calls, zero latency, zero cost per image.

- **Natural Language framework**: On-device tokenization, lemmatization, named entity recognition. Could parse "200g chicken breast" into {food: "chicken breast", quantity: 200, unit: "g"} locally.

- **Rumored Apple Health+**: Apple reportedly preparing a Health+ platform for 2026 with AI-driven food tracking and calorie logging. If launched, could complement or compete with Drift's food tab. Worth monitoring WWDC 2026.
  - Source: [Apple Health+ AI Coach](https://apple.gadgethacks.com/news/apple-health-ai-coach-launches-2026-revolutionary-features/)

### AI for workout logging

- **Apple Watch auto-detection**: Detects start/stop of walks, runs, cycling, swimming, elliptical, rowing. Does NOT auto-detect strength training exercises, reps, or sets.
  - Source: [Apple auto workout detection](https://appletoolbox.com/auto-workout-detection-apple-watch/)

- **Motra (formerly Train Fitness)**: Uses "Neural Kinetic Profiling" -- Apple Watch accelerometer + gyroscope to auto-detect exercise type and count reps. 100K+ users. Technology is promising but not yet reliable for all exercises. Works best for isolation movements (curls, lateral raises).
  - Source: [Motra on App Store](https://apps.apple.com/us/app/motra-formerly-train-fitness/id1548577496)

- **Realistic 2026 assessment**: Auto rep counting from wrist motion is ~70-80% accurate for simple movements, much worse for compound lifts. Manual logging remains more reliable. Best use: suggest "Did you just do 3x10 bicep curls?" for user to confirm/edit rather than silently logging.

### Privacy analysis -- can it all be local?

- **Speech-to-text**: Yes. SpeechAnalyzer is fully on-device as of iOS 26.
- **Food image recognition**: Yes. Core ML + Vision framework. No network needed. Accuracy will be lower than cloud models but usable for common foods.
- **Natural language parsing**: Yes. Apple's Natural Language framework runs on-device. Custom food name matching against Drift's local 817-food database is trivial.
- **Workout motion detection**: Yes. CoreMotion + accelerometer data stays on-device.
- **Nutrition database lookup**: Already local in Drift (817 foods in SQLite). For barcode lookups, Open Food Facts API is the only cloud dependency and could be cached aggressively.
- **Verdict**: A fully local AI-assisted logging pipeline is feasible. Speech -> NLP parse -> local DB match -> confirm. No cloud required for the core flow.

### Practical ideas for Drift (not prioritized)

1. **Voice food logging**: Tap mic, say "two eggs and a banana," parse with on-device Speech + NLP, fuzzy-match against Drift's food DB, present for confirmation. Zero cloud dependency.
2. **Natural language text input**: Type "chicken 200g, rice 1 cup" in the search bar, parse and auto-fill. Simpler than voice, no microphone permission needed.
3. **Photo food logging**: Snap a photo, run through Core ML food classifier, suggest top matches from local DB. User confirms and adjusts portion. Accuracy caveat: works for single-item meals, unreliable for mixed plates.
4. **Smart suggestions from history**: "You usually eat eggs at 8am on weekdays" -- pre-fill suggestions based on patterns. No AI model needed, just SQL queries on existing log data.
5. **Watch-assisted workout hints**: If Apple Watch detects elevated HR + wrist motion pattern, suggest "Starting a workout?" in the app. Do not auto-log -- just prompt.
6. **Confirm-not-log pattern**: Any AI suggestion should be presented for human confirmation, never silently logged. Reduces frustration from wrong guesses.

## UX Research (April 2026)

### Highest-Impact Food Logging Improvements
1. **Saved meals (one-tap re-log)**: Users eat the same breakfast ~80% of the time. Save multi-item meals and re-log with one tap. *(Lose It!, MFP — easy)*
2. **Time-of-day search context**: Show coffee/oats in morning search, protein at dinner. Boost relevance without changing ranking algorithm. *(Lose It! — easy)*
3. **Quick-add raw calories**: Dedicated "just enter 500 cal" button for eating out, no food search needed. *(MFP — easy)*
4. **Voice food logging**: "Two eggs and toast" → parsed via iOS Speech framework. SnackSmart does this on-device. *(medium)*
5. **AI photo recognition**: Passio Nutrition-AI SDK — on-device Core ML, 2.5M food DB, iOS Swift Package, token pricing ($2.50/M). Privacy-compatible. *(hard, but SDK handles ML)*

### Exercise Logging Improvements
1. **Single-tap set completion**: Show prefilled weight/reps from last session, tap checkmark to confirm. Minimize taps. *(Setgraph — easy)*
2. **Swipe gestures on sets**: Swipe to adjust reps +/- 1 instead of opening picker. *(medium)*
3. **Post-workout summary card**: Shareable card with PRs, volume, duration. *(Hevy — medium)*

### Exercise Media (for user's research question)
- **ExerciseDB API**: 11,000+ exercises with GIFs/images. Open source on GitHub. *(free — medium to integrate)*
- **Wger**: Open source, 500 exercises with illustrations. *(free — medium)*
- **Strategy**: Lazy-download GIFs per exercise on first view. Bundle nothing. Show in exercise detail sheet.

### Reducing Logging Fatigue
- Streaks + "don't break the chain" counter (Drift has heatmaps, add streak number)
- Progressive disclosure: calories-only default, expand for macros
- Weekly summary notification: "6/7 days logged, X cal avg"

### Key risk to monitor

- **Apple Health+ with built-in food tracking** could launch at WWDC 2026. If Apple adds native calorie logging to the Health app, it changes the competitive landscape. Drift's advantage would be its algorithm (TDEE, projections, goal tracking) rather than raw food logging.
