import Foundation

/// One HealthKit-bound quantity derived from a logged food entry. Pure value —
/// DriftCore builds the specs (Tier-0 tested), the iOS writer maps them onto
/// `HKQuantitySample`s. `syncIdentifier` is stable per entry+kind, so re-saving
/// with a higher sync version REPLACES our earlier samples in HealthKit
/// (edits are idempotent, never double-counted) and deletion can target
/// exactly what Drift wrote.
public struct NutritionSampleSpec: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        /// Dietary energy (food you ate) — NOT active energy burned.
        case energyKcal = "kcal"
        case proteinG = "protein"
        case carbsG = "carbs"
        case fatG = "fat"
        case fiberG = "fiber"
    }

    public let kind: Kind
    public let value: Double
    public let syncIdentifier: String
    public let date: Date
}

/// Builds the Apple Health write-back plan for food entries (#934).
public enum NutritionHealthSync {

    /// Specs for one entry — one per macro with a positive value. Entries
    /// without a DB id produce nothing (no stable identity to sync against).
    public static func specs(for entry: FoodEntry) -> [NutritionSampleSpec] {
        guard let id = entry.id else { return [] }
        let when = timestamp(for: entry)
        let values: [(NutritionSampleSpec.Kind, Double)] = [
            (.energyKcal, entry.calories),
            (.proteinG, entry.proteinG),
            (.carbsG, entry.carbsG),
            (.fatG, entry.fatG),
            (.fiberG, entry.fiberG),
        ]
        return values.compactMap { kind, value in
            guard value > 0 else { return nil }
            return NutritionSampleSpec(
                kind: kind, value: value,
                syncIdentifier: syncIdentifier(entryId: id, kind: kind),
                date: when)
        }
    }

    /// Every possible identifier for an entry — used to delete Drift's
    /// samples when the entry is removed (covers macros that were zero at
    /// write time; deleting a never-written identifier is a no-op).
    public static func syncIdentifiers(entryId: Int64) -> [String] {
        NutritionSampleSpec.Kind.allCases.map { syncIdentifier(entryId: entryId, kind: $0) }
    }

    static func syncIdentifier(entryId: Int64, kind: NutritionSampleSpec.Kind) -> String {
        "drift-food-\(entryId)-\(kind.rawValue)"
    }

    /// Sample timestamp: the entry's `loggedAt` moment when parseable, else
    /// noon on its calendar day (never midnight — day-boundary ambiguity in
    /// Health's day buckets), else now.
    public static func timestamp(for entry: FoodEntry) -> Date {
        if let d = iso8601.date(from: entry.loggedAt) ?? iso8601Fractional.date(from: entry.loggedAt) {
            return d
        }
        if let dayString = entry.date, let day = DateFormatters.dateOnly.date(from: dayString) {
            return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        }
        return Date()
    }

    private static let iso8601 = ISO8601DateFormatter()
    private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

/// Seam for the iOS HealthKit writer (mirrors `HealthDataProvider` /
/// `WidgetRefresher`). The DB mutation funnels call these fire-and-forget;
/// the writer owns gating (user toggle), foreign-source checks, and the
/// actual HealthKit I/O. nil (macOS, tests) = no-op.
public protocol HealthNutritionWriter: AnyObject, Sendable {
    /// Entry inserted or updated — write/replace its Health samples.
    func entrySaved(_ entry: FoodEntry)
    /// Entry deleted — remove the samples Drift wrote for it.
    func entryDeleted(id: Int64)
}
