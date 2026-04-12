import Foundation

/// Unified biomarker service — used by both UI views and AI tool calls.
@MainActor
enum BiomarkerService {

    /// Whether any biomarker results exist.
    static func hasResults() -> Bool {
        ((try? AppDatabase.shared.fetchLatestBiomarkerResults())?.isEmpty == false)
    }

    /// Get out-of-range biomarker results.
    static func getResults() -> String {
        guard let results = try? AppDatabase.shared.fetchLatestBiomarkerResults(),
              !results.isEmpty else { return "No biomarker data. Upload a lab report to get started." }

        var outOfRange: [String] = []
        var optimal = 0
        for r in results {
            if let def = BiomarkerKnowledgeBase.byId[r.biomarkerId] {
                let status = def.status(for: r.normalizedValue)
                if status != .optimal {
                    outOfRange.append("\(def.name): \(String(format: "%.1f", r.normalizedValue)) \(def.unit) (\(status))")
                } else {
                    optimal += 1
                }
            }
        }

        if outOfRange.isEmpty {
            return "All \(results.count) biomarkers are in optimal range."
        }
        return "Out of range: \(outOfRange.joined(separator: ", ")). \(optimal) markers optimal."
    }

    /// Get detail for a specific biomarker.
    static func getDetail(name: String) -> String {
        let lower = name.lowercased()
        guard let def = BiomarkerKnowledgeBase.all.first(where: { $0.name.lowercased().contains(lower) }) else {
            return "Biomarker '\(name)' not found."
        }

        guard let results = try? AppDatabase.shared.fetchBiomarkerResults(forBiomarkerId: def.id),
              let latest = results.first else {
            return "\(def.name): no data yet. Upload a lab report."
        }

        let status = def.status(for: latest.normalizedValue)
        return "\(def.name): \(String(format: "%.1f", latest.normalizedValue)) \(def.unit) — \(status). Optimal: \(String(format: "%.0f", def.optimalLow))-\(String(format: "%.0f", def.optimalHigh)) \(def.unit)."
    }
}
