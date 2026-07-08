import Testing
import Foundation
@testable import DriftCore

// Tier 0 — pure logic only, no LLM, no DB. Tests ToolRanker routing and pure helpers.

@MainActor
struct GLP1InsightToolTests {

    init() { ToolRegistration.registerAll() }

    // MARK: - ToolRanker routing (gold set)

    @Test func glp1Adherence_routesToGLP1Insight() {
        let top = ToolRanker.rank(query:"how's my glp-1 adherence?", screen: .food).first?.id
        #expect(top == "health.glp1_insight")
    }

    @Test func ozempicProgress_routesToGLP1Insight() {
        let top = ToolRanker.rank(query:"ozempic progress this month", screen: .food).first?.id
        #expect(top == "health.glp1_insight")
    }

    @Test func injectionStreak_routesToGLP1Insight() {
        let top = ToolRanker.rank(query:"what's my injection streak?", screen: .food).first?.id
        #expect(top == "health.glp1_insight")
    }

    @Test func semaglutideStreak_routesToGLP1Insight() {
        let top = ToolRanker.rank(query:"semaglutide streak", screen: .food).first?.id
        #expect(top == "health.glp1_insight")
    }

    @Test func weightSinceOzempic_routesToGLP1Insight() {
        let top = ToolRanker.rank(query:"how much weight have I lost weight since ozempic?", screen: .food).first?.id
        #expect(top == "health.glp1_insight")
    }

    // MARK: - Routing exclusions (should NOT route to glp1_insight)

    @Test func tookOzempic_doesNotRouteToGLP1Insight() {
        let top = ToolRanker.rank(query:"took ozempic 0.5mg", screen: .food).first?.id
        #expect(top != "health.glp1_insight")
    }

    @Test func lastDoseOzempic_doesNotRouteToGLP1Insight() {
        let top = ToolRanker.rank(query:"when did I last take ozempic?", screen: .food).first?.id
        #expect(top != "health.glp1_insight")
    }

    // MARK: - isLoggedThisWeek

