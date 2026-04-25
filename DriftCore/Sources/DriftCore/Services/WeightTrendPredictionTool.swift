import Foundation
import DriftCore

@MainActor
public enum WeightTrendPredictionTool {

    nonisolated static let toolName = "weight_trend_prediction"

    private nonisolated static let minEntriesRequired = 7
    private nonisolated static let flatSlopeThresholdKgPerDay = 0.01 / 7.0
    private nonisolated static let wrongDirectionThresholdKgPerDay = 0.005
    private nonisolated static let maxProjectionDays = 1825

    // MARK: - Registration

    static func syncRegistration(registry: ToolRegistry = .shared) {
        registry.register(schema)
    }

    static var schema: ToolSchema {
        ToolSchema(
            id: "insights.weight_trend_prediction",
            name: toolName,
            service: "insights",
            description: "User asks when they'll reach their goal weight or how long it will take. Returns projected date, weekly rate, and confidence based on current trend.",
            parameters: [],
            handler: { _ in .text(run()) }
        )
    }

    // MARK: - Entry point

    public static func run() -> String {
        guard let goal = WeightGoal.load() else {
            return "Set a goal weight first — try 'set my goal to 75 kg' and I'll project when you'll get there."
        }

        let entries = WeightServiceAPI.getHistory(days: 30)
        guard entries.count >= minEntriesRequired else {
            return "Need at least \(minEntriesRequired) days of weight data to predict — you have \(entries.count). Keep logging daily and ask again."
        }

        guard let reg = linearRegression(entries: entries) else {
            return "Couldn't compute a trend. Make sure weights are logged on different dates."
        }

        let u = Preferences.weightUnit
        let currentKg = WeightTrendService.shared.latestWeightKg ?? entries.sorted { $0.date > $1.date }.first?.weightKg ?? 70
        let targetKg = goal.targetWeightKg
        let slopePerDay = reg.slopePerDay
        let slopePerWeek = slopePerDay * 7
        let remaining = targetKg - currentKg
        let isLosing = targetKg < currentKg

        let isFlat = abs(slopePerDay) < flatSlopeThresholdKgPerDay
        let wrongDirection = (isLosing && slopePerDay > wrongDirectionThresholdKgPerDay) ||
                             (!isLosing && slopePerDay < -wrongDirectionThresholdKgPerDay)

        let targetDisplay = String(format: "%.1f", u.convert(fromKg: targetKg))
        let rateDisplay = String(format: "%.2f", abs(u.convert(fromKg: slopePerWeek)))
        let currentDisplay = String(format: "%.1f", u.convert(fromKg: currentKg))

        if isFlat {
            return "Your weight has been stable at ~\(currentDisplay) \(u.displayName). At this rate you won't reach \(targetDisplay) \(u.displayName). Adjust your diet or training to build momentum."
        }

        if wrongDirection {
            let dir = isLosing ? "gaining" : "losing"
            return "You're currently \(dir) \(rateDisplay) \(u.displayName)/week — moving away from your goal of \(targetDisplay) \(u.displayName). Refocus on nutrition and training to reverse the trend."
        }

        let daysToGoal = remaining / slopePerDay
        if daysToGoal > Double(maxProjectionDays) {
            return "At \(rateDisplay) \(u.displayName)/week, reaching \(targetDisplay) \(u.displayName) would take over 5 years. Consider adjusting your goal timeline or increasing your weekly rate."
        }

        guard daysToGoal > 0 else {
            return "You've already reached or passed your goal of \(targetDisplay) \(u.displayName). Consider setting a new goal."
        }

        let projectedDate = Calendar.current.date(byAdding: .day, value: Int(daysToGoal.rounded()), to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        let dateStr = formatter.string(from: projectedDate)
        let weeksAway = max(1, Int((daysToGoal / 7).rounded()))
        let r2Pct = Int(reg.r2 * 100)

        return "At your current rate of \(rateDisplay) \(u.displayName)/week, you'll reach \(targetDisplay) \(u.displayName) around \(dateStr) (~\(weeksAway) weeks). Trend confidence: \(r2Label(reg.r2)) (R²=\(r2Pct)%)."
    }

    // MARK: - OLS linear regression

    struct RegressionResult: Sendable {
        let slopePerDay: Double
        let interceptKg: Double
        let r2: Double
    }

    nonisolated static func linearRegression(entries: [WeightEntry]) -> RegressionResult? {
        guard entries.count >= 2 else { return nil }
        let fmt = DateFormatters.dateOnly
        let sorted = entries.sorted { $0.date < $1.date }
        guard let firstDate = fmt.date(from: sorted.first!.date) else { return nil }

        let pairs: [(x: Double, y: Double)] = sorted.compactMap { e in
            guard let d = fmt.date(from: e.date) else { return nil }
            let dayIndex = Calendar.current.dateComponents([.day], from: firstDate, to: d).day ?? 0
            return (Double(dayIndex), e.weightKg)
        }
        guard pairs.count >= 2 else { return nil }

        let n = Double(pairs.count)
        let sumX = pairs.map(\.x).reduce(0, +)
        let sumY = pairs.map(\.y).reduce(0, +)
        let sumXY = pairs.map { $0.x * $0.y }.reduce(0, +)
        let sumX2 = pairs.map { $0.x * $0.x }.reduce(0, +)
        let denom = n * sumX2 - sumX * sumX
        guard abs(denom) > 0 else { return nil }

        let slope = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n
        let meanY = sumY / n
        let ssRes = pairs.map { pow($0.y - (slope * $0.x + intercept), 2) }.reduce(0, +)
        let ssTot = pairs.map { pow($0.y - meanY, 2) }.reduce(0, +)
        let r2 = ssTot > 0 ? max(0, 1 - ssRes / ssTot) : 1.0

        return RegressionResult(slopePerDay: slope, interceptKg: intercept, r2: r2)
    }

    nonisolated static func r2Label(_ r2: Double) -> String {
        if r2 >= 0.7 { return "high" }
        if r2 >= 0.4 { return "moderate" }
        return "low"
    }
}
