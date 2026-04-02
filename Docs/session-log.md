# Self-Improvement Session Log

## Session 2 (April 1-2, 2026)
- **Commits**: 13, all pushed
- **TestFlight**: Build 51 published
- **Tests**: 566 → 614 (+48 new tests, 0 regressions)
- **Food DB**: 716 → 767 items (+51 foods)
- **Exercise DB**: 884 → 907 items (+23 exercises, 4 dupes removed)

### Changes
- TDEE base formula soft-capped at 2700 to prevent 3000+ without profile data
- 14 comprehensive TDEE demographic tests (all age groups, weight×activity matrix)
- Food DB: Chipotle, Panda Express, Chick-fil-A, Popeyes, Five Guys, In-N-Out, Shake Shack, Dunkin', Domino's, common US home-cooked (mac & cheese, PB&J, BLT, stir fry, beef stew), Asian (pho, teriyaki, General Tso's), Indian snacks (samosa, pakora, bhel puri), healthy (edamame, chia seeds, flaxseed), vegetables
- Exercise DB: Bulgarian Split Squat, Chest Fly (dumbbell/cable), Seated Row (cable/machine), Pendlay Row, Ab Wheel, Hip Abduction/Adduction, Dragon Flag, L-Sit, Pike Push-Up, machine presses, cable curls/raises
- Fixed HRV trend detection: was checking first<last, now checks all sequential pairs rising
- Fixed 2 flaky workout session tests (UserDefaults race conditions in parallel tests)
- Fixed factory reset not clearing TDEE config (activity level, profile data persisted after reset)
- Fixed WeightGoal off-main-thread TDEE fallback not using soft cap
- Dynamic version string (bundle version instead of hardcoded "v0.1.0")
- Dashboard TDEE card now shows data source chips + "Add data to improve" for low confidence

---

## Session 1 (March 29-30, 2026)
- **Commits**: 33 total, all pushed to remote
- **TestFlight**: Builds 48 + 49
- **Tests**: 575 passing (4 new)
- **Food DB**: 681 → 714 items (+33)
- **Exercise DB**: 873 → 884 items (+11)
- **0 regressions**

### Highlights
- Fixed launch screen white flash (missing color asset)
- Accent color refined (#A78BFA — softer, less "AI")
- Templates compacted (play icon instead of big Start button)
- Delete confirmations on templates + workouts
- Settings health buttons now show success/error + descriptions
- Factory reset shows confirmation alert
- Sleep fetching deduplicated (-47 lines)
- HealthKit query helper extracted (-18 lines)
- Food data cleaned (broken entries fixed, categories merged)
- Fast food added (McDonald's, Starbucks, Taco Bell, Wendy's)
- Indian foods expanded (korma, vindaloo, dahi, jalebi, etc.)
- Exercises added (Turkish get-up, farmer's walk, battle ropes, etc.)
- Goal edit button in toolbar
- Copy previous day shows calorie count
- Template preview shows last-used weights
- Recovery estimator tests added
- Manual food entry validates numeric input
- Force unwrap removed from GlucoseTabView
