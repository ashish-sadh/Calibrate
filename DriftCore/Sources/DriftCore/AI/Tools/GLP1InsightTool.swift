import Foundation
import DriftCore

@MainActor
public enum GLP1InsightTool {

    nonisolated static let toolName = "glp1_insight"

    // Common GLP-1 drug name substrings for auto-detection
    nonisolated static let glp1Patterns = [
        "ozempic", "wegovy", "semaglutide",
        "mounjaro", "zepbound", "tirzepatide",
        "glp-1", "glp1", "victoza", "liraglutide",
        "rybelsus",
    ]

    static func syncRegistration(registry: ToolRegistry = .shared) {
        registry.register(schema)
    }

    static var schema: ToolSchema {
        ToolSchema(
            id: "health.glp1_insight",
            name: toolName,
            service: "health",
            description: "User asks about GLP-1 adherence, streak, or weight progress — e.g. 'how's my GLP-1 adherence?', 'what's my ozempic streak?', 'how much weight have I lost since starting semaglutide?', 'how's my injection streak?'.",
            parameters: [
                ToolParam("medication", "string", "GLP-1 medication name (e.g. ozempic, semaglutide, mounjaro). Omit to auto-detect from logs.", required: false),
            ],
            handler: { params in
                .text(run(medicationName: params.string("medication")))
            }
        )
    }

    // MARK: - Entry point

    public static func run(medicationName: String?) -> String {
        let allMeds = (try? AppDatabase.shared.fetchAllRecentMedications(days: 730)) ?? []

        let medName: String
        if let raw = medicationName, !raw.isEmpty {
            let lower = raw.lowercased()
            medName = allMeds.first(where: { $0.name.lowercased().contains(lower) })?.name ?? raw.capitalized
        } else {
            guard let detected = autoDetectGLP1(from: allMeds) else {
                return "No GLP-1 medication found in your logs. Try 'took ozempic 0.5mg' to get started."
            }
            medName = detected
        }

        let logs = (try? AppDatabase.shared.fetchMedications(for: medName, days: 730)) ?? []
        guard !logs.isEmpty else {
            return "No \(medName) doses logged yet. Try 'took \(medName.lowercased())' to get started."
        }

        let isoFmt = ISO8601DateFormatter()
        let doseDates = logs.compactMap { isoFmt.date(from: $0.loggedAt) }.sorted()

        guard let firstDate = doseDates.first else {
            return "No valid dose dates found for \(medName)."
        }

        let now = Date()
        let daysSince = daysBetween(firstDate, now)
        let cadenceWeeks = inferCadenceWeeks(dates: doseDates)  // #990: 1 = weekly, 2 = biweekly
        let streak = weeklyStreak(dates: doseDates, now: now, cadenceWeeks: cadenceWeeks)
        let missed = missedWeeksInLast30Days(dates: doseDates, now: now, cadenceWeeks: cadenceWeeks)

        let weights = (try? AppDatabase.shared.fetchWeightEntries()) ?? []
        let deltaKg = weightDelta(weights: weights, since: firstDate)
        let lastDoseDate = doseDates.last ?? firstDate

        return formatInsight(medName: medName, daysSince: daysSince, weekStreak: streak,
                             weeksMissed: missed, weightDeltaKg: deltaKg,
                             lastDoseDate: lastDoseDate, now: now, cadenceWeeks: cadenceWeeks)
    }

    // MARK: - Pure helpers (nonisolated for testability)

