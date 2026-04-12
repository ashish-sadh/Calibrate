import Foundation

/// Unified glucose service — used by both UI views and AI tool calls.
@MainActor
enum GlucoseService {

    /// Whether glucose readings exist for today.
    static func hasDataToday() -> Bool {
        let today = DateFormatters.todayString
        return ((try? AppDatabase.shared.fetchGlucoseReadings(from: today, to: today))?.isEmpty == false)
    }

    /// Get glucose readings summary for today.
    static func getReadings() -> String {
        let today = DateFormatters.todayString
        guard let readings = try? AppDatabase.shared.fetchGlucoseReadings(from: today, to: today),
              !readings.isEmpty else { return "No glucose data for today." }

        let values = readings.map(\.glucoseMgdl)
        let avg = values.reduce(0, +) / Double(values.count)
        let inZone = values.filter { $0 >= 70 && $0 <= 140 }.count
        let inZonePct = Int(Double(inZone) / Double(values.count) * 100)

        let minVal = Int(values.min() ?? 0)
        let maxVal = Int(values.max() ?? 0)
        return "Glucose: avg \(Int(avg)) mg/dL, range \(minVal)-\(maxVal), \(inZonePct)% in zone (70-140). \(readings.count) readings today."
    }

    /// Detect glucose spikes (readings > 140 mg/dL).
    static func detectSpikes() -> String {
        let today = DateFormatters.todayString
        guard let readings = try? AppDatabase.shared.fetchGlucoseReadings(from: today, to: today),
              !readings.isEmpty else { return "No glucose data to check for spikes." }

        let spikes = readings.filter { $0.glucoseMgdl > 140 }
        if spikes.isEmpty {
            return "No glucose spikes today. All readings under 140 mg/dL."
        }
        let peak = spikes.max(by: { $0.glucoseMgdl < $1.glucoseMgdl })
        return "\(spikes.count) spike(s) detected (>140 mg/dL). Peak: \(Int(peak?.glucoseMgdl ?? 0)) mg/dL."
    }
}
