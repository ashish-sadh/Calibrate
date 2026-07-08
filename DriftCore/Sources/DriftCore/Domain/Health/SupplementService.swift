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
    ///
    /// If nothing in the stack matches — including a fresh user with an EMPTY stack —
    /// we recognize common supplement names (KnownSupplements) and auto-add + mark
    /// them, rather than dead-ending with "No supplements found." (#904)
    public static func markTaken(name: String) -> String {
        let today = DateFormatters.todayString
        let supplements = (try? AppDatabase.shared.fetchActiveSupplements()) ?? []
        let matched = matchingSupplements(query: name, among: supplements)
        var marked: [String] = []
        for supp in matched {
            guard let id = supp.id else { continue }
            // Idempotent set (not toggle): re-affirming "I took my vitamin D"
            // must keep it taken, never flip it back off.
            try? AppDatabase.shared.setSupplementTaken(supplementId: id, date: today, taken: true)
            marked.append(supp.name)
        }
        if !marked.isEmpty {
            return "Marked \(joined(marked)) as taken."
        }

        // Nothing in the existing stack matched — the stack is empty (a fresh user)
        // or the user named a real supplement they haven't added yet. Recognize
        // common names, auto-add, and mark taken so we never dead-end someone
        // naming a real supplement (#904).
        let (added, alreadyHad) = addAndMarkRecognized(in: name, existing: supplements, date: today)
        if !added.isEmpty {
            return "Added \(joined(added)) to your stack and marked \(added.count == 1 ? "it" : "them") taken."
        }
        if !alreadyHad.isEmpty {
            return "Marked \(joined(alreadyHad)) as taken."
        }
        return supplements.isEmpty
            ? "No supplements found. Try 'add <name>' to start your stack."
            : "Couldn't find a supplement matching '\(name)'."
    }

    /// Recognize common supplement names in `phrase`; add any not already in the
    /// stack and mark every recognized one taken for `date`. Returns the canonical
    /// names newly `added` vs those `alreadyHad` (an alias gap the stack matcher
    /// missed) so the caller can phrase an honest confirmation. (#904)
    private static func addAndMarkRecognized(
        in phrase: String, existing: [Supplement], date: String
    ) -> (added: [String], alreadyHad: [String]) {
        var added: [String] = []
        var alreadyHad: [String] = []
        for canonical in KnownSupplements.recognize(in: phrase) {
            // #987: match an existing supplement fuzzily (canonical "Vitamin D" marks a
            // stored "Vitamin D3") instead of exact-equality, which inserted a duplicate.
            let inStackMatch = existing.first(where: { $0.name.lowercased() == canonical.lowercased() })
                ?? matchingSupplements(query: canonical, among: existing).first
            if let inStack = inStackMatch {
                guard let id = inStack.id else { continue }
                try? AppDatabase.shared.setSupplementTaken(supplementId: id, date: date, taken: true)
                alreadyHad.append(inStack.name)
            } else {
                var supp = Supplement(name: canonical, isActive: true,
                                      sortOrder: existing.count + added.count, dailyDoses: 1)
                try? AppDatabase.shared.saveSupplement(&supp)
                guard let id = supp.id else { continue }
                try? AppDatabase.shared.setSupplementTaken(supplementId: id, date: date, taken: true)
                added.append(canonical)
            }
        }
        return (added, alreadyHad)
    }

    /// "a", "a and b", "a, b and c" — natural-language list join.
    private static func joined(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names.last!
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
            if paddedQuery.contains(" \(n) ") || (q.count >= 3 && n.contains(q)) { return true }
            // #987: also match the base name when the stored name carries a trailing
            // variant digit — "i took my vitamin d" (a full sentence) → stored "Vitamin D3".
            let nBase = n.replacingOccurrences(of: #"\s*\d+$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            return nBase.count >= 3 && nBase != n && paddedQuery.contains(" \(nBase) ")
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
