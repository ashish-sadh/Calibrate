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
    var selectedDate: Date = Date()

    var dateString: String {
        DateFormatters.dateOnly.string(from: selectedDate)
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
            print("Search failed: \(error)")
        }
    }

    func loadTodayMeals() {
        do {
            let date = dateString
            let mealLogs = try database.fetchMealLogs(for: date)
            var grouped: [MealType: [FoodEntry]] = [:]

            for log in mealLogs {
                guard let mealType = MealType(rawValue: log.mealType),
                      let logId = log.id else { continue }
                let entries = try database.fetchFoodEntries(forMealLog: logId)
                grouped[mealType, default: []].append(contentsOf: entries)
            }

            todayMeals = grouped
            todayNutrition = try database.fetchDailyNutrition(for: date)
        } catch {
            print("Failed to load meals: \(error)")
        }
    }

    func logFood(_ food: Food, servings: Double, mealType: MealType) {
        do {
            let date = dateString

            // Find or create meal log for this meal type + date
            var mealLogs = try database.fetchMealLogs(for: date)
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
            loadTodayMeals()
        } catch {
            print("Failed to log food: \(error)")
        }
    }

    func quickAdd(name: String, calories: Double, proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double, mealType: MealType) {
        do {
            let date = dateString
            var mealLogs = try database.fetchMealLogs(for: date)
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
            loadTodayMeals()
        } catch {
            print("Failed to quick add: \(error)")
        }
    }

    func deleteEntry(id: Int64) {
        do {
            try database.deleteFoodEntry(id: id)
            loadTodayMeals()
        } catch {
            print("Failed to delete entry: \(error)")
        }
    }
}
