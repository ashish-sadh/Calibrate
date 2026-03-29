import Foundation
import Observation

@MainActor
@Observable
final class SupplementViewModel {
    private let database: AppDatabase

    var supplements: [Supplement] = []
    var todayLogs: [Int64: SupplementLog] = [:]  // keyed by supplement_id
    var selectedDate: Date = Date()

    var dateString: String {
        DateFormatters.dateOnly.string(from: selectedDate)
    }

    var takenCount: Int {
        todayLogs.values.filter(\.taken).count
    }

    var totalCount: Int {
        supplements.count
    }

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func loadSupplements() {
        do {
            supplements = try database.fetchActiveSupplements()
            let logs = try database.fetchSupplementLogs(for: dateString)
            todayLogs = Dictionary(uniqueKeysWithValues: logs.compactMap { log in
                (log.supplementId, log)
            })
        } catch {
            print("Failed to load supplements: \(error)")
        }
    }

    func seedDefaultsIfNeeded() {
        do {
            let existing = try database.fetchActiveSupplements()
            guard existing.isEmpty else { return }

            guard let url = Bundle.main.url(forResource: "default_supplements", withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return }

            struct DefaultSupplement: Codable {
                let name: String
                let dosage: String
                let unit: String
                let sortOrder: Int
            }

            let defaults = try JSONDecoder().decode([DefaultSupplement].self, from: data)
            for d in defaults {
                var supplement = Supplement(
                    name: d.name,
                    dosage: d.dosage,
                    unit: d.unit,
                    sortOrder: d.sortOrder
                )
                try database.saveSupplement(&supplement)
            }
            loadSupplements()
        } catch {
            print("Failed to seed supplements: \(error)")
        }
    }

    func toggleTaken(supplementId: Int64) {
        do {
            try database.toggleSupplementTaken(supplementId: supplementId, date: dateString)
            loadSupplements()
        } catch {
            print("Failed to toggle: \(error)")
        }
    }

    func addCustomSupplement(name: String, dosage: String, unit: String) {
        do {
            var supplement = Supplement(
                name: name,
                dosage: dosage,
                unit: unit,
                sortOrder: supplements.count
            )
            try database.saveSupplement(&supplement)
            loadSupplements()
        } catch {
            print("Failed to add supplement: \(error)")
        }
    }

    func isTaken(_ supplementId: Int64) -> Bool {
        todayLogs[supplementId]?.taken ?? false
    }
}
