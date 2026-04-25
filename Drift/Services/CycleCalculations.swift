import Foundation
import DriftCore

// MARK: - Cycle Period Grouping

struct CyclePeriod {
    let startDate: Date
    let days: [HealthKitService.CycleEntry]

    var endDate: Date { days.last?.date ?? startDate }

    var dominantFlow: Int {
        let flows = days.map(\.flow).filter { $0 >= 1 && $0 <= 4 }
        guard !flows.isEmpty else { return 1 }
        return flows.max() ?? 2
    }

    /// HK values: 1=unspecified, 2=light, 3=medium, 4=heavy
    var dominantFlowDisplay: String {
        switch dominantFlow {
        case 1: "Unspecified"
        case 2: "Light"
        case 3: "Medium"
        case 4: "Heavy"
        default: "Light"
        }
    }
}

enum CycleCalculations {
    /// Groups cycle entries into periods. Entries more than 3 days apart start a new period.
    /// HK values: 1=unspecified, 2=light, 3=medium, 4=heavy, 5=none. Include 1-4, exclude 0 and 5.
    static func groupIntoPeriods(_ entries: [HealthKitService.CycleEntry]) -> [CyclePeriod] {
        let flowEntries = entries.filter { $0.flow >= 1 && $0.flow <= 4 }
        guard !flowEntries.isEmpty else { return [] }

        let sorted = flowEntries.sorted { $0.date < $1.date }
        var periods: [CyclePeriod] = []
        var currentDays: [HealthKitService.CycleEntry] = []

        for entry in sorted {
            if let last = currentDays.last {
                let gap = Calendar.current.dateComponents([.day], from: last.date, to: entry.date).day ?? 0
                if gap > 3 {
                    periods.append(CyclePeriod(startDate: currentDays.first!.date, days: currentDays))
                    currentDays = [entry]
                } else {
                    currentDays.append(entry)
                }
            } else {
                currentDays = [entry]
            }
        }
        if !currentDays.isEmpty {
            periods.append(CyclePeriod(startDate: currentDays.first!.date, days: currentDays))
        }
        return periods
    }

    /// Compute cycle lengths (days between period starts) with labels.
    static func cycleLengthsWithDates(periods: [CyclePeriod]) -> [(label: String, length: Int)] {
        let starts = periods.map(\.startDate)
        guard starts.count >= 2 else { return [] }
        var result: [(label: String, length: Int)] = []
        for i in 1..<starts.count {
            let days = Calendar.current.dateComponents([.day], from: starts[i - 1], to: starts[i]).day ?? 0
            if days > 0 {
                result.append((label: DateFormatters.shortDisplay.string(from: starts[i - 1]), length: days))
            }
        }
        return result
    }

    /// Average cycle length from periods. Returns nil if fewer than 2 periods.
    static func averageCycleLength(periods: [CyclePeriod]) -> Int? {
        let lengths = cycleLengthsWithDates(periods: periods).map(\.length)
        guard !lengths.isEmpty else { return nil }
        return lengths.reduce(0, +) / lengths.count
    }

    /// Current cycle day (days since last period start + 1).
    static func currentCycleDay(periods: [CyclePeriod], now: Date = Date()) -> Int? {
        guard let lastStart = periods.last?.startDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: lastStart, to: now).day ?? 0
        return days + 1
    }

    /// Estimated ovulation day using standard luteal phase formula.
    static func ovulationDay(cycleLength: Int) -> Int {
        max(cycleLength - 14, cycleLength / 2)
    }

    /// Current phase name for display.
    static func currentPhase(cycleDay: Int, cycleLength: Int) -> String? {
        if cycleDay <= 5 { return "Menstrual phase" }
        let ovDay = ovulationDay(cycleLength: cycleLength)
        if cycleDay < ovDay - 1 { return "Follicular phase" }
        if cycleDay <= ovDay + 1 { return "Ovulation window" }
        return "Luteal phase"
    }

    /// Current phase ID for styling.
    static func currentPhaseId(cycleDay: Int, cycleLength: Int) -> String {
        if cycleDay <= 5 { return "period" }
        let ovDay = ovulationDay(cycleLength: cycleLength)
        if cycleDay < ovDay - 1 { return "follicular" }
        if cycleDay <= ovDay + 1 { return "ovulation" }
        return "luteal"
    }
}
