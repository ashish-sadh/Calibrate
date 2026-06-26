import Foundation
import DriftCore

/// Seeds a realistic sample DB so the simulator's pipeline has real context to
/// reason over: a "lose weight" goal, a losing weight trend, and a day of
/// Indian-first meals. Mirrors what a real user's day looks like — the bar is
/// Indian food (CLAUDE.md tenet), so the seed is dal / roti / paneer, not eggs.
///
/// IMPORTANT: the AI tools + context builders are hardcoded to `AppDatabase.shared`
/// (no injection seam), so the sim MUST seed `.shared`. On macOS that is a
/// host-local file (~/Library/Application Support/Drift/drift.sqlite), separate
/// from the iOS app — `factoryReset()` gives a clean slate + reseeds all foods.
@MainActor
enum Seed {

    static func sampleDB() throws {
        let db = AppDatabase.shared

        // 1. Clean slate + reseed the full Indian-first food catalog from bundled JSON.
        try db.factoryReset()

        // 2. Goal: lose weight (start 80 → target 72 over 4 months). Stored in
        //    UserDefaults via WeightGoal, drives goal-aware color + macro targets.
        WeightGoal(
            targetWeightKg: 72,
            monthsToAchieve: 4,
            startDate: "2026-05-01",
            startWeightKg: 80
        ).save()

        // 3. A losing trend (newest 78.8 < start 80 → on track, green).
        for (date, kg) in [("2026-06-15", 79.4), ("2026-06-17", 79.1), ("2026-06-19", 78.8)] {
            var w = WeightEntry(date: date, weightKg: kg, source: "manual")
            try db.saveWeightEntry(&w)
        }

        // 4. Today's meals — a believable Indian day across breakfast / lunch / dinner.
        let today = DateFormatters.todayString
        try seedMeal(db, date: today, meal: "breakfast", name: "Poha",
                     cal: 270, p: 5, c: 50, f: 6, fiber: 3, servings: 1, at: "08:15:00")
        try seedMeal(db, date: today, meal: "lunch", name: "Roti / Chapati",
                     cal: 120, p: 3, c: 22, f: 2, fiber: 2, servings: 2, at: "13:00:00")
        try seedMeal(db, date: today, meal: "lunch", name: "Moong Dal (cooked)",
                     cal: 180, p: 12, c: 25, f: 3, fiber: 5, servings: 1, at: "13:01:00")
        try seedMeal(db, date: today, meal: "lunch", name: "White Rice (cooked)",
                     cal: 205, p: 4, c: 45, f: 0, fiber: 1, servings: 1, at: "13:02:00")
        try seedMeal(db, date: today, meal: "dinner", name: "Paneer Butter Masala",
                     cal: 350, p: 14, c: 12, f: 28, fiber: 2, servings: 1, at: "20:00:00")

        // 5. A small Indian-first supplement stack so the mark_supplement path is
        //    exercisable e2e ("I took my vitamin D" hits a real stack entry). The
        //    empty-stack auto-add path is covered separately by Tier-0 tests. (#904)
        for (i, name) in ["Vitamin D", "Omega 3", "Creatine", "Ashwagandha"].enumerated() {
            var supp = Supplement(name: name, isActive: true, sortOrder: i, dailyDoses: 1)
            try db.saveSupplement(&supp)
        }
    }

    private static func seedMeal(
        _ db: AppDatabase, date: String, meal: String, name: String,
        cal: Double, p: Double, c: Double, f: Double, fiber: Double,
        servings: Double, at time: String
    ) throws {
        var log = MealLog(date: date, mealType: meal)
        try db.saveMealLog(&log)
        var entry = FoodEntry(
            mealLogId: log.id ?? 0,
            foodName: name,
            servingSizeG: 100,
            servings: servings,
            calories: cal,
            proteinG: p, carbsG: c, fatG: f, fiberG: fiber,
            loggedAt: "\(date)T\(time)Z",
            date: date,
            mealType: meal
        )
        try db.saveFoodEntry(&entry)
    }
}
