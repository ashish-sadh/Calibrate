import Foundation

/// Persisted weight goal configuration.
struct WeightGoal: Codable, Sendable {
    var targetWeightKg: Double
    var monthsToAchieve: Int
    var startDate: String       // YYYY-MM-DD
    var startWeightKg: Double

    static let storageKey = "drift_weight_goal"

    var targetWeightLbs: Double { targetWeightKg * 2.20462 }
    var startWeightLbs: Double { startWeightKg * 2.20462 }

    /// Total weight to lose/gain in kg (negative = lose).
    var totalChangeKg: Double { targetWeightKg - startWeightKg }
    var totalChangeLbs: Double { totalChangeKg * 2.20462 }

    /// Required weekly rate in kg/week.
    var requiredWeeklyRateKg: Double {
        let weeks = Double(monthsToAchieve) * 4.33
        return weeks > 0 ? totalChangeKg / weeks : 0
    }

    /// Required daily deficit/surplus in kcal (using configurable energy density).
    var requiredDailyDeficit: Double {
        let config = WeightTrendCalculator.loadConfig()
        return requiredWeeklyRateKg * config.kcalPerKg / 7
    }

    /// Target date.
    var targetDate: Date? {
        guard let start = DateFormatters.dateOnly.date(from: startDate) else { return nil }
        return Calendar.current.date(byAdding: .month, value: monthsToAchieve, to: start)
    }

    /// Days remaining.
    var daysRemaining: Int? {
        guard let target = targetDate else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: target).day ?? 0)
    }

    /// Weeks remaining.
    var weeksRemaining: Double? {
        daysRemaining.map { Double($0) / 7 }
    }

    /// Weight remaining to lose/gain from current.
    func remainingKg(currentWeightKg: Double) -> Double {
        targetWeightKg - currentWeightKg
    }

    /// Progress percentage (0 to 1).
    func progress(currentWeightKg: Double) -> Double {
        guard abs(totalChangeKg) > 0.01 else { return 1 }
        let achieved = currentWeightKg - startWeightKg
        return min(1, max(0, achieved / totalChangeKg))
    }

    /// Whether on track: actual rate vs required rate.
    func isOnTrack(actualWeeklyRateKg: Double) -> OnTrackStatus {
        let required = requiredWeeklyRateKg
        let ratio = required != 0 ? actualWeeklyRateKg / required : 1.0

        // ratio > 1 means exceeding the required rate (ahead)
        // ratio 0.8-1.2 means on track
        // ratio < 0.8 means behind
        if ratio > 1.2 { return .ahead }
        if ratio >= 0.8 { return .onTrack }
        return .behind
    }

    enum OnTrackStatus {
        case ahead, onTrack, behind

        var label: String {
            switch self {
            case .ahead: "Ahead of schedule"
            case .onTrack: "On track"
            case .behind: "Behind schedule"
            }
        }

        var color: String {
            switch self {
            case .ahead: "deficit"
            case .onTrack: "deficit"
            case .behind: "surplus"
            }
        }
    }

    // MARK: - Persistence

    static func load() -> WeightGoal? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let goal = try? JSONDecoder().decode(WeightGoal.self, from: data) else { return nil }
        return goal
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
            UserDefaults.standard.synchronize()
            Log.app.info("Weight goal saved: target=\(targetWeightKg)kg in \(monthsToAchieve) months")
        } else {
            Log.app.error("Failed to encode weight goal")
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.synchronize()
    }
}
