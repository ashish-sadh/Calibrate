import Foundation
import Testing
@testable import Drift

// MARK: - Food Flow Integration Tests
// These test full user action sequences through the ViewModel layer,
// verifying that date navigation + data operations produce correct results.
// This class of test catches bugs where a ViewModel method works in isolation
// but the View calls it with wrong arguments (e.g. wrong date).

// MARK: - Date Navigation & Data Isolation

@Test func entriesDoNotLeakAcrossDates() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Log food on 3 different dates
    let today = Date()
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
    let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: today)!

    await vm.goToDate(twoDaysAgo)
    await vm.quickAdd(name: "Two Days Ago Meal", calories: 100, proteinG: 10, carbsG: 10, fatG: 5, fiberG: 1, mealType: .lunch)

    await vm.goToDate(yesterday)
    await vm.quickAdd(name: "Yesterday Meal", calories: 200, proteinG: 20, carbsG: 20, fatG: 10, fiberG: 2, mealType: .lunch)

    await vm.goToDate(today)
    await vm.quickAdd(name: "Today Meal", calories: 300, proteinG: 30, carbsG: 30, fatG: 15, fiberG: 3, mealType: .lunch)

    // Verify each date has exactly its own entries
    await vm.goToDate(twoDaysAgo)
    #expect(await vm.todayEntries.count == 1, "Two days ago should have exactly 1 entry")
    #expect(await vm.todayEntries[0].foodName == "Two Days Ago Meal")

    await vm.goToDate(yesterday)
    #expect(await vm.todayEntries.count == 1, "Yesterday should have exactly 1 entry")
    #expect(await vm.todayEntries[0].foodName == "Yesterday Meal")

    await vm.goToDate(today)
    #expect(await vm.todayEntries.count == 1, "Today should have exactly 1 entry")
    #expect(await vm.todayEntries[0].foodName == "Today Meal")
}

@Test func navigateBackAndForthPreservesData() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Log on today
    await vm.quickAdd(name: "Breakfast", calories: 400, proteinG: 25, carbsG: 40, fatG: 15, fiberG: 3, mealType: .breakfast)
    #expect(await vm.todayEntries.count == 1)

    // Navigate away and back
    await vm.goToPreviousDay()
    #expect(await vm.todayEntries.isEmpty, "Yesterday should be empty")

    await vm.goToNextDay()
    #expect(await vm.todayEntries.count == 1, "Today's entry should still be there")
    #expect(await vm.todayEntries[0].foodName == "Breakfast")
}

@Test func rapidDateNavigationDoesNotCorruptData() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Log entries on today
    await vm.quickAdd(name: "Stable Entry", calories: 500, proteinG: 30, carbsG: 50, fatG: 20, fiberG: 5, mealType: .lunch)

    // Rapidly navigate back and forth
    for _ in 0..<10 {
        await vm.goToPreviousDay()
        await vm.goToNextDay()
    }

    // Data should be intact
    #expect(await vm.todayEntries.count == 1, "Entry should survive rapid navigation")
    #expect(await vm.todayEntries[0].foodName == "Stable Entry")
    #expect(await vm.todayNutrition.calories == 500)
}

// MARK: - Delete on Past Day

@Test func deleteOnPastDayDoesNotAffectToday() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Log on today
    await vm.quickAdd(name: "Today Food", calories: 300, proteinG: 20, carbsG: 30, fatG: 10, fiberG: 3, mealType: .lunch)

    // Log on yesterday
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    await vm.goToDate(yesterday)
    await vm.quickAdd(name: "Yesterday Food", calories: 200, proteinG: 15, carbsG: 20, fatG: 8, fiberG: 2, mealType: .lunch)

    // Delete yesterday's entry
    let yesterdayEntries = await vm.todayEntries
    guard let entry = yesterdayEntries.first else {
        #expect(Bool(false), "Yesterday should have an entry")
        return
    }
    await vm.deleteEntry(id: entry.id!)

    // Yesterday should be empty now
    #expect(await vm.todayEntries.isEmpty, "Yesterday should be empty after delete")

    // Today should be untouched
    await vm.goToDate(Date())
    #expect(await vm.todayEntries.count == 1, "Today's entry should not be affected")
    #expect(await vm.todayEntries[0].foodName == "Today Food")
}

