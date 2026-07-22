import Foundation

/// Pure helpers for cleaning up exercise names and dates coming off a scanned
/// workout page. The Nebius vision model is instructed to canonicalise names
/// itself, but this is the deterministic safety net: it expands the gym
/// shorthand `ExerciseDatabase.match` refuses to (`match` won't treat "db" as
/// "dumbbell" because a 2-char token can't prefix-cover an 8-char word), so a
/// name that slips through still grounds against the catalog in the review UI.
public enum ExerciseNameNormalizer {

    /// Whole-word abbreviation → expansion, applied token-wise (case-insensitive).
    /// Longest/most-specific compound forms handled before single tokens.
    private static let tokenExpansions: [String: String] = [
        "db": "Dumbbell",
        "dbs": "Dumbbell",
        "bb": "Barbell",
        "kb": "Kettlebell",
        "ohp": "Overhead Press",
        "rdl": "Romanian Deadlift",
        "sldl": "Stiff Leg Deadlift",
        "bor": "Bent Over Row",
        "ez": "EZ",         // "EZ bar curl" already spells "bar"; don't duplicate it
        "bw": "",          // bodyweight marker — drop, weight handled separately
        "ss": "",          // superset marker — drop
        "amrap": "",       // rep-scheme marker — belongs in reps, not the name
    ]

    /// Canonicalise a raw exercise name: trim, expand shorthand tokens, collapse
    /// whitespace, and Title Case. Returns "" for empty / marker-only input so
    /// the caller drops it. Deterministic and I/O-free (Tier-0 testable).
    public static func canonical(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Split on whitespace, keep intra-word punctuation (e.g. "pull-up").
        let tokens = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        var out: [String] = []
        for token in tokens {
            let key = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,()/"))
            if let expansion = tokenExpansions[key] {
                if !expansion.isEmpty { out.append(expansion) }
                // empty expansion → marker token, skip entirely
            } else {
                out.append(token)
            }
        }
        let joined = out.joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return titleCased(joined)
    }

    /// Title-case each word but preserve already-uppercase acronyms (EZ, T-Bar).
    private static func titleCased(_ s: String) -> String {
        s.split(separator: " ").map { word -> String in
            let str = String(word)
            if str.count <= 3 && str == str.uppercased() { return str }  // keep EZ, T
            guard let first = str.first else { return str }
            return String(first).uppercased() + str.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    /// Parse a model-emitted date string (ideally "YYYY-MM-DD", but tolerate
    /// "M/D", "M/D/YY", "M/D/YYYY") into a `Date`. A year-less date resolves to
    /// its most recent past occurrence relative to `referenceDate` (a training
    /// log photographed today records a session that already happened). Returns
    /// nil for unparseable / future-in-a-weird-way input. Pure — `referenceDate`
    /// is injected so it's Tier-0 testable.
    public static func parseDate(_ raw: String, referenceDate: Date) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.lowercased() != "null" else { return nil }

        // Build dates in the SAME zone `DateFormatters.dateOnly` formats in
        // (local), or a midnight-UTC date would render as the previous day.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.autoupdatingCurrent

        // ISO "YYYY-MM-DD"
        if let iso = DateFormatters.dateOnly.date(from: s) { return iso }

        // Numeric "M/D", "M/D/YY", "M/D/YYYY" (also tolerate '-' or '.' separators).
        let parts = s.split(whereSeparator: { $0 == "/" || $0 == "-" || $0 == "." }).map(String.init)
        guard parts.count >= 2,
              let month = Int(parts[0]), (1...12).contains(month),
              let day = Int(parts[1]), (1...31).contains(day) else { return nil }

        let refYear = cal.component(.year, from: referenceDate)
        if parts.count >= 3, let y = Int(parts[2]) {
            let year = y < 100 ? 2000 + y : y
            return cal.date(from: DateComponents(year: year, month: month, day: day))
        }

        // No year: try this year; if that's in the future, roll back one year.
        var comps = DateComponents(year: refYear, month: month, day: day)
        guard let thisYear = cal.date(from: comps) else { return nil }
        if thisYear > referenceDate {
            comps.year = refYear - 1
            return cal.date(from: comps)
        }
        return thisYear
    }
}