    @Test func isLoggedThisWeek_doseYesterday_isTrue() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        #expect(GLP1InsightTool.isLoggedThisWeek(dates: [yesterday]) == true)
    }

    @Test func isLoggedThisWeek_dose8DaysAgo_isFalse() {
        let eightDaysAgo = Calendar.current.date(byAdding: .day, value: -8, to: Date())!
        #expect(GLP1InsightTool.isLoggedThisWeek(dates: [eightDaysAgo]) == false)
    }

    @Test func isLoggedThisWeek_noDoses_isFalse() {
        #expect(GLP1InsightTool.isLoggedThisWeek(dates: []) == false)
    }

    @Test func isLoggedThisWeek_doseExactlySevenDaysAgo_isFalse() {
        // Boundary: exactly 7 days ago is NOT within the last 7 days (cutoff is strictly >)
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        #expect(GLP1InsightTool.isLoggedThisWeek(dates: [sevenDaysAgo]) == false)
    }

    @Test func isLoggedThisWeek_multipleDosesOldAndRecent_isTrue() {
        let old = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        let recent = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        #expect(GLP1InsightTool.isLoggedThisWeek(dates: [old, recent]) == true)
    }

    // MARK: - autoDetectGLP1

    @Test func autoDetect_findsOzempic() {
        let meds = [makeMed("Ozempic"), makeMed("Vitamin D")]
        let found = GLP1InsightTool.autoDetectGLP1(from: meds)
        #expect(found == "Ozempic")
    }

    @Test func autoDetect_findsSemaglutide() {
        let meds = [makeMed("Semaglutide 0.5Mg"), makeMed("Creatine")]
        let found = GLP1InsightTool.autoDetectGLP1(from: meds)
        #expect(found == "Semaglutide 0.5Mg")
    }

    @Test func autoDetect_returnsNilWhenNoGLP1() {
        let meds = [makeMed("Metformin"), makeMed("Vitamin D")]
        let found = GLP1InsightTool.autoDetectGLP1(from: meds)
        #expect(found == nil)
    }

    // MARK: - weeklyStreak

    @Test func weeklyStreak_consecutiveWeeks() {
        let cal = Calendar.current
        let now = Date()
        // Doses in last 3 consecutive weeks (Mon of each week)
        let w1 = cal.date(byAdding: .weekOfYear, value: -2, to: mondayOfWeek(now))!
        let w2 = cal.date(byAdding: .weekOfYear, value: -1, to: mondayOfWeek(now))!
        let w3 = mondayOfWeek(now)
        let streak = GLP1InsightTool.weeklyStreak(dates: [w1, w2, w3], now: now)
        #expect(streak >= 2) // at least 2 completed past weeks
    }

    @Test func weeklyStreak_brokenByMissedWeek() {
        let cal = Calendar.current
        let now = Date()
        // Doses 3 weeks ago and 1 week ago — week 2 ago is missing
        let w3 = cal.date(byAdding: .weekOfYear, value: -3, to: mondayOfWeek(now))!
        let w1 = cal.date(byAdding: .weekOfYear, value: -1, to: mondayOfWeek(now))!
        let streak = GLP1InsightTool.weeklyStreak(dates: [w3, w1], now: now)
        #expect(streak == 1) // only last week counts; week 2 ago breaks it
    }

    @Test func weeklyStreak_noDoses_isZero() {
        #expect(GLP1InsightTool.weeklyStreak(dates: [], now: Date()) == 0)
    }

    // MARK: - missedWeeksInLast30Days

    @Test func missedWeeks_allPresent_isZero() {
        let cal = Calendar.current
        let now = Date()
        let mon = mondayOfWeek(now)
        let doses = (1...4).compactMap { cal.date(byAdding: .weekOfYear, value: -$0, to: mon) }
        #expect(GLP1InsightTool.missedWeeksInLast30Days(dates: doses, now: now) == 0)
    }

    @Test func missedWeeks_noDoses_is4() {
        #expect(GLP1InsightTool.missedWeeksInLast30Days(dates: [], now: Date()) == 4)
    }

    // MARK: - #990: biweekly cadence

    @Test func inferCadenceWeeks_biweeklyVsWeekly() {
        let cal = Calendar.current
        let now = Date()
        let biweekly = [0, 14, 28, 42].map { cal.date(byAdding: .day, value: -$0, to: now)! }
        let weekly = [0, 7, 14, 21].map { cal.date(byAdding: .day, value: -$0, to: now)! }
        #expect(GLP1InsightTool.inferCadenceWeeks(dates: biweekly) == 2)
        #expect(GLP1InsightTool.inferCadenceWeeks(dates: weekly) == 1)
    }

    @Test func weeklyStreak_biweekly_notBrokenByOffWeek() {
        let cal = Calendar.current
        let now = Date()
        // Perfectly-adherent biweekly: doses 5, 3, 1 weeks ago — the intervening weeks are expected off-weeks.
        let doses = [-5, -3, -1].map { cal.date(byAdding: .weekOfYear, value: $0, to: mondayOfWeek(now))! }
        #expect(GLP1InsightTool.weeklyStreak(dates: doses, now: now, cadenceWeeks: 2) >= 2)
    }

    @Test func missedWeeks_biweekly_adherentIsZero() {
        let cal = Calendar.current
        let now = Date()
        let doses = [-1, -3].map { cal.date(byAdding: .weekOfYear, value: $0, to: mondayOfWeek(now))! }
        #expect(GLP1InsightTool.missedWeeksInLast30Days(dates: doses, now: now, cadenceWeeks: 2) == 0)
    }

    // MARK: - weightDelta

    @Test func weightDelta_lossTwelveKg() {
        let start = makeEntry(date: "2026-01-01", kg: 90.0)
        let current = makeEntry(date: "2026-05-01", kg: 78.0)
        let startDate = DateFormatters.dateOnly.date(from: "2026-01-01")!
        // DESC order (most recent first)
        let delta = GLP1InsightTool.weightDelta(weights: [current, start], since: startDate)
        #expect(delta == -12.0)
    }

    @Test func weightDelta_nilWhenNoWeights() {
        let delta = GLP1InsightTool.weightDelta(weights: [], since: Date())
        #expect(delta == nil)
    }

    // MARK: - formatInsight

    @Test func formatInsight_zeroDataNextDose() {
        let now = Date()
        let lastDose = Calendar.current.date(byAdding: .day, value: -3, to: now)!
        let output = GLP1InsightTool.formatInsight(
            medName: "Ozempic", daysSince: 30, weekStreak: 4, weeksMissed: 0,
            weightDeltaKg: -5.0, lastDoseDate: lastDose, now: now
        )
        #expect(output.contains("Ozempic"))
        #expect(output.contains("streak: 4"))
        #expect(output.contains("Next dose: in 4 days"))
        #expect(output.contains("lbs"))
    }

    @Test func formatInsight_overdueNextDose() {
        let now = Date()
        let lastDose = Calendar.current.date(byAdding: .day, value: -9, to: now)!
        let output = GLP1InsightTool.formatInsight(
            medName: "Wegovy", daysSince: 60, weekStreak: 8, weeksMissed: 1,
            weightDeltaKg: nil, lastDoseDate: lastDose, now: now
        )
        #expect(output.contains("overdue"))
    }

    @Test func formatInsight_noWeightData_omitsWeightLine() {
        let now = Date()
        let output = GLP1InsightTool.formatInsight(
            medName: "Mounjaro", daysSince: 14, weekStreak: 2, weeksMissed: 0,
            weightDeltaKg: nil, lastDoseDate: now, now: now
        )
        #expect(!output.contains("lbs"))
        #expect(!output.contains("kg)"))
    }

    // MARK: - Zero-data state (run output)

    @Test func run_unknownMed_returnsGracefulMessage() {
        // Medication name not in DB — run() returns helpful message instead of crashing
        let result = GLP1InsightTool.run(medicationName: "nonexistent_glp_xyz_test")
        #expect(result.lowercased().contains("no ") || result.lowercased().contains("not found"))
    }

    // MARK: - Helpers

    private func makeMed(_ name: String) -> DailyMedication {
        DailyMedication(name: name, doseMg: nil, doseUnit: nil, loggedAt: ISO8601DateFormatter().string(from: Date()))
    }

    private func makeEntry(date: String, kg: Double) -> WeightEntry {
        WeightEntry(date: date, weightKg: kg)
    }

    private func mondayOfWeek(_ date: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
    }
}