@Test func deleteAllEntriesOnPastDayDoesNotAffectToday() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Log on today
    await vm.quickAdd(name: "Today A", calories: 100, proteinG: 10, carbsG: 10, fatG: 5, fiberG: 1, mealType: .breakfast)
    await vm.quickAdd(name: "Today B", calories: 200, proteinG: 20, carbsG: 20, fatG: 10, fiberG: 2, mealType: .lunch)

    // Log on yesterday
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    await vm.goToDate(yesterday)
    await vm.quickAdd(name: "Old A", calories: 150, proteinG: 12, carbsG: 15, fatG: 6, fiberG: 1, mealType: .lunch)
    await vm.quickAdd(name: "Old B", calories: 250, proteinG: 22, carbsG: 25, fatG: 11, fiberG: 3, mealType: .dinner)

    // Delete all yesterday entries
    let entries = await vm.todayEntries
    for e in entries {
        await vm.deleteEntry(id: e.id!)
    }
    #expect(await vm.todayEntries.isEmpty, "Yesterday should be empty")

    // Today untouched
    await vm.goToDate(Date())
    #expect(await vm.todayEntries.count == 2, "Today should still have 2 entries")
    #expect(await vm.todayNutrition.calories == 300)
}

// MARK: - Edit on Past Day

@Test func editServingsOnPastDayDoesNotAffectToday() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Log same food on both days
    await vm.quickAdd(name: "Rice", calories: 200, proteinG: 4, carbsG: 45, fatG: 1, fiberG: 1, mealType: .lunch)

    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    await vm.goToDate(yesterday)
    await vm.quickAdd(name: "Rice", calories: 200, proteinG: 4, carbsG: 45, fatG: 1, fiberG: 1, mealType: .lunch)

    // Edit yesterday's servings
    let yesterdayEntries = await vm.todayEntries
    guard let entry = yesterdayEntries.first else { return }
    await vm.updateEntryServings(id: entry.id!, servings: 3.0)

    // Today's Rice should still be 1 serving
    await vm.goToDate(Date())
    let todayEntries = await vm.todayEntries
    guard let todayEntry = todayEntries.first else { return }
    #expect(todayEntry.servings == 1.0, "Today's servings should be unaffected, got \(todayEntry.servings)")
}

// MARK: - Copy Flows (full user action sequence)

@Test func copyAllFromPastDayThenDeleteSourceLeavesTodayIntact() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Log on a past date
    let pastDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
    await vm.goToDate(pastDate)
    await vm.quickAdd(name: "Meal X", calories: 400, proteinG: 30, carbsG: 40, fatG: 15, fiberG: 4, mealType: .lunch)
    await vm.quickAdd(name: "Meal Y", calories: 300, proteinG: 25, carbsG: 30, fatG: 12, fiberG: 3, mealType: .dinner)

    // Copy all to today (simulating the view's copyAllToToday flow)
    let todayStr = DateFormatters.todayString
    let pastEntries = await vm.todayEntries
    for entry in pastEntries {
        await vm.quickAdd(name: entry.foodName, calories: entry.totalCalories,
                          proteinG: entry.totalProtein, carbsG: entry.totalCarbs,
                          fatG: entry.totalFat, fiberG: entry.totalFiber,
                          mealType: MealType(rawValue: entry.mealType ?? "lunch") ?? .lunch,
                          date: todayStr)
    }

    // Now delete the source entries
    let sourceEntries = await vm.todayEntries
    for e in sourceEntries {
        await vm.deleteEntry(id: e.id!)
    }
    #expect(await vm.todayEntries.isEmpty, "Source day should be empty after delete")

    // Today should still have the copies
    await vm.goToDate(Date())
    #expect(await vm.todayEntries.count == 2, "Today should still have 2 copied entries")
    #expect(await vm.todayNutrition.calories == 700, "Total should be 400 + 300")
}

