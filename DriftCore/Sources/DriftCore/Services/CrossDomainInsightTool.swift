import Foundation
import DriftCore

/// Cross-domain correlation tool. Answers questions that span 2+ health
/// domains — "did I lose weight on workout days?", "glucose vs carbs?",
/// "protein on lifting days vs rest?". Read-only, on-device, no cloud.
///
/// Design:
/// - Align paired daily observations across both metrics (inner join by date).
/// - Compute Pearson's r over the paired series. Require ≥ 5 pairs.
/// - Return a one-line human summary: means, n, r, trend direction.
/// - `sleep_hours` and `steps` are exposed in the metric list but currently
///   answer with a graceful "not yet supported" line — HealthKit historical
///   fetches are async and out of scope for v1. #317.
@MainActor
public enum CrossDomainInsightTool {

    nonisolated static let toolName = "cross_domain_insight"

    /// Metrics backed by on-device data. Kept `nonisolated` so tests + the
    /// IntentClassifier fixture list can reuse the exact same strings.
    nonisolated static let supportedMetrics: [String] = [
        "weight", "calories", "protein", "carbs", "fat", "fiber",
        "workout_volume", "glucose_avg"
    ]

    nonisolated static let pendingMetrics: [String] = ["sleep_hours", "steps"]

    nonisolated static let allowedWindows: [Int] = [7, 14, 30, 90]

    // MARK: - Registration

    static func syncRegistration(registry: ToolRegistry = .shared) {
        registry.register(schema)
    }

    static var schema: ToolSchema {
        ToolSchema(
            id: "insights.cross_domain_insight",
            name: toolName,
            service: "insights",
            description: "User asks about correlations between two metrics — e.g. weight vs workouts, glucose vs carbs, protein on lifting days.",
            parameters: [
                ToolParam("metric_a", "string", "First metric: weight, calories, protein, carbs, fat, fiber, workout_volume, glucose_avg"),
                ToolParam("metric_b", "string", "Second metric — same options as metric_a"),
                ToolParam("window_days", "number", "Window: 7, 14, 30, or 90 days (default 30)", required: false)
            ],
            handler: { params in
                let a = normalizeMetric(params.string("metric_a") ?? "")
                let b = normalizeMetric(params.string("metric_b") ?? "")
                let window = clampWindow(params.int("window_days"))
                return .text(run(metricA: a, metricB: b, windowDays: window))
            }
        )
    }

    // MARK: - Entry point (pure except for DB reads)

    /// Main analyzer. Returns a formatted user-facing line. Testable by
    /// seeding the DB — the pure correlation math is exposed below for
    /// direct unit tests.
    public static func run(metricA: String, metricB: String, windowDays: Int) -> String {
        guard !metricA.isEmpty, !metricB.isEmpty else {
            return "Tell me which two metrics to compare — e.g. 'weight vs workout_volume' or 'glucose vs carbs'."
        }
        if metricA == metricB {
            return "Pick two different metrics — a metric always correlates perfectly with itself."
        }
        if pendingMetrics.contains(metricA) || pendingMetrics.contains(metricB) {
            return "Sleep and steps correlations aren't wired up yet — try: weight, calories, protein, carbs, fat, fiber, workout_volume, or glucose_avg."
        }
        guard supportedMetrics.contains(metricA), supportedMetrics.contains(metricB) else {
            return "Unknown metric. Supported: \(supportedMetrics.joined(separator: ", "))."
        }
        let series = fetchPairedSeries(metricA: metricA, metricB: metricB, windowDays: windowDays)
        guard series.count >= 5 else {
            return "Need at least 5 days with both \(prettyName(metricA)) and \(prettyName(metricB)) logged — you have \(series.count). Keep logging and ask again."
        }
        let xs = series.map(\.a)
        let ys = series.map(\.b)
        guard let r = pearsonR(xs: xs, ys: ys) else {
            return "One of the metrics is flat over the \(windowDays)-day window — no variation to correlate."
        }
        return formatSummary(
            metricA: metricA, metricB: metricB,
            xs: xs, ys: ys, r: r, windowDays: windowDays
        )
    }

    // MARK: - Normalization

    /// Map user phrasing to a canonical metric key. Case-insensitive.
    /// Aliases: "cal"/"kcal" → calories, "sugar"/"glucose" → glucose_avg,
    /// "workouts"/"lifting" → workout_volume, "weight_kg"/"bodyweight" → weight.
    nonisolated static func normalizeMetric(_ raw: String) -> String {
        let key = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        switch key {
        case "":                                          return ""
        case "weight", "weight_kg", "weight_lbs", "bodyweight", "body_weight":
            return "weight"
        case "calories", "cal", "cals", "kcal", "kcals", "energy":
            return "calories"
        case "protein", "protein_g":                       return "protein"
        case "carbs", "carb", "carbohydrates", "carbs_g":  return "carbs"
        case "fat", "fats", "fat_g":                       return "fat"
        case "fiber", "fibre", "fiber_g":                  return "fiber"
        case "workout_volume", "workouts", "workout", "lifting", "training_volume", "volume":
            return "workout_volume"
        case "glucose_avg", "glucose", "blood_sugar", "sugar", "bg":
            return "glucose_avg"
        case "sleep", "sleep_hours", "sleep_h":            return "sleep_hours"
        case "steps", "step_count":                        return "steps"
        default:
            // Accept already-canonical strings.
            if supportedMetrics.contains(key) || pendingMetrics.contains(key) { return key }
            return key
        }
    }

