import Foundation
import Observation

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

    var dateString: String {
        DateFormatters.dateOnly.string(from: selectedDate)
    }

    /// Auto-assign meal type: inherit from a recent entry logged within 3h (so a second bowl at
    /// 10am after a 7am breakfast stays `breakfast`), else fall back to hour ranges.
    var autoMealType: MealType {
        MealType.resolve(now: Date(), recentEntries: todayEntries)
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
            // Keep widget in sync with latest nutrition data
            if Calendar.current.isDateInToday(selectedDate) {
                WidgetDataProvider.refreshWidgetData()
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
        Task.detached(priority: .background) { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            try? AppDatabase.shared.detectAndSaveCombos()
            await MainActor.run { self?.combos = (try? AppDatabase.shared.fetchCombos()) ?? [] }
        }
    }

    /// Log all ingredients of a combo as individual food entries.
    func logCombo(_ combo: Food) {
        guard let items = combo.recipeItems else { return }
        let mealType = autoMealType
        for item in items {
            quickAdd(name: item.name, calories: item.calories, proteinG: item.proteinG,
                     carbsG: item.carbsG, fatG: item.fatG, fiberG: item.fiberG,
                     mealType: mealType, servingSizeG: item.servingSizeG, servings: 1)
        }
        try? database.trackFoodUsage(name: combo.name, foodId: combo.id, servings: 1,
                                     calories: combo.calories, proteinG: combo.proteinG,
                                     carbsG: combo.carbsG, fatG: combo.fatG, fiberG: combo.fiberG,
                                     servingSizeG: combo.servingSize)
    }

    /// Copy a group of past-day entries to today (one-tap combo copy from history).
    func copyGroupToToday(_ entries: [FoodEntry]) {
        entries.forEach { copyEntryToToday($0) }
        loadTodayMeals()
    }

    func logFood(_ food: Food, servings: Double, mealType: MealType, loggedAt: Date = Date()) {
        do {
            let date = dateString

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
                loggedAt: ISO8601DateFormatter().string(from: loggedAt),
                date: date,
                mealType: mealType.rawValue
            )
            try database.saveFoodEntry(&entry)
            try? database.trackFoodUsage(name: food.name, foodId: food.id, servings: servings,
                                         calories: food.calories, proteinG: food.proteinG,
                                         carbsG: food.carbsG, fatG: food.fatG, fiberG: food.fiberG,
                                         servingSizeG: food.servingSize)
            if let id = entry.id {
                ConversationState.shared.pushRecentEntry(.init(
                    id: id, name: food.name, mealType: mealType.rawValue,
                    calories: Int(food.calories), loggedAt: loggedAt
                ))
            }
            loadTodayMeals()
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

    func quickAdd(name: String, calories: Double, proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double, mealType: MealType, loggedAt: String? = nil, servingSizeG: Double = 0, servings: Double = 1, date: String? = nil) {
        do {
            let date = date ?? dateString
            let mealLogs = try database.fetchMealLogs(for: date)
            var mealLog = mealLogs.first { $0.mealType == mealType.rawValue }

            if mealLog == nil {
                var newLog = MealLog(date: date, mealType: mealType.rawValue)
                try database.saveMealLog(&newLog)
                mealLog = newLog
            }

            guard let mealLogId = mealLog?.id else { return }

            let now = DateFormatters.iso8601.string(from: Date())
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
                loggedAt: loggedAt ?? now,
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
                    calories: Int(calories), loggedAt: Date()
                ))
            }
            loadTodayMeals()
        } catch {
            Log.foodLog.error("Failed to quick add: \(error.localizedDescription)")
        }
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
        WeightGoal.load()?.macroTargets(currentWeightKg: WeightTrendService.shared.latestWeightKg)
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
        let totals = FoodService.getDailyTotals(date: dateStr)
        return totals.eaten > 0 ? Double(totals.eaten) : nil
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
                    quickAdd(name: entry.foodName, calories: entry.totalCalories,
                             proteinG: entry.totalProtein, carbsG: entry.totalCarbs,
                             fatG: entry.totalFat, fiberG: entry.totalFiber,
                             mealType: mealType, loggedAt: mappedLoggedAt)
                }
            }
        } catch {
            Log.foodLog.error("Failed to copy from yesterday: \(error.localizedDescription)")
        }
    }

    func copyAllToToday(entries: [FoodEntry]) {
        let cal = Calendar.current
        let todayDate = Date()
        let iso = DateFormatters.iso8601
        for entry in entries {
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
            quickAdd(name: entry.foodName, calories: entry.totalCalories,
                     proteinG: entry.totalProtein, carbsG: entry.totalCarbs,
                     fatG: entry.totalFat, fiberG: entry.totalFiber,
                     mealType: mealType, loggedAt: mappedLoggedAt,
                     servingSizeG: entry.servingSizeG, date: DateFormatters.todayString)
        }
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
}
