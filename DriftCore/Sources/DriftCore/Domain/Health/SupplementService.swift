import Foundation
import DriftCore

/// Unified supplement service — used by both UI views and AI tool calls.
@MainActor
public enum SupplementService {

    /// Get today's supplement status: taken/total + remaining names.
    public static func getStatus() -> String {
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

    /// Mark a supplement (or supplements) as taken from a natural-language phrase.
    /// Robust to full sentences and filler: "I took my vitamin D and omega 3 this
    /// morning" marks BOTH. The agent often passes the whole utterance as `name`,
    /// so we extract the supplement names here rather than trusting upstream parsing.
    public static func markTaken(name: String) -> String {
        let today = DateFormatters.todayString
        guard let supplements = try? AppDatabase.shared.fetchActiveSupplements(),
              !supplements.isEmpty else {
            return "No supplements found."
        }
        let matched = matchingSupplements(query: name, among: supplements)
        var marked: [String] = []
        for supp in matched {
            guard let id = supp.id else { continue }
            // Idempotent set (not toggle): re-affirming "I took my vitamin D"
            // must keep it taken, never flip it back off.
            try? AppDatabase.shared.setSupplementTaken(supplementId: id, date: today, taken: true)
            marked.append(supp.name)
        }
        guard !marked.isEmpty else {
            return "Couldn't find a supplement matching '\(name)'."
        }
        let summary = marked.count == 1
            ? marked[0]
            : marked.dropLast().joined(separator: ", ") + " and " + marked.last!
        return "Marked \(summary) as taken."
    }

    /// Every active supplement named anywhere in `query`. Handles full sentences
    /// ("I took my vitamin D and omega 3 this morning"), filler, multiple
    /// supplements in one phrase, short partial queries ("d3" → "Vitamin D3"), and
    /// punctuation/case differences ("Omega-3" == "omega 3").
    static func matchingSupplements(query: String, among supplements: [Supplement]) -> [Supplement] {
        let q = normalizedForMatch(query)
        guard !q.isEmpty else { return [] }
        let paddedQuery = " \(q) "
        return supplements.filter { supp in
            let n = normalizedForMatch(supp.name)
            guard n.count >= 2 else { return false }
            // Name appears as a whole word/phrase in the utterance, OR a short
            // clean query is a substring of the name ("vitamin d" → "Vitamin D3").
            return paddedQuery.contains(" \(n) ") || (q.count >= 3 && n.contains(q))
        }
    }

    /// Lowercase, map every non-alphanumeric character to a space, collapse runs
    /// of whitespace — so "Omega-3" and "omega 3" normalize identically.
    private static func normalizedForMatch(_ s: String) -> String {
        let spaced = s.lowercased().map { ($0.isLetter || $0.isNumber) ? $0 : " " }
        return String(spaced).split(separator: " ").joined(separator: " ")
    }

    /// Delete a supplement by ID.
    public static func deleteSupplement(id: Int64) {
        try? AppDatabase.shared.writer.write { db in
            try Supplement.deleteOne(db, id: id)
        }
    }

    /// Update a supplement's properties.
    public static func updateSupplement(id: Int64, name: String, dosage: String?, unit: String?, dailyDoses: Int) {
        try? AppDatabase.shared.writer.write { db in
            try db.execute(sql: """
                UPDATE supplement SET name = ?, dosage = ?, unit = ?, daily_doses = ? WHERE id = ?
                """, arguments: [name, dosage, unit, dailyDoses, id])
        }
    }

    /// Add a new supplement to the stack.
    public static func addSupplement(name: String, dosage: String? = nil) -> String {
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