    nonisolated static func clampWindow(_ raw: Int?) -> Int {
        guard let raw else { return 30 }
        if raw <= 10 { return 7 }
        if raw <= 21 { return 14 }
        if raw <= 60 { return 30 }
        return 90
    }

    // MARK: - Pure correlation math

    /// Pearson's r over paired samples. Returns nil when either series has
    /// zero variance (can't define a correlation) or fewer than 2 points.
    nonisolated static func pearsonR(xs: [Double], ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 2 else { return nil }
        let n = Double(xs.count)
        let mx = xs.reduce(0, +) / n
        let my = ys.reduce(0, +) / n
        var num = 0.0, dx2 = 0.0, dy2 = 0.0
        for i in 0..<xs.count {
            let dx = xs[i] - mx
            let dy = ys[i] - my
            num += dx * dy
            dx2 += dx * dx
            dy2 += dy * dy
        }
        let denom = (dx2 * dy2).squareRoot()
        guard denom > 0 else { return nil }
        return (num / denom).clamped(to: -1.0...1.0)
    }

    /// Strength bucket name for |r|. Thresholds match the acceptance
    /// criteria: strong ≥ 0.6, moderate ≥ 0.3, else weak.
    nonisolated static func strengthLabel(_ r: Double) -> String {
        let ar = abs(r)
        if ar >= 0.6 { return "strong" }
        if ar >= 0.3 { return "moderate" }
        return "weak"
    }

    nonisolated static func directionLabel(_ r: Double) -> String {
        if r > 0.05 { return "positive" }
        if r < -0.05 { return "negative" }
        return "flat"
    }

    nonisolated static func prettyName(_ key: String) -> String {
        switch key {
        case "weight":         return "weight"
        case "calories":       return "calories"
        case "protein":        return "protein"
        case "carbs":          return "carbs"
        case "fat":            return "fat"
        case "fiber":          return "fiber"
        case "workout_volume": return "workout volume"
        case "glucose_avg":    return "avg glucose"
        case "sleep_hours":    return "sleep"
        case "steps":          return "steps"
        default:               return key
        }
    }

    nonisolated static func unitLabel(_ key: String) -> String {
        switch key {
        case "weight":         return "kg"
        case "calories":       return "kcal"
        case "protein", "carbs", "fat", "fiber": return "g"
        case "workout_volume": return "lbs·reps"
        case "glucose_avg":    return "mg/dL"
        case "sleep_hours":    return "h"
        case "steps":          return "steps"
        default:               return ""
        }
    }

    nonisolated static func formatSummary(
        metricA: String, metricB: String,
        xs: [Double], ys: [Double], r: Double, windowDays: Int
    ) -> String {
        let n = xs.count
        let mx = xs.reduce(0, +) / Double(n)
        let my = ys.reduce(0, +) / Double(n)
        let strength = strengthLabel(r)
        let direction = directionLabel(r)
        let rStr = String(format: "%+.2f", r)
        let ua = unitLabel(metricA)
        let ub = unitLabel(metricB)
        let avgA = formatMean(mx, unit: ua)
        let avgB = formatMean(my, unit: ub)
        return "Over the last \(windowDays) days (\(n) paired days): \(prettyName(metricA)) avg \(avgA), \(prettyName(metricB)) avg \(avgB). Correlation r=\(rStr) (\(strength) \(direction))."
    }

    nonisolated static func formatMean(_ v: Double, unit: String) -> String {
        let rounded = v >= 100 ? String(Int(v.rounded())) : String(format: "%.1f", v)
        return unit.isEmpty ? rounded : "\(rounded) \(unit)"
    }

    // MARK: - Data fetch (per-metric)

    /// Paired daily observations across both metrics. Inner-joins on date
    /// so correlation only sees days with *both* signals present.
    static func fetchPairedSeries(metricA: String, metricB: String, windowDays: Int) -> [(date: String, a: Double, b: Double)] {
        let (startStr, endStr) = dateWindow(windowDays: windowDays)
        let seriesA = fetchDailySeries(metric: metricA, startDate: startStr, endDate: endStr)
        let seriesB = fetchDailySeries(metric: metricB, startDate: startStr, endDate: endStr)
        let sharedDates = Set(seriesA.keys).intersection(seriesB.keys)
        return sharedDates.sorted().compactMap { date in
            guard let a = seriesA[date], let b = seriesB[date] else { return nil }
            return (date, a, b)
        }
    }