@Test func copySingleEntryMultipleTimesCreatesDuplicates() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Log on yesterday
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    await vm.goToDate(yesterday)
    await vm.quickAdd(name: "Protein Shake", calories: 150, proteinG: 30, carbsG: 5, fatG: 2, fiberG: 0, mealType: .snack)

    let entries = await vm.todayEntries
    guard let entry = entries.first else { return }

    // Copy same entry 3 times
    await vm.copyEntryToToday(entry)
    await vm.copyEntryToToday(entry)
    await vm.copyEntryToToday(entry)

    // Today should have 3 copies
    await vm.goToDate(Date())
    await vm.loadTodayMeals()
    #expect(await vm.todayEntries.count == 3, "Should have 3 copies of the entry")
    #expect(await vm.todayNutrition.calories == 450, "3 x 150 = 450")
}

// MARK: - Nutrition Totals Across Date Navigation

@Test func nutritionTotalsUpdateCorrectlyOnDateChange() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Today: 800 cal
    await vm.quickAdd(name: "Breakfast", calories: 300, proteinG: 20, carbsG: 30, fatG: 10, fiberG: 3, mealType: .breakfast)
    await vm.quickAdd(name: "Lunch", calories: 500, proteinG: 35, carbsG: 50, fatG: 20, fiberG: 5, mealType: .lunch)
    #expect(await vm.todayNutrition.calories == 800)

    // Yesterday: 600 cal
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    await vm.goToDate(yesterday)
    await vm.quickAdd(name: "Light Day", calories: 600, proteinG: 40, carbsG: 60, fatG: 25, fiberG: 6, mealType: .lunch)
    #expect(await vm.todayNutrition.calories == 600, "Yesterday should show 600 cal")

    // Navigate back to today — totals should update
    await vm.goToDate(Date())
    #expect(await vm.todayNutrition.calories == 800, "Today should show 800 cal again")
    #expect(await vm.todayNutrition.proteinG == 55, "Protein should be 20 + 35 = 55")
}

// MARK: - Multi-Meal Type on Same Date

@Test func multipleMealTypesOnSameDateAllPersist() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    await vm.quickAdd(name: "Oats", calories: 300, proteinG: 10, carbsG: 50, fatG: 8, fiberG: 5, mealType: .breakfast)
    await vm.quickAdd(name: "Salad", calories: 400, proteinG: 25, carbsG: 30, fatG: 15, fiberG: 8, mealType: .lunch)
    await vm.quickAdd(name: "Apple", calories: 95, proteinG: 0, carbsG: 25, fatG: 0, fiberG: 4, mealType: .snack)
    await vm.quickAdd(name: "Chicken", calories: 500, proteinG: 45, carbsG: 10, fatG: 20, fiberG: 0, mealType: .dinner)

    #expect(await vm.todayEntries.count == 4, "All 4 meal types should have entries")
    #expect(await vm.todayNutrition.calories == 1295)

    // Navigate away and back — all should persist
    await vm.goToPreviousDay()
    await vm.goToNextDay()
    #expect(await vm.todayEntries.count == 4, "All entries should survive navigation")
}

// MARK: - quickAdd Date Parameter Edge Cases

