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

// MARK: - Weight ViewModel Integration Tests

@Test func weightAddAndLoadEntries() async throws {
    let db = try AppDatabase.empty()
    let vm = await WeightViewModel(database: db)

    await vm.addWeight(value: 70.0)
    #expect(await vm.entries.count == 1)
    #expect(await vm.allEntries.count == 1)
}

@Test func weightDeleteDoesNotAffectOtherEntries() async throws {
    let db = try AppDatabase.empty()
    let vm = await WeightViewModel(database: db)

    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    await vm.addWeight(value: 70.0, date: yesterday)
    await vm.addWeight(value: 69.5)
    #expect(await vm.allEntries.count == 2)

    // Delete yesterday's entry
    let yesterdayEntry = await vm.allEntries.first { $0.date == DateFormatters.dateOnly.string(from: yesterday) }
    guard let id = yesterdayEntry?.id else {
        #expect(Bool(false), "Should have yesterday entry")
        return
    }
    await vm.deleteWeight(id: id)

    #expect(await vm.allEntries.count == 1, "Should have 1 entry remaining")
    #expect(await vm.entries[0].weightKg == 69.5, "Today's entry should remain")
}

@Test func weightUpsertSameDateUpdatesValue() async throws {
    let db = try AppDatabase.empty()
    let vm = await WeightViewModel(database: db)

    await vm.addWeight(value: 70.0)
    await vm.addWeight(value: 68.5) // same date (today) — should upsert
    #expect(await vm.allEntries.count == 1, "Should upsert, not create duplicate")
    #expect(await vm.entries[0].weightKg == 68.5, "Should have updated weight")
}

@Test func weightTrendCalculatesAfterMultipleEntries() async throws {
    let db = try AppDatabase.empty()
    let vm = await WeightViewModel(database: db)

    // Add entries over several days
    for i in (0..<7).reversed() {
        let date = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
        await vm.addWeight(value: 70.0 - Double(i) * 0.1, date: date)
    }

    #expect(await vm.allEntries.count == 7)
    #expect(await vm.trend != nil, "Should have calculated trend")
}

@Test func weightTimeRangeFiltering() async throws {
    let db = try AppDatabase.empty()
    let vm = await WeightViewModel(database: db)

    // Add entries: one 60 days ago, one 10 days ago, one today
    let sixtyDaysAgo = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
    let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
    await vm.addWeight(value: 72.0, date: sixtyDaysAgo)
    await vm.addWeight(value: 71.0, date: tenDaysAgo)
    await vm.addWeight(value: 70.0)

    #expect(await vm.allEntries.count == 3, "All entries should exist")

    // 1 week range should only include today
    await MainActor.run { vm.selectedTimeRange = .oneWeek }
    await vm.loadEntries()
    #expect(await vm.entries.count == 1, "1W should show only today's entry")

    // 1 month range should include today + 10 days ago
    await MainActor.run { vm.selectedTimeRange = .oneMonth }
    await vm.loadEntries()
    #expect(await vm.entries.count == 2, "1M should show 2 entries")

    // 3 month range should include all 3
    await MainActor.run { vm.selectedTimeRange = .threeMonths }
    await vm.loadEntries()
    #expect(await vm.entries.count == 3, "3M should show all 3 entries")
}

@Test func weightMilestoneDetectsNewLow() async throws {
    let db = try AppDatabase.empty()
    let vm = await WeightViewModel(database: db)

    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    await vm.addWeight(value: 70.0, date: yesterday)
    #expect(await vm.milestoneMessage == nil, "First entry should not trigger milestone")

    await vm.addWeight(value: 69.0) // new low
    #expect(await vm.milestoneMessage != nil, "New low should trigger milestone")
    #expect(await vm.milestoneMessage?.contains("New Low") == true)
}

