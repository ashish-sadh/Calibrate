# Self-Improvement Session Log

## Session 2 (April 1-2, 2026)
- **Commits**: 22, all pushed
- **TestFlight**: Build 51 published
- **Tests**: 566 → 614 (+48 new tests, 0 regressions)
- **Food DB**: 716 → 768 items (+63 added, 11 dupes removed, names cleaned)
- **Exercise DB**: 884 → 907 items (+23 added, 4 dupes removed, 21 capitalization fixes)

### Changes
- **TDEE**: Base formula soft-capped at 2700 (prevents 3000+ without profile data). 14 comprehensive demographic tests across all age groups and weight×activity matrix. WeightGoal TDEE fallback uses soft cap. Research logged (Schofield equation, 4000 kcal ceiling) in future-ideas.md.
- **Dashboard**: TDEE card shows data source chips + "Add data to improve" hint. VoiceOver accessibility labels added (weight, health pills, recovery). Dead comments removed.
- **Food**: +63 items (Chipotle, Panda Express, Chick-fil-A, Popeyes, Five Guys, In-N-Out, Shake Shack, Dunkin', Domino's, US home-cooked, Asian, Indian snacks, plant-based, fermented foods, healthy staples). 11 duplicates removed. Lowercase names capitalized. Eggplant recategorized from Proteins to Vegetables. Consistency heatmap batch query (30 → 1 DB queries).
- **Exercises**: +23 items (Bulgarian Split Squat, Chest Fly, Seated Row, Pendlay Row, Ab Wheel, Hip machines, Dragon Flag, L-Sit, Pike Push-Up, machine presses, cable exercises). 4 duplicates removed. Equipment/category capitalization normalized (21 fixes).
- **Bugs fixed**: HRV trend detection (sequential pairs vs first<last), 3 flaky workout session tests (UserDefaults race conditions), factory reset missing TDEE config + exercise favorites + TDEE cache, MoreTabView dark background, barcode scanner ml serving sizes.
- **Lab OCR**: Month-name date formats (Mar 15, 2026 / January 5, 2026 / 15 Mar 2026) + 5 tests.
- **Accessibility**: VoiceOver labels on dashboard (weight card, health pills, recovery) and food diary entries.
- **Performance**: Food consistency heatmap batch query (30 individual queries → 1 batch query).
- **Other**: Dynamic version string, stale code comments removed, docs updated.

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
