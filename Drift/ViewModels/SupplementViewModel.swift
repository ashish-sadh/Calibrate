import Foundation
import Observation

@MainActor
@Observable
final class SupplementViewModel {
    private let database: AppDatabase

    var supplements: [Supplement] = []
    var todayLogs: [Int64: SupplementLog] = [:]
    var selectedDate: Date = Date()
    var consistencyData: [DayConsistency] = []

    struct DayConsistency: Identifiable {
        let id: String // date string
        let date: Date
        let taken: Int
        let total: Int
        var ratio: Double { total > 0 ? Double(taken) / Double(total) : 0 }
    }

    var dateString: String { DateFormatters.dateOnly.string(from: selectedDate) }
    var takenCount: Int { todayLogs.values.filter(\.taken).count }
    var totalCount: Int { supplements.count }

    // Streak: consecutive days with all supplements taken
    var currentStreak: Int {
        var streak = 0
        let cal = Calendar.current
        for i in 0..<consistencyData.count {
            let day = consistencyData.reversed()[i] // oldest first after reverse... actually let's just iterate properly
            break
        }
        // Walk backwards from today
        for dayOffset in 0..<60 {
            let date = cal.date(byAdding: .day, value: -dayOffset, to: Date())!
            let dateStr = DateFormatters.dateOnly.string(from: date)
            if let day = consistencyData.first(where: { $0.id == dateStr }) {
                if day.ratio >= 1.0 { streak += 1 } else { break }
            } else {
                break // no data = streak broken
            }
        }
        return streak
    }

    // Last 30 days average
    var thirtyDayAverage: Double {
        let recent = consistencyData.suffix(30)
        guard !recent.isEmpty else { return 0 }
        return recent.map(\.ratio).reduce(0, +) / Double(recent.count)
    }

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func loadSupplements() {
        do {
            supplements = try database.fetchActiveSupplements()
            let logs = try database.fetchSupplementLogs(for: dateString)
            todayLogs = Dictionary(uniqueKeysWithValues: logs.compactMap { ($0.supplementId, $0) })
            loadConsistency()
        } catch {
            Log.supplements.error("Failed to load: \(error.localizedDescription)")
        }
    }

    func loadConsistency() {
        do {
            let cal = Calendar.current
            let endDate = Date()
            let startDate = cal.date(byAdding: .day, value: -59, to: endDate)!
            let startStr = DateFormatters.dateOnly.string(from: startDate)
            let endStr = DateFormatters.dateOnly.string(from: endDate)

            let allLogs = try database.fetchSupplementLogs(from: startStr, to: endStr)
            let supplementCount = supplements.count

            // Group logs by date
            var byDate: [String: Int] = [:] // date -> count of taken
            for log in allLogs where log.taken {
                byDate[log.date, default: 0] += 1
            }

            // Build 60-day grid
            var days: [DayConsistency] = []
            for dayOffset in (0..<60).reversed() {
                let date = cal.date(byAdding: .day, value: -dayOffset, to: endDate)!
                let dateStr = DateFormatters.dateOnly.string(from: date)
                let taken = byDate[dateStr] ?? 0
                days.append(DayConsistency(id: dateStr, date: date, taken: taken, total: supplementCount))
            }
            consistencyData = days
        } catch {
            Log.supplements.error("Failed to load consistency: \(error.localizedDescription)")
        }
    }

    func seedDefaultsIfNeeded() {
        do {
            let existing = try database.fetchActiveSupplements()
            guard existing.isEmpty else { return }
            guard let url = Bundle.main.url(forResource: "default_supplements", withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return }
            struct DS: Codable { let name: String; let dosage: String; let unit: String; let sortOrder: Int }
            let defaults = try JSONDecoder().decode([DS].self, from: data)
            for d in defaults {
                var s = Supplement(name: d.name, dosage: d.dosage, unit: d.unit, sortOrder: d.sortOrder)
                try database.saveSupplement(&s)
            }
            loadSupplements()
        } catch {
            Log.supplements.error("Failed to seed: \(error.localizedDescription)")
        }
    }

    func toggleTaken(supplementId: Int64) {
        do {
            try database.toggleSupplementTaken(supplementId: supplementId, date: dateString)
            loadSupplements()
        } catch {
            Log.supplements.error("Failed to toggle: \(error.localizedDescription)")
        }
    }

    func addCustomSupplement(name: String, dosage: String, unit: String) {
        do {
            var s = Supplement(name: name, dosage: dosage, unit: unit, sortOrder: supplements.count)
            try database.saveSupplement(&s)
            loadSupplements()
        } catch {
            Log.supplements.error("Failed to add: \(error.localizedDescription)")
        }
    }

    func isTaken(_ supplementId: Int64) -> Bool {
        todayLogs[supplementId]?.taken ?? false
    }
}
