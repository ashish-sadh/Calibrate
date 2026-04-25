import Foundation
import DriftCore

/// Unified supplement service — used by both UI views and AI tool calls.
@MainActor
enum SupplementService {

    /// Get today's supplement status: taken/total + remaining names.
    static func getStatus() -> String {
        let today = DateFormatters.todayString
        guard let supplements = try? AppDatabase.shared.fetchActiveSupplements(),
              !supplements.isEmpty else { return "No supplements set up." }
        let logs = (try? AppDatabase.shared.fetchSupplementLogs(for: today)) ?? []
        let takenIds = Set(logs.filter(\.taken).compactMap(\.supplementId))
        let taken = takenIds.count
        let total = supplements.count

        if taken == total { return "All \(total) supplements taken today." }
        let untaken = supplements.filter { !takenIds.contains($0.id ?? 0) }.map(\.name)
        return "Supplements: \(taken)/\(total) taken. Still need: \(untaken.joined(separator: ", "))."
    }

    /// Mark a supplement as taken by name.
    static func markTaken(name: String) -> String {
        let today = DateFormatters.todayString
        guard let supplements = try? AppDatabase.shared.fetchActiveSupplements() else {
            return "No supplements found."
        }
        let lower = name.lowercased()
        guard let match = supplements.first(where: { $0.name.lowercased().contains(lower) }),
              let id = match.id else {
            return "Couldn't find a supplement matching '\(name)'."
        }
        try? AppDatabase.shared.toggleSupplementTaken(supplementId: id, date: today)
        return "Marked \(match.name) as taken."
    }

    /// Delete a supplement by ID.
    static func deleteSupplement(id: Int64) {
        try? AppDatabase.shared.writer.write { db in
            try Supplement.deleteOne(db, id: id)
        }
    }

    /// Update a supplement's properties.
    static func updateSupplement(id: Int64, name: String, dosage: String?, unit: String?, dailyDoses: Int) {
        try? AppDatabase.shared.writer.write { db in
            try db.execute(sql: """
                UPDATE supplement SET name = ?, dosage = ?, unit = ?, daily_doses = ? WHERE id = ?
                """, arguments: [name, dosage, unit, dailyDoses, id])
        }
    }

    /// Add a new supplement to the stack.
    static func addSupplement(name: String, dosage: String? = nil) -> String {
        guard let supplements = try? AppDatabase.shared.fetchActiveSupplements() else {
            return "Couldn't access supplements."
        }
        // Check if already exists
        if supplements.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            return "\(name) is already in your stack."
        }
        var supp = Supplement(name: name.capitalized, dosage: dosage, unit: nil,
                               isActive: true, sortOrder: supplements.count, dailyDoses: 1)
        try? AppDatabase.shared.saveSupplement(&supp)
        return "Added \(name.capitalized)\(dosage.map { " (\($0))" } ?? "") to your supplement stack."
    }
}
