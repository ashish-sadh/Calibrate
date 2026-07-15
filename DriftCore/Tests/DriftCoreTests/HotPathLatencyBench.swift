import XCTest
@testable import DriftCore

/// Tier-4 hot-path latency bench — catches the "whole-table scan / N× loop
/// inside a user interaction" family (2026-07-15 Log-button hang, the
/// #1008 query storms) BEFORE a field report does. Runs the exact DB paths
/// behind the Log press, the Add Food sheet, and the dashboard insight load
/// against a YEAR-scale dataset, and asserts generous order-of-magnitude
/// ceilings: a pass means "still index-shaped", a fail means someone
/// reintroduced a scan. These are not micro-benchmarks — thresholds are
/// ~10× the expected cost so machine variance never flakes them.
///
/// Opt-in only (Tier 4): set DRIFT_LATENCY_BENCH=1. Does not run in CI.
///
/// Run:
///   cd DriftCore && DRIFT_LATENCY_BENCH=1 swift test --filter HotPathLatencyBench
///
/// Cadence: after any change to AppDatabase queries or logging/dashboard
/// hot paths, and as part of the once-in-a-while perf pass documented in
/// Docs/development-sop.md ("Performance monitoring").
final class HotPathLatencyBench: XCTestCase {

    private var db: AppDatabase!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DRIFT_LATENCY_BENCH"] == "1",
                          "Tier-4 bench — set DRIFT_LATENCY_BENCH=1 to run")
        db = try AppDatabase.empty()
        try seedYearScale(db)
    }

    // MARK: - Year-scale dataset

    /// ~6,000-food catalog + 365 days × 12 food entries/day (~4,380 rows,
    /// a heavy but realistic year of use), inserted in one transaction.
    private func seedYearScale(_ db: AppDatabase) throws {
        let cal = Calendar.current
        try db.writer.write { conn in
            for i in 0..<6_000 {
                try conn.execute(sql: """
                    INSERT INTO food (name, category, serving_size, serving_unit, calories,
                                      protein_g, carbs_g, fat_g, fiber_g, normalized_key)
                    VALUES (?, 'Bench', 100, 'g', 250, 10, 30, 8, 3, ?)
                    """, arguments: ["Bench Food \(i)", Food.normalizedKey("Bench Food \(i)")])
            }
            for dayOffset in 0..<365 {
                guard let date = cal.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
                let dateStr = DateFormatters.dateOnly.string(from: date)
                try conn.execute(sql: "INSERT INTO meal_log (date, meal_type) VALUES (?, 'lunch')",
                                 arguments: [dateStr])
                let mealLogId = conn.lastInsertedRowID
                for slot in 0..<12 {
                    let foodId = Int64((dayOffset * 12 + slot) % 6_000 + 1)
                    try conn.execute(sql: """
                        INSERT INTO food_entry (meal_log_id, food_id, food_name, serving_size_g,
                                                servings, calories, protein_g, carbs_g, fat_g,
                                                fiber_g, logged_at, date, meal_type)
                        VALUES (?, ?, ?, 100, 1, 250, 10, 30, 8, 3, ?, ?, 'lunch')
                        """, arguments: [mealLogId, foodId, "Bench Food \(foodId)",
                                         "\(dateStr)T12:\(String(format: "%02d", slot)):00Z", dateStr])
                }
            }
        }
    }

    /// Wall-clock ceiling assert with a printed measurement for the log.
    private func assertUnder(_ ceilingMs: Double, _ label: String, _ work: () throws -> Void) rethrows {
        let start = DispatchTime.now()
        try work()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        print("⏱ [HotPathLatencyBench] \(label): \(String(format: "%.1f", ms))ms (ceiling \(Int(ceilingMs))ms)")
        XCTAssertLessThan(ms, ceilingMs,
                          "\(label) blew its ceiling — a whole-table scan or N× loop is back on this path")
    }

    // MARK: - Benches

    /// The Log press persists each new food via saveScannedFood. The
    /// 2026-07-15 hang: the dedupe fetched + normalized all ~6k names per
    /// item. Indexed normalized_key lookup should make 10 items trivial.
    func testLogPress_saveScannedFoods() throws {
        try assertUnder(500, "saveScannedFood ×10 vs 6k catalog") {
            for i in 0..<10 {
                var food = Food(name: "Fresh Photo Item \(i)", category: "Photo Log",
                                servingSize: 120, servingUnit: "g", calories: 300)
                try db.saveScannedFood(&food)
            }
        }
    }

    /// Add Food sheet onAppear: recently-logged suggestions. Was an
    /// unbounded GROUP BY over all of food_entry; now 90-day-bounded on
    /// idx_food_entry_date.
    func testAddFoodSheet_recentlyLoggedFoods() throws {
        try assertUnder(200, "fetchMostRecentlyLoggedFoods vs 4.4k entries") {
            let foods = try db.fetchMostRecentlyLoggedFoods(limit: 8)
            XCTAssertFalse(foods.isEmpty, "seeded data must produce suggestions — empty means the query is broken, not fast")
        }
    }

    /// Dashboard insight load: was ~100 serial per-day fetchDailyNutrition
    /// queries; now one ranged GROUP BY. Bench the batch AND print the
    /// per-day equivalent so the ratio stays visible in the log.
    func testDashboard_dailyNutritionRange() throws {
        let cal = Calendar.current
        let start = DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -30, to: Date())!)
        try assertUnder(200, "fetchDailyNutritionRange 30d vs year of entries") {
            let map = try db.fetchDailyNutritionRange(from: start, to: DateFormatters.todayString)
            XCTAssertGreaterThan(map.count, 25, "seeded data must cover the window")
        }
        // Reference: the per-day pattern this replaced (not asserted — printed
        // so a future reader sees why the batch API exists).
        let t0 = DispatchTime.now()
        for offset in 0..<30 {
            let d = DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -offset, to: Date())!)
            _ = try db.fetchDailyNutrition(for: d)
        }
        let perDayMs = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
        print("⏱ [HotPathLatencyBench] reference per-day ×30 loop: \(String(format: "%.1f", perDayMs))ms")
    }

    /// Online-search dedupe set: was fetch-all-names + Swift normalization
    /// per search; now reads the persisted keys.
    func testOnlineSearch_dedupeKeys() throws {
        try assertUnder(200, "fetchAllFoodKeys vs 6k catalog") {
            let keys = try db.fetchAllFoodKeys()
            XCTAssertGreaterThan(keys.count, 5_000)
        }
    }
}
