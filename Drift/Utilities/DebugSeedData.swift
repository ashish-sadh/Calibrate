import Foundation

#if DEBUG
/// Seed data for testing the stale-startWeightKg bug on simulator.
/// Call from DriftApp.swift: `DebugSeedData.seedWeightGoalBug()`
enum DebugSeedData {

    /// Reproduces the "gain 14.1 kg" bug:
    /// - Goal: target=90 kg, startWeight=75.9 kg (STALE — the bug)
    /// - Actual weight entries: ~101-102 kg over last 30 days
    /// - Dashboard should show "lose ~11 kg" (fixed) not "gain 14.1 kg" (old bug)
    @MainActor
    static func seedWeightGoalBug() {
        let db = AppDatabase.shared

        // Clear existing weight data
        try? db.writer.write { dbConn in
            try dbConn.execute(sql: "DELETE FROM weight_entry")
        }
        WeightGoal.clear()

        // 1. Seed weight entries: 101-102 kg over last 30 days (realistic losing trend)
        let cal = Calendar.current
        let today = Date()
        let weights: [(daysAgo: Int, kg: Double)] = [
            (30, 102.5), (28, 102.3), (25, 102.4), (23, 102.1),
            (21, 102.0), (18, 101.9), (16, 102.1), (14, 101.8),
            (12, 101.7), (10, 101.9), (7, 101.6), (5, 101.8),
            (3, 101.5), (1, 101.8), (0, 101.8),
        ]

        for w in weights {
            guard let date = cal.date(byAdding: .day, value: -w.daysAgo, to: today) else { continue }
            let dateStr = DateFormatters.dateOnly.string(from: date)
            var entry = WeightEntry(date: dateStr, weightKg: w.kg, source: "manual")
            try? db.saveWeightEntry(&entry)
        }

        // 2. Create the buggy goal: startWeight=75.9 (WRONG — simulates stale HealthKit data)
        let goal = WeightGoal(
            targetWeightKg: 90.0,
            monthsToAchieve: 3,
            startDate: "2026-01-15",  // started ~3 months ago
            startWeightKg: 75.9       // THE BUG: this was wrong when goal was created
        )
        goal.save()

        // 3. Refresh trend service so dashboard picks up the new data
        WeightTrendService.shared.refresh()

        Log.app.info("🧪 DEBUG: Seeded weight goal bug scenario — 15 entries + stale goal (start=75.9, target=90)")
    }

    /// Clean scenario: correct start weight, normal losing goal.
    @MainActor
    static func seedNormalGoal() {
        let db = AppDatabase.shared

        try? db.writer.write { dbConn in
            try dbConn.execute(sql: "DELETE FROM weight_entry")
        }
        WeightGoal.clear()

        let cal = Calendar.current
        let today = Date()
        // User started at 105, now at ~100, goal 90
        let weights: [(daysAgo: Int, kg: Double)] = [
            (60, 105.0), (55, 104.7), (50, 104.3), (45, 103.8),
            (40, 103.5), (35, 103.0), (30, 102.5), (25, 102.0),
            (20, 101.5), (15, 101.0), (10, 100.8), (7, 100.5),
            (5, 100.3), (3, 100.2), (0, 100.0),
        ]

        for w in weights {
            guard let date = cal.date(byAdding: .day, value: -w.daysAgo, to: today) else { continue }
            let dateStr = DateFormatters.dateOnly.string(from: date)
            var entry = WeightEntry(date: dateStr, weightKg: w.kg, source: "manual")
            try? db.saveWeightEntry(&entry)
        }

        let goal = WeightGoal(
            targetWeightKg: 90.0,
            monthsToAchieve: 6,
            startDate: DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -60, to: today)!),
            startWeightKg: 105.0  // CORRECT start weight
        )
        goal.save()

        WeightTrendService.shared.refresh()
        Log.app.info("🧪 DEBUG: Seeded normal goal scenario — 15 entries + correct goal (start=105, target=90)")
    }

    /// Gaining goal scenario: underweight user trying to gain.
    @MainActor
    static func seedGainingGoal() {
        let db = AppDatabase.shared

        try? db.writer.write { dbConn in
            try dbConn.execute(sql: "DELETE FROM weight_entry")
        }
        WeightGoal.clear()

        let cal = Calendar.current
        let today = Date()
        let weights: [(daysAgo: Int, kg: Double)] = [
            (30, 58.0), (25, 58.5), (20, 59.0), (15, 59.5),
            (10, 60.0), (7, 60.2), (5, 60.5), (3, 60.8), (0, 61.0),
        ]

        for w in weights {
            guard let date = cal.date(byAdding: .day, value: -w.daysAgo, to: today) else { continue }
            let dateStr = DateFormatters.dateOnly.string(from: date)
            var entry = WeightEntry(date: dateStr, weightKg: w.kg, source: "manual")
            try? db.saveWeightEntry(&entry)
        }

        let goal = WeightGoal(
            targetWeightKg: 70.0,
            monthsToAchieve: 6,
            startDate: DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -30, to: today)!),
            startWeightKg: 58.0
        )
        goal.save()

        WeightTrendService.shared.refresh()
        Log.app.info("🧪 DEBUG: Seeded gaining goal — 9 entries (58→61), target=70")
    }
}
#endif