@Test func weightGoalAwareColors() async throws {
    let db = try AppDatabase.empty()
    let vm = await WeightViewModel(database: db)

    // Default is isLosing = true
    let deficitColor = await vm.changeColor(for: -0.5) // losing weight = good
    let surplusColor = await vm.changeColor(for: 0.5)  // gaining weight = bad
    let neutralColor = await vm.changeColor(for: 0.0)

    #expect(deficitColor == "deficit", "Weight loss should be deficit (green)")
    #expect(surplusColor == "surplus", "Weight gain should be surplus (red)")
    #expect(neutralColor == "neutral", "No change should be neutral")
}

// MARK: - Supplement ViewModel Integration Tests

@Test func supplementAddAndLoad() async throws {
    let db = try AppDatabase.empty()
    let vm = await SupplementViewModel(database: db)

    await vm.addCustomSupplement(name: "Vitamin D", dosage: "5000", unit: "IU")
    await vm.addCustomSupplement(name: "Omega-3", dosage: "1000", unit: "mg")

    #expect(await vm.supplements.count == 2)
    #expect(await vm.totalCount == 2)
    #expect(await vm.takenCount == 0, "Nothing taken yet")
}

@Test func supplementToggleTakenFlow() async throws {
    let db = try AppDatabase.empty()
    let vm = await SupplementViewModel(database: db)

    await vm.addCustomSupplement(name: "Magnesium", dosage: "400", unit: "mg")
    let supplementId = await vm.supplements[0].id!

    #expect(await vm.isTaken(supplementId) == false)

    await vm.toggleTaken(supplementId: supplementId)
    #expect(await vm.isTaken(supplementId) == true, "Should be taken after toggle")
    #expect(await vm.takenCount == 1)

    // Toggle off
    await vm.toggleTaken(supplementId: supplementId)
    #expect(await vm.isTaken(supplementId) == false, "Should be untaken after second toggle")
    #expect(await vm.takenCount == 0)
}

@Test func supplementToggleDoesNotAffectOtherSupplements() async throws {
    let db = try AppDatabase.empty()
    let vm = await SupplementViewModel(database: db)

    await vm.addCustomSupplement(name: "Vitamin D", dosage: "5000", unit: "IU")
    await vm.addCustomSupplement(name: "Zinc", dosage: "30", unit: "mg")

    let vitDId = await vm.supplements.first { $0.name == "Vitamin D" }!.id!
    let zincId = await vm.supplements.first { $0.name == "Zinc" }!.id!

    await vm.toggleTaken(supplementId: vitDId)
    #expect(await vm.isTaken(vitDId) == true)
    #expect(await vm.isTaken(zincId) == false, "Zinc should not be affected")
    #expect(await vm.takenCount == 1)
}

@Test func supplementCopyYesterdayFlow() async throws {
    let db = try AppDatabase.empty()
    let vm = await SupplementViewModel(database: db)

    await vm.addCustomSupplement(name: "Creatine", dosage: "5", unit: "g")
    await vm.addCustomSupplement(name: "Vitamin C", dosage: "1000", unit: "mg")

    // Mark both as taken for yesterday
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    let yesterdayStr = DateFormatters.dateOnly.string(from: yesterday)
    for supp in await vm.supplements {
        try db.toggleSupplementTaken(supplementId: supp.id!, date: yesterdayStr)
    }

    // Today should have nothing taken
    await vm.loadSupplements()
    #expect(await vm.takenCount == 0, "Today should start with nothing taken")

    // Copy yesterday
    await vm.copyYesterday()
    #expect(await vm.takenCount == 2, "Both supplements should be marked taken after copy")
}

@Test func supplementConsistencyDataLoads() async throws {
    let db = try AppDatabase.empty()
    let vm = await SupplementViewModel(database: db)

    await vm.addCustomSupplement(name: "Fish Oil", dosage: "1000", unit: "mg")
    await vm.loadSupplements()

    // Should have 60 days of consistency data
    #expect(await vm.consistencyData.count == 60, "Should have 60 days of consistency data")
}

// MARK: - Dashboard ViewModel Integration Tests

