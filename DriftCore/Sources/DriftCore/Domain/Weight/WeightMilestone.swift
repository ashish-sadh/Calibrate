import Foundation

/// "New Low!" / "New High!" celebration copy for a weigh-in that beats every
/// entry already logged.
///
/// Lifted verbatim out of `WeightViewModel.addWeight` (iOS) so the Android
/// weight store can fire the same milestone from the same rule — the logic is
/// pure arithmetic over the existing history and belongs nowhere near a view
/// model. Direction is goal-aware: a user who is losing celebrates a new
/// minimum, a user who is gaining celebrates a new maximum.
public enum WeightMilestone {

    /// - Parameters:
    ///   - newWeightKg: the weigh-in about to be saved, in kg.
    ///   - existingWeightsKg: every weight already logged, in kg, any order.
    ///   - isLosing: goal direction — true when the user is losing weight.
    ///   - unit: display unit for the message.
    /// - Returns: the celebration message, or nil when this weigh-in is not a
    ///   new extreme (or there is no history to beat yet).
    public static func message(
        newWeightKg: Double,
        existingWeightsKg: [Double],
        isLosing: Bool,
        unit: WeightUnit
    ) -> String? {
        guard !existingWeightsKg.isEmpty else { return nil }
        let display = "\(String(format: "%.1f", unit.convert(fromKg: newWeightKg))) \(unit.displayName)"
        if isLosing {
            guard let currentMin = existingWeightsKg.min(), newWeightKg < currentMin else { return nil }
            return "New Low! \(display)"
        } else {
            guard let currentMax = existingWeightsKg.max(), newWeightKg > currentMax else { return nil }
            return "New High! \(display)"
        }
    }
}
