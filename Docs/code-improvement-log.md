# Drift Code-Improvement Log

Track of code quality improvement cycles. Each entry = one refactoring cycle.

---

## 2026-04-08

- **WorkoutView.swift** — [Principle: SwiftUI] Smell: 9 structs in 2067-line file → extracted ActiveWorkoutView (737 lines) to its own file. File reduced to 1327 lines.
- **HealthKitService.swift** — [Principle: Design Patterns] Smell: God class spanning 7+ health domains → extracted cycle tracking (270 lines) to HealthKitService+Cycle.swift. File reduced to 741 lines.
- **FoodTabView.swift** — [Principle: SwiftUI] Smell: 891-line monolithic view → extracted PlantPointsCardView (187 lines) as self-contained component. File reduced to 702 lines.
- **AppDatabase.swift** — [Principle: Design Patterns] Smell: God class spanning 12 domains → extracted food usage tracking (201 lines) to AppDatabase+FoodUsage.swift. File reduced to 737 lines.
- **FoodSearchView.swift** — [Principle: SwiftUI] Smell: @State explosion (25 vars, 9 manual*) → extracted ManualFoodEntrySheet (136 lines). File reduced to 669 lines, 16 @State vars.
- **AIChatView.swift** — [Principle: Clean Code] Smell: 964-line file mixing UI + suggestion logic → extracted suggestions/insight/fallbacks (178 lines) to AIChatView+Suggestions.swift. File reduced to 786 lines.
- **WorkoutView.swift** — [Principle: SwiftUI] Smell: 8 extra structs still in file → extracted ExercisePickerView + CustomExerciseSheet (194 lines) to ExercisePickerView.swift. File reduced to 1133 lines.
- **AIContextBuilder.swift** — [Principle: Design Patterns] Smell: God class, 19 sections → extracted 5 health contexts (154 lines) to AIContextBuilder+Health.swift. File reduced to 529 lines.
- **DashboardView.swift** — [Principle: SwiftUI] Smell: 649-line view with 7 card sections → extracted TDEE + calorie balance cards (276 lines) to DashboardView+Cards.swift. File reduced to 373 lines.
- **LabReportOCR.swift** — [Principle: Clean Code] Smell: 652-line enum mixing OCR + biomarker logic → extracted biomarker extraction + aliases (300 lines) to LabReportOCR+Biomarkers.swift. File reduced to 352 lines.
- **WorkoutView.swift** — [Principle: SwiftUI] Smell: 6 extra structs still in file → extracted WorkoutDetailView (142 lines). File reduced to 991 lines.
- **WorkoutView.swift** — [Principle: SwiftUI] Smell: 4 extra structs → extracted CreateTemplateView + TemplateExerciseEditor (190 lines). File reduced to 800 lines.

## 2026-04-09

- **FoodTabView.swift** — [Principle: SwiftUI] Smell: 1011 lines, 9 edit* @State vars → extracted EditFoodEntrySheet (250 lines) as self-contained view. File reduced to 765 lines.

## 2026-04-12

- **AIChatView.swift** — [Principle: Clean Code] Smell: 476-line sendMessage() god function → extracted to AIChatView+MessageHandling.swift with 13 focused handler methods. File reduced from 836 to 214 lines.
- **GoalView.swift** — [Principle: SwiftUI] Smell: 600-line view with complex profile form bindings inline → extracted profile card, fields, save logic (233 lines) to GoalView+Profile.swift. File reduced to 385 lines.
- **FoodSearchView.swift** — [Principle: DDD] Smell: 22 direct AppDatabase.shared calls in a view (searches, favorites, raw SQL updates) → routed all through FoodService with 8 new methods. Zero database imports remain in view.
