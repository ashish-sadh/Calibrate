import Foundation
import DriftCore
import Observation

// Single-source (SharedUI): drives the Food tab on BOTH the iOS app and the
// Android app (#1059/#1062 port). No platform imports — widget refresh goes
// through the DriftPlatform seam; the one iOS-view-typed helper
// (`logRecipeItems`) is gated DRIFT_IOS_APP.
@MainActor
@Observable
final class FoodLogViewModel {
    private let database: AppDatabase

    var searchQuery: String = ""
    var searchResults: [Food] = []
    var todayNutrition: DailyNutrition = .zero
    var todayEntries: [FoodEntry] = []
    var selectedDate: Date = Date()
    var recentFoods: [Food] = []
    var recentEntries: [RecentEntry] = []
    var frequentFoods: [Food] = []
    var savedRecipes: [SavedFood] = []
    var favoriteFoods: [RecentEntry] = []
    var weeklyPlantPoints: PlantPointsService.PlantPoints = .init(uniquePlants: [], uniqueHerbsSpices: [])
    var dailyNewPlants: Int = 0
    var combos: [Food] = []
    /// Unified suggestion strip: combos + recents in one most-clicked-first ranking.
    var suggestionChips: [Food] = []

    var dateString: String {
        DateFormatters.dateOnly.string(from: selectedDate)
    }

    /// Auto-assign meal type: inherit from a recent entry logged within 3h (so a second bowl at
    /// 10am after a 7am breakfast stays `breakfast`), else fall back to hour ranges.
    var autoMealType: MealType {
        MealType.resolve(now: Date(), recentEntries: todayEntries)
    }