    /// True if at least one dose was logged within the last 7 days (strictly after now - 7d).
    /// Used by the notification pipeline to skip scheduling when already dosed this week.
    nonisolated public static func isLoggedThisWeek(dates: [Date], now: Date = Date()) -> Bool {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: now) else { return false }
        return dates.contains { $0 > cutoff }
    }

    nonisolated public static func autoDetectGLP1(from meds: [DailyMedication]) -> String? {
        for pattern in glp1Patterns {
            if let found = meds.first(where: { $0.name.lowercased().contains(pattern) }) {
                return found.name
            }
        }
        return nil
    }

    nonisolated public static func daysBetween(_ from: Date, _ to: Date) -> Int {
        Calendar.current.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// Count consecutive calendar weeks (Mon–Sun) ending before `now` that have ≥1 dose.
    /// The current (incomplete) week is skipped — it can't break the streak.
    nonisolated public static func weeklyStreak(dates: [Date], now: Date = Date(), cadenceWeeks: Int = 1) -> Int {
        var cal = Calendar.current
        cal.firstWeekday = 2  // Monday — locale-independent week boundaries (matches test mondayOfWeek; avoids US Sunday-locale drift)
        let step = max(cadenceWeeks, 1)  // #990: 2 for biweekly meds so an expected off-week isn't a break
        var weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        var streak = 0
        var isCurrentPeriod = true

        for _ in 0..<104 {
            let periodEnd = cal.date(byAdding: .weekOfYear, value: step, to: weekStart) ?? weekStart
            let hasDose = dates.contains { $0 >= weekStart && $0 < periodEnd }

            if hasDose {
                streak += 1
            } else if !isCurrentPeriod {
                break
            }

            isCurrentPeriod = false
            guard let prev = cal.date(byAdding: .weekOfYear, value: -step, to: weekStart) else { break }
            weekStart = prev
        }
        return streak
    }

    /// Count completed calendar weeks in the last 30 days with no dose logged.
    nonisolated public static func missedWeeksInLast30Days(dates: [Date], now: Date = Date(), cadenceWeeks: Int = 1) -> Int {
        var cal = Calendar.current
        cal.firstWeekday = 2  // Monday — locale-independent week boundaries (matches test mondayOfWeek; avoids US Sunday-locale drift)
        let step = max(cadenceWeeks, 1)  // #990: count missed DOSING periods, not calendar weeks, for biweekly meds
        var weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        var missed = 0
        for _ in 0..<(4 / step) {
            guard let prev = cal.date(byAdding: .weekOfYear, value: -step, to: weekStart) else { break }
            weekStart = prev
            let periodEnd = cal.date(byAdding: .weekOfYear, value: step, to: weekStart) ?? weekStart
            let hasDose = dates.contains { $0 >= weekStart && $0 < periodEnd }
            if !hasDose { missed += 1 }
        }
        return missed
    }

    /// #990: infer dosing cadence in weeks from the dose history (median gap), so a biweekly
    /// GLP-1 (≈14-day spacing) isn't scored as a weekly med with constant "missed weeks".
    nonisolated public static func inferCadenceWeeks(dates: [Date]) -> Int {
        guard dates.count >= 3 else { return 1 }  // too few doses to tell — assume weekly
        let sorted = dates.sorted()
        var gaps: [Int] = []
        for i in 1..<sorted.count { gaps.append(daysBetween(sorted[i - 1], sorted[i])) }
        gaps.sort()
        return gaps[gaps.count / 2] >= 10 ? 2 : 1  // ≈14-day median ⇒ biweekly
    }

    /// Weight change (kg) from the closest weight at/after `since` to the most recent weight.
    /// Returns nil when insufficient weight data. Negative = weight lost.
    nonisolated public static func weightDelta(weights: [WeightEntry], since firstDose: Date) -> Double? {
        let fmt = DateFormatters.dateOnly
        let startStr = fmt.string(from: firstDose)
        // weights is DESC ordered — .last(where: date >= start) = earliest weight at/after start
        guard let startKg = weights.last(where: { $0.date >= startStr })?.weightKg,
              let currentKg = weights.first?.weightKg else { return nil }
        return currentKg - startKg
    }

    nonisolated public static func formatInsight(
        medName: String,
        daysSince: Int,
        weekStreak: Int,
        weeksMissed: Int,
        weightDeltaKg: Double?,
        lastDoseDate: Date,
        now: Date = Date(),
        cadenceWeeks: Int = 1
    ) -> String {
        var parts: [String] = []

        let weeksSince = daysSince / 7
        parts.append("\(medName) — started \(daysSince) day\(daysSince == 1 ? "" : "s") ago (\(weeksSince) week\(weeksSince == 1 ? "" : "s")).")

        parts.append("Dose streak: \(weekStreak) consecutive week\(weekStreak == 1 ? "" : "s").")

        if weeksMissed == 0 {
            parts.append("No missed doses in the last 30 days.")
        } else {
            parts.append("\(weeksMissed) missed week\(weeksMissed == 1 ? "" : "s") in the last 30 days.")
        }

        if let delta = weightDeltaKg {
            let lbs = String(format: "%.1f", abs(delta * 2.20462))
            let kg = String(format: "%.1f", abs(delta))
            if delta < -0.5 {
                parts.append("Weight lost since start: \(lbs) lbs (\(kg) kg).")
            } else if delta > 0.5 {
                parts.append("Weight gained since start: \(lbs) lbs (\(kg) kg).")
            } else {
                parts.append("Weight unchanged since start.")
            }
        }

        // Next dose reminder — cadence-aware (weekly or biweekly). #990
        let daysSinceLast = daysBetween(lastDoseDate, now)
        let daysUntilNext = cadenceWeeks * 7 - daysSinceLast
        if daysUntilNext <= 0 {
            parts.append("Next dose: overdue by \(-daysUntilNext) day\(-daysUntilNext == 1 ? "" : "s") — take it today.")
        } else if daysUntilNext == 1 {
            parts.append("Next dose: tomorrow.")
        } else {
            parts.append("Next dose: in \(daysUntilNext) days.")
        }

        return parts.joined(separator: " ")
    }
}
