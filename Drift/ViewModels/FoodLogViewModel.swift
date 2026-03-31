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
    }

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
            todayEntries = all.sorted { $0.createdAt < $1.createdAt }
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

    /// Quick log a food with 1 serving and auto meal type.
    func quickLogFood(_ food: Food) {
        logFood(food, servings: 1, mealType: autoMealType)
    }

    func quickAdd(name: String, calories: Double, proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double, mealType: MealType) {
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

            var entry = FoodEntry(
                mealLogId: mealLogId,
                foodName: name,
                servingSizeG: 0,
                servings: 1,
                calories: calories,
                proteinG: proteinG,
                carbsG: carbsG,
                fatG: fatG,
                fiberG: fiberG
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
    func loggedDays(last days: Int = 30) -> [Date: Double] {
        let cal = Calendar.current
        var result: [Date: Double] = [:]
        for offset in 0..<days {
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let dateStr = DateFormatters.dateOnly.string(from: date)
            let nutrition = try? database.fetchDailyNutrition(for: dateStr)
            result[cal.startOfDay(for: date)] = nutrition?.calories ?? 0
        }
        return result
    }
}
