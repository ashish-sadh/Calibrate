import Foundation

// MARK: - Health Data Contexts (Sleep, Glucose, Biomarkers, DEXA, Cycle)

extension AIContextBuilder {

    // MARK: - Sleep & Recovery Context

    static func sleepRecoveryContext() -> String {
        guard let data = AIDataCache.shared.sleep else { return "No sleep data available." }
        var lines: [String] = ["Sleep & Recovery:"]
        if data.sleepHours > 0 {
            lines.append("  Last night: \(String(format: "%.1f", data.sleepHours))h sleep")
        }
        if let detail = data.sleepDetail {
            if detail.remHours > 0 { lines.append("  REM: \(String(format: "%.1f", detail.remHours))h") }
            if detail.deepHours > 0 { lines.append("  Deep: \(String(format: "%.1f", detail.deepHours))h") }
        }
        if data.hrvMs > 0 { lines.append("  HRV: \(Int(data.hrvMs))ms") }
        if data.restingHR > 0 { lines.append("  RHR: \(Int(data.restingHR))bpm") }
        lines.append("  Recovery: \(data.recoveryScore)/100")

        // Pre-computed assessment
        if data.recoveryScore >= 80 {
            lines.append("  Assessment: well recovered — good for intense training")
        } else if data.recoveryScore >= 50 {
            lines.append("  Assessment: moderate recovery — light to moderate activity ok")
        } else if data.recoveryScore > 0 {
            lines.append("  Assessment: low recovery — rest or light activity recommended")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Glucose Context

    static func glucoseContext() -> String {
        let today = DateFormatters.todayString
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) else { return "" }
        let endStr = DateFormatters.dateOnly.string(from: tomorrow)
        guard let readings = try? AppDatabase.shared.fetchGlucoseReadings(from: today, to: endStr),
              !readings.isEmpty else { return "No glucose data today." }

        let values = readings.map(\.glucoseMgdl)
        let avg = values.reduce(0, +) / Double(values.count)
        let inNormal = readings.filter { $0.zone == .normal }.count
        let spikes = readings.filter { $0.glucoseMgdl > 140 }.count

        var lines = ["Glucose (\(readings.count) readings): avg \(Int(avg))mg/dL | range \(Int(values.min() ?? 0))-\(Int(values.max() ?? 0)) | \(Int(Double(inNormal) / Double(readings.count) * 100))% normal"]
        if spikes > 0 { lines.append("Spikes: \(spikes) readings >140mg/dL") }

        // Pre-computed assessment
        if avg < 100 { lines.append("Assessment: glucose well controlled") }
        else if avg < 126 { lines.append("Assessment: slightly elevated average — monitor diet") }
        else { lines.append("Assessment: elevated glucose — consider consulting doctor") }

        return lines.joined(separator: "\n")
    }

    // MARK: - Biomarker Context

    static func biomarkerContext() -> String {
        guard let results = try? AppDatabase.shared.fetchLatestBiomarkerResults(),
              !results.isEmpty else { return "No lab results on file." }

        var lines = ["Biomarkers (\(results.count)):"]
        var optimalCount = 0
        var outOfRange: [String] = []

        for r in results {
            guard let def = BiomarkerKnowledgeBase.byId[r.biomarkerId] else { continue }
            let status = def.status(for: r.normalizedValue)
            if status == .optimal {
                optimalCount += 1
            } else {
                let direction = r.normalizedValue < def.optimalLow ? "low" : "high"
                var entry = "\(def.name): \(String(format: "%.1f", r.value))\(r.unit) [\(direction), optimal \(String(format: "%.0f", def.optimalLow))-\(String(format: "%.0f", def.optimalHigh))]"
                // Add improvement tip for first 2 out-of-range markers (save tokens)
                if outOfRange.count < 2, !def.howToImprove.isEmpty {
                    let tip = String(def.howToImprove.prefix(80))
                    entry += " Tip: \(tip)"
                }
                outOfRange.append(entry)
            }
        }

        // Show out-of-range first (most actionable), then summary
        for marker in outOfRange.prefix(8) {
            lines.append("  \(marker)")
        }
        lines.append("  \(optimalCount)/\(results.count) optimal")
        return lines.joined(separator: "\n")
    }

    // MARK: - DEXA / Body Composition Context

    static func dexaContext() -> String {
        var lines: [String] = []

        // Check body_composition table first (HealthKit + manual entries — more common)
        if let entries = try? AppDatabase.shared.fetchBodyComposition(), let latest = entries.first {
            lines.append("Body Composition (\(latest.date)):")
            if let bf = latest.bodyFatPct { lines.append("  Body Fat: \(String(format: "%.1f", bf))%") }
            if let bmi = latest.bmi { lines.append("  BMI: \(String(format: "%.1f", bmi))") }
            if let water = latest.waterPct { lines.append("  Water: \(String(format: "%.1f", water))%") }
            if let muscle = latest.muscleMassKg { lines.append("  Muscle: \(String(format: "%.1f", muscle * 2.20462)) lbs") }
            if let bone = latest.boneMassKg { lines.append("  Bone: \(String(format: "%.1f", bone * 2.20462)) lbs") }
            if let visc = latest.visceralFat { lines.append("  Visceral Fat: \(visc)") }

            // Compare with previous entry
            if entries.count > 1 {
                let prev = entries[1]
                if let curBf = latest.bodyFatPct, let prevBf = prev.bodyFatPct {
                    lines.append("  Change from \(prev.date): \(String(format: "%+.1f", curBf - prevBf))% body fat")
                }
                if let curM = latest.muscleMassKg, let prevM = prev.muscleMassKg {
                    lines.append("  Muscle: \(String(format: "%+.1f", (curM - prevM) * 2.20462)) lbs")
                }
            }
        }

        // Also check DEXA scans (from BodySpec PDF imports)
        if let scans = try? AppDatabase.shared.fetchDEXAScans(), let latest = scans.first {
            lines.append("DEXA Scan (\(latest.scanDate)):")
            if let bf = latest.bodyFatPct {
                let category: String
                switch bf {
                case ..<15: category = "athletic"
                case ..<20: category = "fit"
                case ..<25: category = "average"
                case ..<30: category = "above average"
                default: category = "high"
                }
                lines.append("  BF: \(String(format: "%.1f", bf))% (\(category))")
            }
            if let lean = latest.leanMassLbs { lines.append("  Lean: \(String(format: "%.1f", lean)) lbs") }
            if let fat = latest.fatMassLbs { lines.append("  Fat: \(String(format: "%.1f", fat)) lbs") }
            if let rmr = latest.rmrCalories { lines.append("  RMR: \(Int(rmr)) kcal") }

            if scans.count > 1 {
                let prev = scans[1]
                if let curBf = latest.bodyFatPct, let prevBf = prev.bodyFatPct {
                    lines.append("  Change from \(prev.scanDate): \(String(format: "%+.1f", curBf - prevBf))% body fat")
                }
            }
        }

        return lines.isEmpty ? "No body composition data. Log measurements from the Body Composition screen or import a DEXA scan." : lines.joined(separator: "\n")
    }

    // MARK: - Cycle Context

    static func cycleContext() -> String {
        guard let data = AIDataCache.shared.cycle, data.periodCount >= 2 else { return "" }

        var lines = ["Cycle:"]
        if let day = data.currentCycleDay { lines.append("  Day \(day) of cycle") }
        if let phase = data.currentPhase { lines.append("  Phase: \(phase)") }
        if let avg = data.avgCycleLength { lines.append("  Average cycle: \(avg) days") }
        return lines.joined(separator: "\n")
    }
}
