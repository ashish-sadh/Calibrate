import Foundation
import DriftCore

/// Unified sleep & recovery service — used by both UI views and AI tool calls.
@MainActor
enum SleepRecoveryService {

    /// Get last night's sleep data.
    static func getSleep() -> String {
        guard let data = AIDataCache.shared.sleep else { return "No sleep data available." }
        var lines: [String] = []
        lines.append("Sleep: \(String(format: "%.1f", data.sleepHours)) hours")
        if let detail = data.sleepDetail {
            lines.append("Stages: \(String(format: "%.1f", detail.remHours))h REM, \(String(format: "%.1f", detail.deepHours))h deep")
        }
        if data.recoveryScore > 0 {
            lines.append("Sleep score: \(data.recoveryScore)/100")
        }
        return lines.joined(separator: "\n")
    }

    /// Get recovery score with HRV and RHR.
    static func getRecovery() -> String {
        guard let data = AIDataCache.shared.sleep else { return "No recovery data available." }
        var lines: [String] = []
        if data.recoveryScore > 0 { lines.append("Recovery: \(data.recoveryScore)/100") }
        if data.hrvMs > 0 { lines.append("HRV: \(Int(data.hrvMs)) ms") }
        if data.restingHR > 0 { lines.append("Resting HR: \(Int(data.restingHR)) bpm") }
        return lines.isEmpty ? "No recovery data available." : lines.joined(separator: "\n")
    }

    /// Get HRV details.
    static func getHRV() -> String {
        guard let data = AIDataCache.shared.sleep, data.hrvMs > 0 else { return "No HRV data available." }
        return "HRV: \(Int(data.hrvMs)) ms. Resting HR: \(Int(data.restingHR)) bpm."
    }

    /// Training readiness based on recovery + sleep.
    static func getReadiness() -> String {
        guard let data = AIDataCache.shared.sleep else { return "No data to assess readiness." }
        if data.recoveryScore >= 70 {
            return "Good to train. Recovery: \(data.recoveryScore)/100, \(String(format: "%.1f", data.sleepHours))h sleep."
        } else if data.recoveryScore >= 40 {
            return "Moderate recovery (\(data.recoveryScore)/100). Light to moderate training recommended."
        } else if data.recoveryScore > 0 {
            return "Low recovery (\(data.recoveryScore)/100). Consider rest or light activity."
        }
        return "Not enough data to assess readiness."
    }
}
