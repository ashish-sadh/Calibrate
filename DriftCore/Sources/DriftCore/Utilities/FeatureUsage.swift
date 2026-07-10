import Foundation

/// On-device feature usage counters — Drift's privacy-compatible telemetry
/// (operator decision 2026-07-09). Counts NEVER leave the device: they're
/// surfaced in Settings → Usage Insights, where the user can explicitly
/// share the text export through the existing feedback channel. This is
/// "friend feedback over telemetry" with better data, not a cloud pipeline.
public enum FeatureUsage {
    private static let storageKey = "drift_feature_usage"

    public static func record(_ event: String) {
        var counts = (UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Int]) ?? [:]
        counts[event, default: 0] += 1
        UserDefaults.standard.set(counts, forKey: storageKey)
    }

    /// All counters, most-used first.
    public static func all() -> [(event: String, count: Int)] {
        let counts = (UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Int]) ?? [:]
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (event: $0.key, count: $0.value) }
    }

    public static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    /// Human-readable export for the explicit share flow.
    public static func exportText() -> String {
        let rows = all().map { "\($0.count)\t\($0.event)" }.joined(separator: "\n")
        return "Drift usage (on-device counts)\n\(rows)"
    }
}