@Test func dashboardLoadsTodayNutrition() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()

    // Log some food first via FoodLogViewModel
    let foodVM = await FoodLogViewModel(database: db)
    await foodVM.quickAdd(name: "Breakfast", calories: 400, proteinG: 25, carbsG: 40, fatG: 15, fiberG: 3, mealType: .breakfast)
    await foodVM.quickAdd(name: "Lunch", calories: 600, proteinG: 35, carbsG: 60, fatG: 20, fiberG: 5, mealType: .lunch)

    // Now load dashboard
    let dashVM = await DashboardViewModel(database: db)
    await dashVM.loadToday()

    #expect(await dashVM.todayNutrition.calories == 1000, "Dashboard should show 1000 cal")
    #expect(await dashVM.todayNutrition.proteinG == 60, "Dashboard should show 60g protein")
}

@Test func dashboardLoadsSupplementStatus() async throws {
    let db = try AppDatabase.empty()
    let suppVM = await SupplementViewModel(database: db)

    await suppVM.addCustomSupplement(name: "Vitamin D", dosage: "5000", unit: "IU")
    await suppVM.addCustomSupplement(name: "Magnesium", dosage: "400", unit: "mg")

    // Take one supplement
    let vitDId = await suppVM.supplements.first { $0.name == "Vitamin D" }!.id!
    await suppVM.toggleTaken(supplementId: vitDId)

    // Dashboard should reflect this
    let dashVM = await DashboardViewModel(database: db)
    await dashVM.loadToday()

    #expect(await dashVM.supplementsTotal == 2)
    #expect(await dashVM.supplementsTaken == 1)
}

@Test func dashboardCalorieBalanceComputation() async throws {
    let db = try AppDatabase.empty()
    let dashVM = await DashboardViewModel(database: db)

    // Set up known state
    await MainActor.run {
        dashVM.todayNutrition = DailyNutrition(calories: 2000, proteinG: 100, carbsG: 200, fatG: 80, fiberG: 25)
        dashVM.caloriesBurned = 2500
    }

    #expect(await dashVM.calorieBalance == -500, "Should be 500 cal deficit")
    #expect(await dashVM.calorieBalanceText.contains("deficit"), "Should say deficit")
}

@Test func dashboardWithNoDataShowsZeros() async throws {
    let db = try AppDatabase.empty()
    let dashVM = await DashboardViewModel(database: db)
    await dashVM.loadToday()

    #expect(await dashVM.todayNutrition.calories == 0)
    #expect(await dashVM.supplementsTotal == 0)
    #expect(await dashVM.supplementsTaken == 0)
}

// MARK: - Cross-ViewModel Integration

@Test func foodLogAndDashboardStayInSync() async throws {
    let db = try AppDatabase.empty()

    // Log food
    let foodVM = await FoodLogViewModel(database: db)
    await foodVM.quickAdd(name: "Rice", calories: 200, proteinG: 4, carbsG: 45, fatG: 1, fiberG: 1, mealType: .lunch)

    // Dashboard should see it
    let dashVM = await DashboardViewModel(database: db)
    await dashVM.loadToday()
    #expect(await dashVM.todayNutrition.calories == 200)

    // Add more food
    await foodVM.quickAdd(name: "Chicken", calories: 300, proteinG: 40, carbsG: 0, fatG: 8, fiberG: 0, mealType: .lunch)

    // Reload dashboard — should reflect update
    await dashVM.loadToday()
    #expect(await dashVM.todayNutrition.calories == 500, "Dashboard should show updated total")
    #expect(await dashVM.todayNutrition.proteinG == 44)
}

@Test func weightAndDashboardShareTrend() async throws {
    let db = try AppDatabase.empty()
    let weightVM = await WeightViewModel(database: db)

    // Add weight entries
    for i in (0..<5).reversed() {
        let date = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
        await weightVM.addWeight(value: 70.0 - Double(i) * 0.2, date: date)
    }

    #expect(await weightVM.allEntries.count == 5)
    #expect(await weightVM.trend != nil, "Weight VM should have trend")

    // Dashboard loads weight from same DB
    let dashVM = await DashboardViewModel(database: db)
    await dashVM.loadToday()
    // Dashboard loads weight trend internally — just verify it didn't crash
    // (HealthKit part is skipped on simulator)
}
