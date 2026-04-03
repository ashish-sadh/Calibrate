import Foundation
import Testing
@testable import Drift

// MARK: - groupIntoPeriods Tests

@Test func cycleGroupPeriodsEmpty() async throws {
    let result = CycleCalculations.groupIntoPeriods([])
    #expect(result.isEmpty)
}

@Test func cycleGroupPeriodsSingleEntry() async throws {
    let entry = HealthKitService.CycleEntry(date: Date(), flow: 2)
    let result = CycleCalculations.groupIntoPeriods([entry])
    #expect(result.count == 1)
    #expect(result[0].days.count == 1)
}

@Test func cycleGroupPeriodsGap3DaysSamePeriod() async throws {
    let cal = Calendar.current
    let d1 = cal.date(byAdding: .day, value: -5, to: Date())!
    let d2 = cal.date(byAdding: .day, value: -2, to: Date())! // 3 days later
    let entries = [
        HealthKitService.CycleEntry(date: d1, flow: 2),
        HealthKitService.CycleEntry(date: d2, flow: 1),
    ]
    let result = CycleCalculations.groupIntoPeriods(entries)
    #expect(result.count == 1, "3-day gap should be same period, got \(result.count)")
}

@Test func cycleGroupPeriodsGap4DaysSplits() async throws {
    let cal = Calendar.current
    let d1 = cal.date(byAdding: .day, value: -10, to: Date())!
    let d2 = cal.date(byAdding: .day, value: -6, to: Date())! // 4 days later
    let entries = [
        HealthKitService.CycleEntry(date: d1, flow: 2),
        HealthKitService.CycleEntry(date: d2, flow: 2),
    ]
    let result = CycleCalculations.groupIntoPeriods(entries)
    #expect(result.count == 2, "4-day gap should split into 2 periods, got \(result.count)")
}

@Test func cycleGroupPeriodsFiltersInvalidFlow() async throws {
    let cal = Calendar.current
    let entries = [
        HealthKitService.CycleEntry(date: cal.date(byAdding: .day, value: -3, to: Date())!, flow: 0),
        HealthKitService.CycleEntry(date: cal.date(byAdding: .day, value: -2, to: Date())!, flow: 2),
        HealthKitService.CycleEntry(date: cal.date(byAdding: .day, value: -1, to: Date())!, flow: 4),
    ]
    let result = CycleCalculations.groupIntoPeriods(entries)
    #expect(result.count == 1)
    #expect(result[0].days.count == 1, "Only flow=2 should be included")
}

@Test func cycleGroupPeriodsUnsortedInput() async throws {
    let cal = Calendar.current
    let d1 = cal.date(byAdding: .day, value: -5, to: Date())!
    let d2 = cal.date(byAdding: .day, value: -4, to: Date())!
    let d3 = cal.date(byAdding: .day, value: -3, to: Date())!
    // Pass in reverse order
    let entries = [
        HealthKitService.CycleEntry(date: d3, flow: 1),
        HealthKitService.CycleEntry(date: d1, flow: 3),
        HealthKitService.CycleEntry(date: d2, flow: 2),
    ]
    let result = CycleCalculations.groupIntoPeriods(entries)
    #expect(result.count == 1)
    #expect(result[0].days.count == 3)
    #expect(result[0].startDate == d1, "Should sort by date")
}

// MARK: - averageCycleLength Tests

@Test func cycleAverageLengthVaryingCycles() async throws {
    let cal = Calendar.current
    let now = Date()
    // 3 periods: 28 days apart, then 30 days apart
    let p1Start = cal.date(byAdding: .day, value: -63, to: now)!
    let p2Start = cal.date(byAdding: .day, value: -35, to: now)! // 28 days gap
    let p3Start = cal.date(byAdding: .day, value: -5, to: now)!  // 30 days gap

    let entries = [p1Start, p2Start, p3Start].flatMap { start in
        (0..<5).map { day in
            HealthKitService.CycleEntry(date: cal.date(byAdding: .day, value: day, to: start)!, flow: 2)
        }
    }
    let periods = CycleCalculations.groupIntoPeriods(entries)
    let avg = CycleCalculations.averageCycleLength(periods: periods)
    #expect(avg == 29, "Average of 28 and 30 should be 29, got \(avg ?? -1)")
}

@Test func cycleAverageLengthSinglePeriodNil() async throws {
    let entry = HealthKitService.CycleEntry(date: Date(), flow: 2)
    let periods = CycleCalculations.groupIntoPeriods([entry])
    #expect(CycleCalculations.averageCycleLength(periods: periods) == nil)
}

// MARK: - currentCycleDay Tests

@Test func cycleCurrentDayBasic() async throws {
    let cal = Calendar.current
    let tenDaysAgo = cal.date(byAdding: .day, value: -10, to: Date())!
    let entries = (0..<5).map { day in
        HealthKitService.CycleEntry(date: cal.date(byAdding: .day, value: day, to: tenDaysAgo)!, flow: 2)
    }
    let periods = CycleCalculations.groupIntoPeriods(entries)
    let day = CycleCalculations.currentCycleDay(periods: periods)
    #expect(day == 11, "10 days ago + 1 = day 11, got \(day ?? -1)")
}

// MARK: - ovulationDay Tests

@Test func cycleOvulationDay28() async throws {
    #expect(CycleCalculations.ovulationDay(cycleLength: 28) == 14)
}

@Test func cycleOvulationDay30() async throws {
    #expect(CycleCalculations.ovulationDay(cycleLength: 30) == 16)
}

@Test func cycleOvulationDay26() async throws {
    #expect(CycleCalculations.ovulationDay(cycleLength: 26) == 13)
}

// MARK: - currentPhase Tests

@Test func cyclePhaseDay3IsMenstrual() async throws {
    #expect(CycleCalculations.currentPhase(cycleDay: 3, cycleLength: 28) == "Menstrual phase")
}

@Test func cyclePhaseDay8IsFollicular() async throws {
    #expect(CycleCalculations.currentPhase(cycleDay: 8, cycleLength: 28) == "Follicular phase")
}

@Test func cyclePhaseDay14IsOvulation() async throws {
    let phase = CycleCalculations.currentPhase(cycleDay: 14, cycleLength: 28)
    #expect(phase == "Ovulation window", "Day 14 of 28 should be ovulation, got \(phase ?? "nil")")
}

@Test func cyclePhaseDay20IsLuteal() async throws {
    #expect(CycleCalculations.currentPhase(cycleDay: 20, cycleLength: 28) == "Luteal phase")
}