    /// Timestamp for a NEW entry. Today → real wall-clock now, so entries
    /// sort by the actual order they were logged. A PAST day (back-filled
    /// log) → the meal-type's canonical hour on that day, so it sorts
    /// sensibly by meal instead of clustering at "now" with a wrong time
    /// (past-day logging fix, 2026-07-08 — new logs while viewing an earlier
    /// day were landing with today's timestamp).
    func entryTimestamp(mealType: MealType, on day: Date? = nil) -> Date {
        let target = day ?? selectedDate
        if Calendar.current.isDateInToday(target) { return Date() }
        let hour: Int
        switch mealType {
        case .breakfast: hour = 8
        case .lunch:     hour = 13
        case .dinner:    hour = 19
        case .snack:     hour = 12
        }
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: target) ?? target
    }

    /// Anchor a time-of-day (from an hour/minute DatePicker, whose date
    /// component is always "today") onto the day this VM is viewing. Sheets
    /// with a Time picker (search, barcode, manual entry, suggestions) must
    /// route their chosen time through this, or a past-day log gets a
    /// today-dated timestamp (past-day logging fix, 2026-07-08/09).
    func anchoredToSelectedDay(_ time: Date) -> Date {
        let cal = Calendar.current
        guard !cal.isDateInToday(selectedDate) else { return time }
        let hm = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: hm.hour ?? 12, minute: hm.minute ?? 0,
                        second: 0, of: selectedDate) ?? selectedDate
    }

    init(database: AppDatabase = .shared) {
        self.database = database
        #if targetEnvironment(simulator)
        seedMockFoodIfNeeded()
        #endif
    }

    #if targetEnvironment(simulator)
    private func seedMockFoodIfNeeded() {
        // Never seed during test runs — tests use AppDatabase.empty() and manage their own data.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let key = "drift_mock_food_seeded_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let cal = Calendar.current
        let iso = DateFormatters.iso8601

        // Seed yesterday and day-before with realistic food logs
        let mockDays: [(dayOffset: Int, meals: [(type: MealType, foods: [(name: String, cal: Double, p: Double, c: Double, f: Double, fiber: Double, hour: Int, min: Int)])])] = [
            (dayOffset: -1, meals: [
                (.breakfast, [
                    ("Oatmeal with Banana", 350, 12, 58, 8, 6, 7, 30),
                    ("Black Coffee", 5, 0, 1, 0, 0, 7, 35),
                ]),
                (.lunch, [
                    ("Grilled Chicken Salad", 420, 38, 18, 22, 4, 12, 30),
                    ("Whole Wheat Bread", 130, 5, 22, 2, 3, 12, 30),
                ]),
                (.dinner, [
                    ("Salmon with Rice", 580, 35, 52, 20, 2, 19, 0),
                    ("Mixed Vegetables", 85, 3, 14, 2, 5, 19, 0),
                ]),
                (.snack, [
                    ("Greek Yogurt", 150, 15, 12, 5, 0, 16, 0),
                ]),
            ]),
            (dayOffset: -2, meals: [
                (.breakfast, [
                    ("Scrambled Eggs (2)", 180, 14, 2, 13, 0, 8, 0),
                    ("Toast with Butter", 160, 3, 20, 7, 1, 8, 0),
                ]),
                (.lunch, [
                    ("Chicken Tikka Masala", 480, 32, 28, 24, 3, 13, 0),
                    ("Basmati Rice", 210, 4, 46, 1, 1, 13, 0),
                ]),
                (.dinner, [
                    ("Pasta Bolognese", 520, 28, 62, 16, 4, 19, 30),
                ]),
            ]),
        ]

        do {
            for day in mockDays {
                guard let date = cal.date(byAdding: .day, value: day.dayOffset, to: Date()) else { continue }
                let dateStr = DateFormatters.dateOnly.string(from: date)
                for meal in day.meals {
                    var mealLog = MealLog(date: dateStr, mealType: meal.type.rawValue)
                    try database.saveMealLog(&mealLog)
                    guard let mealLogId = mealLog.id else { continue }
                    for food in meal.foods {
                        guard let logTime = cal.date(bySettingHour: food.hour, minute: food.min, second: 0, of: date) else { continue }
                        var entry = FoodEntry(
                            mealLogId: mealLogId,
                            foodName: food.name,
                            servingSizeG: 0,
                            servings: 1,
                            calories: food.cal,
                            proteinG: food.p,
                            carbsG: food.c,
                            fatG: food.f,
                            fiberG: food.fiber,
                            loggedAt: iso.string(from: logTime)
                        )
                        try database.saveFoodEntry(&entry)
                    }
                }
            }
            UserDefaults.standard.set(true, forKey: key)
            UserDefaults.standard.synchronize()
        } catch {
            Log.foodLog.error("Mock food seed failed: \(error.localizedDescription)")
        }
    }
    #endif

    func search() {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }
        do {
            searchResults = try database.searchFoods(query: searchQuery)
        } catch {
            Log.foodLog.error("Search failed: \(error.localizedDescription)")
        }
    }

    func loadTodayMeals() {
        do {
            let date = dateString
            let entries = try database.fetchFoodEntries(for: date)
            todayEntries = entries.sorted { $0.loggedAt.replacingOccurrences(of: "T", with: " ") < $1.loggedAt.replacingOccurrences(of: "T", with: " ") }
            todayNutrition = try database.fetchDailyNutrition(for: date)
            // Keep widget in sync with latest nutrition data. Routed through
            // the DriftPlatform seam (WidgetCenterRefresher on iOS, nil on
            // Android until Glance lands) — same call, platform-safe.
            if Calendar.current.isDateInToday(selectedDate) {
                DriftPlatform.widget?.refresh()
            }
        } catch {
            Log.foodLog.error("Failed to load meals: \(error.localizedDescription)")
        }
    }

    /// Load recent, frequent, and saved recipe suggestions.
    func loadSuggestions() {
        recentFoods = (try? database.fetchRecentFoods()) ?? []
        recentEntries = (try? database.fetchRecentEntryNames()) ?? []
        frequentFoods = (try? database.fetchFrequentFoods()) ?? []
        savedRecipes = (try? database.fetchFavorites()) ?? []
        favoriteFoods = (try? database.fetchFavoriteEntryNames()) ?? []
        combos = (try? database.fetchCombos()) ?? []
        suggestionChips = (try? database.fetchSuggestionChips()) ?? []
        // Combo auto-detection scans the WHOLE food_entry table + writes —
        // it used to run on EVERY suggestions load (every tab visit, every
        // logged item), the dominant progressive-lag source (field report
        // 2026-07-09: "slower after a couple of minutes"). A combo needs
        // 2+ distinct DATES to form, so once per calendar day is
        // behaviorally identical.
        let today = DateFormatters.dateOnly.string(from: Date())
        guard UserDefaults.standard.string(forKey: "drift_combo_detect_day") != today else { return }
        UserDefaults.standard.set(today, forKey: "drift_combo_detect_day")
        Task.detached(priority: .background) { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !UserDefaults.standard.bool(forKey: "didClearAutopilotSeedV1") {
                try? AppDatabase.shared.clearAutopilotSeedData()
                UserDefaults.standard.set(true, forKey: "didClearAutopilotSeedV1")
            }
            if !UserDefaults.standard.bool(forKey: "didClearAutoCombosV1") {
                try? AppDatabase.shared.clearAutoDetectedCombos()
                UserDefaults.standard.set(true, forKey: "didClearAutoCombosV1")
            }
            try? AppDatabase.shared.detectAndSaveCombos()
            await MainActor.run {
                self?.combos = (try? AppDatabase.shared.fetchCombos()) ?? []
                self?.suggestionChips = (try? AppDatabase.shared.fetchSuggestionChips()) ?? []
            }
        }
    }

    /// Log all ingredients of a combo as individual food entries.
    func logCombo(_ combo: Food) {
        guard let items = combo.recipeItems else { return }
        let mealType = autoMealType
        quickAddBatch(items.map {
            BatchFoodItem(name: $0.name, calories: $0.calories, proteinG: $0.proteinG,
                          carbsG: $0.carbsG, fatG: $0.fatG, fiberG: $0.fiberG,
                          mealType: mealType, servingSizeG: $0.servingSizeG)
        })
        try? database.trackFoodUsage(name: combo.name, foodId: combo.id, servings: 1,
                                     calories: combo.calories, proteinG: combo.proteinG,
                                     carbsG: combo.carbsG, fatG: combo.fatG, fiberG: combo.fiberG,
                                     servingSizeG: combo.servingSize)
    }

    /// Copy a group of past-day entries to today (one-tap combo copy from history).
    func copyGroupToToday(_ entries: [FoodEntry]) {
        entries.forEach { copyEntryToToday($0) }
        loadTodayMeals()
        NotificationCenter.default.post(name: .foodEntryAdded, object: nil)
    }

    func logFood(_ food: Food, servings: Double, mealType: MealType, loggedAt: Date? = nil, loggedPortion: String? = nil) {
        logFoodCore(food, servings: servings, mealType: mealType, loggedAt: loggedAt, loggedPortion: loggedPortion)
        loadTodayMeals()
        NotificationCenter.default.post(name: .foodEntryAdded, object: nil)
    }

    /// Batch variant — N inserts, then ONE day reload + ONE `.foodEntryAdded`
    /// post (the #949 pattern applied to `logFood`). A 4-item photo/text log
    /// used to reload the day, refresh the widget, and re-render the diary
    /// 4× inside the Log button press — the visible hang (field report
    /// 2026-07-15).
    func logFoods(_ items: [(food: Food, servings: Double)], mealType: MealType) {
        guard !items.isEmpty else { return }
        for item in items {
            logFoodCore(item.food, servings: item.servings, mealType: mealType)
        }
        loadTodayMeals()
        NotificationCenter.default.post(name: .foodEntryAdded, object: nil)
    }

    /// Insert ONE entry (creating the meal log if needed) WITHOUT reloading
    /// the day or posting `.foodEntryAdded` — callers batch those.
    private func logFoodCore(_ food: Food, servings: Double, mealType: MealType, loggedAt: Date? = nil, loggedPortion: String? = nil) {
        FeatureUsage.record("action.log_food")
        do {
            let date = dateString
            // nil ⇒ derive: now for today, meal-canonical time for a past day.
            let effectiveLoggedAt = loggedAt ?? entryTimestamp(mealType: mealType)

            // Find or create meal log for this meal type + date
            let mealLogs = try database.fetchMealLogs(for: date)
            var mealLog = mealLogs.first { $0.mealType == mealType.rawValue }

            if mealLog == nil {
                var newLog = MealLog(date: date, mealType: mealType.rawValue)
                try database.saveMealLog(&newLog)
                mealLog = newLog
            }

            guard let mealLogId = mealLog?.id else { return }

            var entry = FoodEntry(
                mealLogId: mealLogId,
                foodId: food.id,
                foodName: food.name,
                servingSizeG: food.servingSize,
                servings: servings,
                calories: food.calories,
                proteinG: food.proteinG,
                carbsG: food.carbsG,
                fatG: food.fatG,
                fiberG: food.fiberG,
                loggedAt: DateFormatters.iso8601.string(from: effectiveLoggedAt),
                date: date,
                mealType: mealType.rawValue,
                loggedPortion: loggedPortion
            )
            try database.saveFoodEntry(&entry)
            try? database.trackFoodUsage(name: food.name, foodId: food.id, servings: servings,
                                         calories: food.calories, proteinG: food.proteinG,
                                         carbsG: food.carbsG, fatG: food.fatG, fiberG: food.fiberG,
                                         servingSizeG: food.servingSize)
            // Conversation "recent entries" are a today-only shortcut — don't
            // push back-filled past-day logs into it.
            if let id = entry.id, isToday {
                ConversationState.shared.pushRecentEntry(.init(
                    id: id, name: food.name, mealType: mealType.rawValue,
                    calories: food.calories.isFinite ? Int(food.calories.rounded()) : 0,
                    loggedAt: effectiveLoggedAt
                ))
            }
        } catch {
            Log.foodLog.error("Failed to log food: \(error.localizedDescription)")
        }
    }

    /// Copy a food entry to today (used when viewing a past day).
    func copyEntryToToday(_ entry: FoodEntry) {
        let todayStr = DateFormatters.todayString
        let mealType = MealType(rawValue: entry.mealType ?? "") ?? .snack
        do {
            let mealLogs = try database.fetchMealLogs(for: todayStr)
            var mealLog = mealLogs.first { $0.mealType == mealType.rawValue }
            if mealLog == nil {
                var newLog = MealLog(date: todayStr, mealType: mealType.rawValue)
                try database.saveMealLog(&newLog)
                mealLog = newLog
            }
            guard let mealLogId = mealLog?.id else { return }
            var newEntry = FoodEntry(
                mealLogId: mealLogId, foodId: entry.foodId, foodName: entry.foodName,
                servingSizeG: entry.servingSizeG, servings: entry.servings,
                calories: entry.calories, proteinG: entry.proteinG,
                carbsG: entry.carbsG, fatG: entry.fatG, fiberG: entry.fiberG,
                loggedAt: DateFormatters.iso8601.string(from: Date()),
                date: todayStr, mealType: mealType.rawValue
            )
            try database.saveFoodEntry(&newEntry)
            try? database.trackFoodUsage(name: entry.foodName, foodId: entry.foodId, servings: entry.servings,
                                         calories: entry.calories, proteinG: entry.proteinG,
                                         carbsG: entry.carbsG, fatG: entry.fatG, fiberG: entry.fiberG,
                                         servingSizeG: entry.servingSizeG)
        } catch {
            Log.foodLog.error("Failed to copy to today: \(error.localizedDescription)")
        }
    }

    /// Quick log a food with last-used serving size (or 1) and auto meal type.
    func quickLogFood(_ food: Food) {
        let lastUsed = recentEntries.first(where: { $0.name == food.name })?.lastServings ?? 1
        logFood(food, servings: lastUsed, mealType: autoMealType)
    }

    #if DRIFT_IOS_APP
    /// Log each RecipeItem as its own FoodEntry — one row per ingredient.
    /// Shared helper so AI-chat "log breakfast avocado toast and coffee"
    /// (QuickAddView) and Food-tab re-log of a saved combo (ComboLogSheet)
    /// produce the same diary rows. `perItemServings` lets ComboLogSheet pass
    /// per-checkbox servings; `recipeServings` lets QuickAddView scale the
    /// whole stack. Callers that don't need either just pass `items` and
    /// `mealType`. (iOS-app-gated: RecipeItem is a QuickAddView type; the
    /// Android port logs combos via `logCombo`.)
    func logRecipeItems(_ items: [QuickAddView.RecipeItem],
                        recipeServings: Double = 1,
                        perItemServings: [UUID: Double] = [:],
                        mealType: MealType,
                        loggedAt: String? = nil) {
        quickAddBatch(items.compactMap { item -> BatchFoodItem? in
            let s = (perItemServings[item.id] ?? 1) * recipeServings
            guard s > 0 else { return nil }
            return BatchFoodItem(name: item.name,
                                 calories: item.calories * s,
                                 proteinG: item.proteinG * s,
                                 carbsG: item.carbsG * s,
                                 fatG: item.fatG * s,
                                 fiberG: item.fiberG * s,
                                 mealType: mealType,
                                 loggedAt: loggedAt,
                                 servingSizeG: item.servingSizeG * s,
                                 servings: 1)
        })
    }
    #endif

    /// One food entry queued for a batched insert. (#949)
    struct BatchFoodItem {
        let name: String
        let calories: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let fiberG: Double
        let mealType: MealType
        var loggedAt: String? = nil
        var servingSizeG: Double = 0
        var servings: Double = 1
        var date: String? = nil
    }

    /// Insert ONE entry (creating the meal log if needed) WITHOUT reloading the
    /// day or posting `.foodEntryAdded`. Callers batch those so an N-item log
    /// reloads + refreshes the widget + notifies ONCE, not N times. (#949)
    @discardableResult
    private func quickAddCore(name: String, calories: Double, proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double, mealType: MealType, loggedAt: String? = nil, servingSizeG: Double = 0, servings: Double = 1, date: String? = nil) -> Bool {
        FeatureUsage.record("action.quick_add")
        do {
            let date = date ?? dateString
            let mealLogs = try database.fetchMealLogs(for: date)
            var mealLog = mealLogs.first { $0.mealType == mealType.rawValue }

            if mealLog == nil {
                var newLog = MealLog(date: date, mealType: mealType.rawValue)
                try database.saveMealLog(&newLog)
                mealLog = newLog
            }

            guard let mealLogId = mealLog?.id else { return false }

            // nil loggedAt ⇒ derive from the TARGET day: now for today,
            // meal-canonical time for a back-filled past day (so it doesn't
            // land with a wrong "now" timestamp on an earlier day).
            let parsedDay = DateFormatters.dateOnly.date(from: date) ?? Date()
            let effectiveLoggedAt = loggedAt
                ?? DateFormatters.iso8601.string(from: entryTimestamp(mealType: mealType, on: parsedDay))
            var entry = FoodEntry(
                mealLogId: mealLogId,
                foodName: name,
                servingSizeG: servingSizeG,
                servings: servings,
                calories: calories,
                proteinG: proteinG,
                carbsG: carbsG,
                fatG: fatG,
                fiberG: fiberG,
                loggedAt: effectiveLoggedAt,
                date: date,
                mealType: mealType.rawValue
            )
            try database.saveFoodEntry(&entry)
            // Only track usage for named foods (not generic "Quick Add")
            if name != "Quick Add" && !name.isEmpty {
                try? database.trackFoodUsage(name: name, foodId: nil, servings: 1,
                                             calories: calories, proteinG: proteinG,
                                             carbsG: carbsG, fatG: fatG, fiberG: fiberG,
                                             servingSizeG: servingSizeG)
            }
            if let id = entry.id, date == DateFormatters.todayString,
               name != "Quick Add" && !name.isEmpty {
                ConversationState.shared.pushRecentEntry(.init(
                    id: id, name: name, mealType: mealType.rawValue,
                    calories: calories.isFinite ? Int(calories.rounded()) : 0,
                    loggedAt: Date()
                ))
            }
            return true
        } catch {
            Log.foodLog.error("Failed to quick add: \(error.localizedDescription)")
            return false
        }
    }

    func quickAdd(name: String, calories: Double, proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double, mealType: MealType, loggedAt: String? = nil, servingSizeG: Double = 0, servings: Double = 1, date: String? = nil) {
        quickAddCore(name: name, calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG, fiberG: fiberG, mealType: mealType, loggedAt: loggedAt, servingSizeG: servingSizeG, servings: servings, date: date)
        loadTodayMeals()
        // Tell the Food-diary surface (which lives on its OWN viewModel
        // instance and only reloads on this notification) that an entry
        // landed — otherwise logging from the FAB's LogMealSheet writes to
        // the DB but the diary behind it never refreshes (field bug).
        NotificationCenter.default.post(name: .foodEntryAdded, object: nil)
    }

    /// Batch insert — each item is written individually (identical per-item
    /// semantics to `quickAdd`), but the day reload + widget refresh +
    /// `.foodEntryAdded` post fire exactly ONCE at the end. An N-item
    /// recipe/combo/copy used to trigger N reloads + N widget refreshes. (#949)
    func quickAddBatch(_ items: [BatchFoodItem]) {
        guard !items.isEmpty else { return }
        var any = false
        for it in items {
            if quickAddCore(name: it.name, calories: it.calories, proteinG: it.proteinG,
                            carbsG: it.carbsG, fatG: it.fatG, fiberG: it.fiberG,
                            mealType: it.mealType, loggedAt: it.loggedAt,
                            servingSizeG: it.servingSizeG, servings: it.servings, date: it.date) {
                any = true
            }
        }
        guard any else { return }
        loadTodayMeals()
        NotificationCenter.default.post(name: .foodEntryAdded, object: nil)
    }

    func updateEntryLoggedAt(id: Int64, loggedAt: String) {
        do {
            try database.updateFoodEntryLoggedAt(id: id, loggedAt: loggedAt)
        } catch {
            Log.foodLog.error("Failed to update entry time: \(error.localizedDescription)")
        }
    }

    func updateEntryMealType(id: Int64, mealType: MealType) {
        do {
            try database.updateFoodEntryMealType(id: id, mealType: mealType.rawValue)
        } catch {
            Log.foodLog.error("Failed to update meal type: \(error.localizedDescription)")
        }
    }

    func updateEntryServings(id: Int64, servings: Double) {
        do {
            try database.updateFoodEntryServings(id: id, servings: servings)
            loadTodayMeals()
        } catch {
            Log.foodLog.error("Failed to update entry: \(error.localizedDescription)")
        }
    }

    func deleteEntry(id: Int64) {
        do {
            try database.deleteFoodEntry(id: id)
            loadTodayMeals()
        } catch {
            Log.foodLog.error("Failed to delete entry: \(error.localizedDescription)")
        }
    }

    func goToDate(_ date: Date) {
        selectedDate = date
        loadTodayMeals()
        loadPlantPoints()
    }

    func goToPreviousDay() { if let d = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) { goToDate(d) } }
    func goToNextDay() { if let d = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) { goToDate(d) } }
    var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    /// Load plant points for the week containing selectedDate.
    func loadPlantPoints() {
        let cal = Calendar.current
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: selectedDate) else { return }
        let weekStart = DateFormatters.dateOnly.string(from: weekInterval.start)
        let weekEndDate = cal.date(byAdding: .day, value: -1, to: weekInterval.end) ?? weekInterval.end
        let weekEnd = DateFormatters.dateOnly.string(from: weekEndDate)

        do {
            // NOVA-aware plant point counting
            let weekItems = try database.fetchFoodItemsForPlantPoints(from: weekStart, to: weekEnd)
            weeklyPlantPoints = PlantPointsService.calculate(from: weekItems)

            // Count new plants added today vs rest of week
            let todayStr = dateString
            let todayItems = try database.fetchFoodItemsForPlantPoints(from: todayStr, to: todayStr)
            let todayPlants = PlantPointsService.calculate(from: todayItems)

            // Plants logged before today this week
            let yesterdayDate = cal.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            let beforeToday = DateFormatters.dateOnly.string(from: yesterdayDate)
            if weekStart <= beforeToday {
                let priorItems = try database.fetchFoodItemsForPlantPoints(from: weekStart, to: beforeToday)
                let priorPlants = PlantPointsService.calculate(from: priorItems)
                let priorSet = Set(priorPlants.uniquePlants + priorPlants.uniqueHerbsSpices)
                let todaySet = Set(todayPlants.uniquePlants + todayPlants.uniqueHerbsSpices)
                dailyNewPlants = todaySet.subtracting(priorSet).count
            } else {
                dailyNewPlants = todayPlants.plantCount
            }
        } catch {
            Log.foodLog.error("Failed to load plant points: \(error.localizedDescription)")
        }
    }

    var macroTargets: WeightGoal.MacroTargets? {
        WeightGoal.load()?.macroTargets(currentWeightKg: WeightTrendService.shared.trendWeight)
    }

    func toggleFavorite(name: String, foodId: Int64?) {
        FoodService.toggleFavorite(name: name, foodId: foodId)
    }

    func isFavorite(name: String) -> Bool {
        FoodService.isFavorite(name: name)
    }

    func yesterdayCalories() -> Double? {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) else { return nil }
        let dateStr = DateFormatters.dateOnly.string(from: yesterday)
        let nutrition = (try? database.fetchDailyNutrition(for: dateStr)) ?? .zero
        return nutrition.calories > 0 ? nutrition.calories : nil
    }

    func copyFromYesterday() {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) else { return }
        let dateStr = DateFormatters.dateOnly.string(from: yesterday)
        do {
            let logs = try database.fetchMealLogs(for: dateStr)
            guard !logs.isEmpty else { return }
            let iso = DateFormatters.iso8601
            let todayDate = selectedDate
            let cal = Calendar.current
            var batch: [BatchFoodItem] = []
            for log in logs {
                guard let logId = log.id else { continue }
                let entries = try database.fetchFoodEntries(forMealLog: logId)
                guard !entries.isEmpty else { continue }
                for entry in entries {
                    let mappedLoggedAt: String
                    var entryHour: Int = cal.component(.hour, from: todayDate)
                    if let original = iso.date(from: entry.loggedAt) ?? DateFormatters.sqliteDatetime.date(from: entry.loggedAt) {
                        let time = cal.dateComponents([.hour, .minute, .second], from: original)
                        entryHour = time.hour ?? entryHour
                        var today = cal.dateComponents([.year, .month, .day], from: todayDate)
                        today.hour = time.hour; today.minute = time.minute; today.second = time.second
                        mappedLoggedAt = iso.string(from: cal.date(from: today) ?? todayDate)
                    } else {
                        mappedLoggedAt = iso.string(from: todayDate)
                    }
                    // Reclassify by the entry's actual hour — don't carry over yesterday's meal category
                    let mealType = MealType.fromHour(entryHour)
                    batch.append(BatchFoodItem(name: entry.foodName, calories: entry.totalCalories,
                                               proteinG: entry.totalProtein, carbsG: entry.totalCarbs,
                                               fatG: entry.totalFat, fiberG: entry.totalFiber,
                                               mealType: mealType, loggedAt: mappedLoggedAt))
                }
            }
            quickAddBatch(batch)
        } catch {
            Log.foodLog.error("Failed to copy from yesterday: \(error.localizedDescription)")
        }
    }

    func copyAllToToday(entries: [FoodEntry]) {
        let cal = Calendar.current
        let todayDate = Date()
        let iso = DateFormatters.iso8601
        quickAddBatch(entries.map { entry in
            let mappedLoggedAt: String
            if let original = iso.date(from: entry.loggedAt) ?? DateFormatters.sqliteDatetime.date(from: entry.loggedAt) {
                let time = cal.dateComponents([.hour, .minute, .second], from: original)
                var today = cal.dateComponents([.year, .month, .day], from: todayDate)
                today.hour = time.hour; today.minute = time.minute; today.second = time.second
                mappedLoggedAt = iso.string(from: cal.date(from: today) ?? todayDate)
            } else {
                mappedLoggedAt = iso.string(from: todayDate)
            }
            let mealType = MealType(rawValue: entry.mealType ?? "") ?? autoMealType
            return BatchFoodItem(name: entry.foodName, calories: entry.totalCalories,
                                 proteinG: entry.totalProtein, carbsG: entry.totalCarbs,
                                 fatG: entry.totalFat, fiberG: entry.totalFiber,
                                 mealType: mealType, loggedAt: mappedLoggedAt,
                                 servingSizeG: entry.servingSizeG, date: DateFormatters.todayString)
        })
    }

    func swapEntries(_ movedIndex: Int, _ targetIndex: Int, in entries: [FoodEntry]) {
        guard movedIndex >= 0, movedIndex < entries.count,
              targetIndex >= 0, targetIndex < entries.count,
              let movedId = entries[movedIndex].id, let targetId = entries[targetIndex].id else { return }
        var timeMoved = entries[movedIndex].loggedAt
        var timeTarget = entries[targetIndex].loggedAt
        if timeMoved == timeTarget,
           let date = DateFormatters.iso8601.date(from: timeMoved) ?? DateFormatters.sqliteDatetime.date(from: timeMoved) {
            let iso = DateFormatters.iso8601
            timeMoved = targetIndex < movedIndex
                ? iso.string(from: date.addingTimeInterval(-1))
                : iso.string(from: date.addingTimeInterval(1))
        }
        updateEntryLoggedAt(id: movedId, loggedAt: timeTarget)
        updateEntryLoggedAt(id: targetId, loggedAt: timeMoved)
        loadTodayMeals()
    }

    /// Days with food logged in last N days (for consistency heatmap).
    /// Uses single batch query instead of N individual queries.
    func loggedDays(last days: Int = 30) -> [Date: Double] {
        let cal = Calendar.current
        guard let startDate = cal.date(byAdding: .day, value: -(days - 1), to: Date()) else { return [:] }
        let startStr = DateFormatters.dateOnly.string(from: startDate)
        let endStr = DateFormatters.dateOnly.string(from: Date())

        let dailyCals = (try? database.fetchDailyCalories(from: startStr, to: endStr)) ?? [:]

        var result: [Date: Double] = [:]
        for offset in 0..<days {
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let dateStr = DateFormatters.dateOnly.string(from: date)
            result[cal.startOfDay(for: date)] = dailyCals[dateStr] ?? 0
        }
        return result
    }

    /// Calories logged per day within the calendar month containing `date`,
    /// keyed by `startOfDay`. Powers the month-grid picker's per-day "food
    /// logged" dots — unlike `loggedDays(last:)`, this works for any month
    /// the user scrolls back to, not just a trailing window from today.
    /// Only days with a positive total are returned; callers treat a missing
    /// key as "nothing logged".
    func loggedDays(inMonth date: Date) -> [Date: Double] {
        let cal = Calendar.current
        guard let monthInterval = cal.dateInterval(of: .month, for: date) else { return [:] }
        // dateInterval.end is the first instant of the *next* month — step
        // back a day so the query's end bound lands on this month's last day.
        let lastDay = cal.date(byAdding: .day, value: -1, to: monthInterval.end) ?? monthInterval.end
        let startStr = DateFormatters.dateOnly.string(from: monthInterval.start)
        let endStr = DateFormatters.dateOnly.string(from: lastDay)

        let dailyCals = (try? database.fetchDailyCalories(from: startStr, to: endStr)) ?? [:]

        var result: [Date: Double] = [:]
        for (dateStr, cals) in dailyCals where cals > 0 {
            if let d = DateFormatters.dateOnly.date(from: dateStr) {
                result[cal.startOfDay(for: d)] = cals
            }
        }
        return result
    }
}