    static func fetchDailySeries(metric: String, startDate: String, endDate: String) -> [String: Double] {
        switch metric {
        case "weight":
            return fetchDailyWeight(startDate: startDate, endDate: endDate)
        case "calories":
            return (try? AppDatabase.shared.fetchDailyCalories(from: startDate, to: endDate)) ?? [:]
        case "protein", "carbs", "fat", "fiber":
            return fetchDailyMacro(metric, startDate: startDate, endDate: endDate)
        case "workout_volume":
            return fetchDailyWorkoutVolume(startDate: startDate, endDate: endDate)
        case "glucose_avg":
            return fetchDailyGlucoseAverage(startDate: startDate, endDate: endDate)
        default:
            return [:]
        }
    }

    /// Daily weight series — one entry per day, using the last reading.
    /// Same-day duplicate logs collapse to the most recent value (stable
    /// enough for correlation against other daily metrics).
    private static func fetchDailyWeight(startDate: String, endDate: String) -> [String: Double] {
        let entries = (try? AppDatabase.shared.fetchWeightEntries(from: startDate, to: endDate)) ?? []
        var byDay: [String: Double] = [:]
        for entry in entries where entry.date >= startDate && entry.date <= endDate {
            byDay[entry.date] = entry.weightKg
        }
        return byDay
    }

    /// Daily total of a macro nutrient by iterating dates in the window.
    /// Uses `fetchDailyNutrition(for:)` per day — correct but O(windowDays)
    /// reads. Fine at 90-day max; revisit if we expand to yearly windows.
    private static func fetchDailyMacro(_ metric: String, startDate: String, endDate: String) -> [String: Double] {
        var result: [String: Double] = [:]
        for date in datesInRange(startDate: startDate, endDate: endDate) {
            guard let daily = try? AppDatabase.shared.fetchDailyNutrition(for: date) else { continue }
            let value: Double = {
                switch metric {
                case "protein": return daily.proteinG
                case "carbs":   return daily.carbsG
                case "fat":     return daily.fatG
                case "fiber":   return daily.fiberG
                default:        return 0
                }
            }()
            if value > 0 { result[date] = value }
        }
        return result
    }

    /// Daily workout volume = Σ (weight_lbs × reps) across working sets.
    /// Warmups are excluded so the signal tracks real training load.
    private static func fetchDailyWorkoutVolume(startDate: String, endDate: String) -> [String: Double] {
        let workouts = (try? WorkoutService.fetchWorkouts(limit: 500)) ?? []
        var result: [String: Double] = [:]
        for w in workouts where w.date >= startDate && w.date <= endDate {
            guard let id = w.id else { continue }
            let sets = (try? WorkoutService.fetchSets(forWorkout: id)) ?? []
            let dayVolume = sets.reduce(0.0) { total, s in
                guard !s.isWarmup, let weight = s.weightLbs, let reps = s.reps else { return total }
                return total + weight * Double(reps)
            }
            if dayVolume > 0 { result[w.date, default: 0] += dayVolume }
        }
        return result
    }

    /// Daily average glucose — mean of all readings on that date.
    private static func fetchDailyGlucoseAverage(startDate: String, endDate: String) -> [String: Double] {
        let readings = (try? AppDatabase.shared.fetchGlucoseReadings(from: startDate, to: endDate)) ?? []
        var sums: [String: (sum: Double, count: Int)] = [:]
        for r in readings {
            let date = String(r.timestamp.prefix(10))
            let acc = sums[date] ?? (0, 0)
            sums[date] = (acc.sum + r.glucoseMgdl, acc.count + 1)
        }
        return sums.mapValues { $0.count > 0 ? $0.sum / Double($0.count) : 0 }
    }

    // MARK: - Date helpers

    nonisolated static func dateWindow(windowDays: Int, now: Date = Date()) -> (start: String, end: String) {
        let cal = Calendar.current
        let end = now
        let start = cal.date(byAdding: .day, value: -(windowDays - 1), to: end) ?? end
        let fmt = DateFormatters.dateOnly
        return (fmt.string(from: start), fmt.string(from: end))
    }

    nonisolated static func datesInRange(startDate: String, endDate: String) -> [String] {
        let fmt = DateFormatters.dateOnly
        guard let start = fmt.date(from: startDate),
              let end = fmt.date(from: endDate) else { return [] }
        var out: [String] = []
        var cur = start
        let cal = Calendar.current
        while cur <= end {
            out.append(fmt.string(from: cur))
            guard let next = cal.date(byAdding: .day, value: 1, to: cur) else { break }
            cur = next
        }
        return out
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
