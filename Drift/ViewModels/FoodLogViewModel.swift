import Foundation
import Observation

@MainActor
@Observable
final class FoodLogViewModel {
    private let database: AppDatabase

    var searchQuery: String = ""
    var searchResults: [Food] = []
    var todayMeals: [MealType: [FoodEntry]] = [:]
    var todayNutrition: DailyNutrition = .zero
    var todayEntries: [FoodEntry] = []
    var selectedDate: Date = Date()
    var recentFoods: [Food] = []
    var recentEntries: [RecentEntry] = []
    var frequentFoods: [Food] = []
    var savedRecipes: [FavoriteFood] = []
    var favoriteFoods: [RecentEntry] = []

    var dateString: String {
        DateFormatters.dateOnly.string(from: selectedDate)
    }

    /// Auto-assign meal type based on time of day (used internally, hidden from UI).
    var autoMealType: MealType {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<21: return .dinner
        default: return .snack
        }
    }

    init(database: AppDatabase = .shared) {
        self.database = database
        #if targetEnvironment(simulator)
        seedMockFoodIfNeeded()
        #endif
    }

    #if targetEnvironment(simulator)
    private func seedMockFoodIfNeeded() {
        let key = "drift_mock_food_seeded_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let cal = Calendar.current
        let iso = ISO8601DateFormatter()

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
            let mealLogs = try database.fetchMealLogs(for: date)
            var grouped: [MealType: [FoodEntry]] = [:]
            var all: [FoodEntry] = []

            for log in mealLogs {
                guard let mealType = MealType(rawValue: log.mealType),
                      let logId = log.id else { continue }
                let entries = try database.fetchFoodEntries(forMealLog: logId)
                grouped[mealType, default: []].append(contentsOf: entries)
                all.append(contentsOf: entries)
            }

            todayMeals = grouped
            todayEntries = all.sorted { $0.loggedAt < $1.loggedAt }
            todayNutrition = try database.fetchDailyNutrition(for: date)
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
    }

    func logFood(_ food: Food, servings: Double, mealType: MealType) {
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
                fiberG: food.fiberG
            )
            try database.saveFoodEntry(&entry)
            try? database.trackFoodUsage(name: food.name, foodId: food.id, servings: servings)
            loadTodayMeals()
        } catch {
            Log.foodLog.error("Failed to log food: \(error.localizedDescription)")
        }
    }

    /// Quick log a food with last-used serving size (or 1) and auto meal type.
    func quickLogFood(_ food: Food) {
        let lastUsed = recentEntries.first(where: { $0.name == food.name })?.lastServings ?? 1
        logFood(food, servings: lastUsed, mealType: autoMealType)
    }

    func quickAdd(name: String, calories: Double, proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double, mealType: MealType, loggedAt: String? = nil) {
        do {
            let date = dateString
            let mealLogs = try database.fetchMealLogs(for: date)
            var mealLog = mealLogs.first { $0.mealType == mealType.rawValue }

            if mealLog == nil {
                var newLog = MealLog(date: date, mealType: mealType.rawValue)
                try database.saveMealLog(&newLog)
                mealLog = newLog
            }

            guard let mealLogId = mealLog?.id else { return }

            let now = ISO8601DateFormatter().string(from: Date())
            var entry = FoodEntry(
                mealLogId: mealLogId,
                foodName: name,
                servingSizeG: 0,
                servings: 1,
                calories: calories,
                proteinG: proteinG,
                carbsG: carbsG,
                fatG: fatG,
                fiberG: fiberG,
                loggedAt: loggedAt ?? now
            )
            try database.saveFoodEntry(&entry)
            try? database.trackFoodUsage(name: name, foodId: nil, servings: 1)
            loadTodayMeals()
        } catch {
            Log.foodLog.error("Failed to quick add: \(error.localizedDescription)")
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
    }

    func goToPreviousDay() { if let d = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) { goToDate(d) } }
    func goToNextDay() { if let d = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) { goToDate(d) } }
    var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

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