@Test func quickAddWithExplicitDateToFuture() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Log to tomorrow explicitly
    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
    let tomorrowStr = DateFormatters.dateOnly.string(from: tomorrow)
    await vm.quickAdd(name: "Meal Prep", calories: 350, proteinG: 25, carbsG: 35, fatG: 12, fiberG: 3, mealType: .lunch, date: tomorrowStr)

    // Today should be empty
    #expect(await vm.todayEntries.isEmpty, "Today should have no entries")

    // Tomorrow should have the entry
    await vm.goToDate(tomorrow)
    #expect(await vm.todayEntries.count == 1)
    #expect(await vm.todayEntries[0].foodName == "Meal Prep")
    #expect(await vm.todayEntries[0].date == tomorrowStr)
}

@Test func quickAddDateParameterDoesNotAffectSelectedDate() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Selected date is today
    let today = Date()
    let todayStr = DateFormatters.todayString

    // Add to a different date via parameter
    let otherDate = Calendar.current.date(byAdding: .day, value: -7, to: today)!
    let otherStr = DateFormatters.dateOnly.string(from: otherDate)
    await vm.quickAdd(name: "Remote Entry", calories: 100, proteinG: 5, carbsG: 10, fatG: 3, fiberG: 1, mealType: .lunch, date: otherStr)

    // selectedDate should still be today (unchanged)
    let selectedStr = await DateFormatters.dateOnly.string(from: vm.selectedDate)
    #expect(selectedStr == todayStr, "selectedDate should not change when using date parameter")
}

// MARK: - Log Food and Verify Meal Log Integrity

@Test func logFoodCreatesMealLogOnlyOnce() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let vm = await FoodLogViewModel(database: db)

    // Add multiple entries to same meal type
    await vm.quickAdd(name: "Item 1", calories: 100, proteinG: 10, carbsG: 10, fatG: 5, fiberG: 1, mealType: .lunch)
    await vm.quickAdd(name: "Item 2", calories: 200, proteinG: 20, carbsG: 20, fatG: 10, fiberG: 2, mealType: .lunch)
    await vm.quickAdd(name: "Item 3", calories: 300, proteinG: 30, carbsG: 30, fatG: 15, fiberG: 3, mealType: .lunch)

    // There should be only 1 lunch meal log, not 3
    let todayStr = DateFormatters.todayString
    let logs = try db.fetchMealLogs(for: todayStr)
    let lunchLogs = logs.filter { $0.mealType == MealType.lunch.rawValue }
    #expect(lunchLogs.count == 1, "Should have exactly 1 lunch meal log, got \(lunchLogs.count)")

    // But 3 entries under it
    let entries = try db.fetchFoodEntries(forMealLog: lunchLogs[0].id!)
    #expect(entries.count == 3)
}

// MARK: - Copy From Yesterday Integration

@Test func copyFromYesterdayWhenYesterdayIsEmpty() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Yesterday has nothing
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    let yesterdayStr = DateFormatters.dateOnly.string(from: yesterday)
    let logs = try db.fetchMealLogs(for: yesterdayStr)

    // Copy loop should simply do nothing (no crash)
    for log in logs {
        guard let logId = log.id else { continue }
        let entries = try db.fetchFoodEntries(forMealLog: logId)
        for entry in entries {
            await vm.quickAdd(name: entry.foodName, calories: entry.totalCalories,
                              proteinG: entry.totalProtein, carbsG: entry.totalCarbs,
                              fatG: entry.totalFat, fiberG: entry.totalFiber, mealType: .lunch)
        }
    }

    // Today should still be empty
    #expect(await vm.todayEntries.isEmpty, "Nothing should have been copied")
}

// MARK: - isToday Flag

@Test func isTodayFlagAccurateAfterNavigation() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    #expect(await vm.isToday == true, "Should start on today")

    await vm.goToPreviousDay()
    #expect(await vm.isToday == false, "Should not be today after going back")

    await vm.goToNextDay()
    #expect(await vm.isToday == true, "Should be today again after going forward")

    let pastDate = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
    await vm.goToDate(pastDate)
    #expect(await vm.isToday == false, "Should not be today on a distant past date")

    await vm.goToDate(Date())
    #expect(await vm.isToday == true, "Should be today after explicit navigation")
}
