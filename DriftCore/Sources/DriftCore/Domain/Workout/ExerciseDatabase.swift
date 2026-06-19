import Foundation

/// 873 exercises from free-exercise-db with muscle groups and equipment.
public enum ExerciseDatabase {
    public struct ExerciseInfo: Codable, Sendable, Identifiable {
        public var id: String { name }
        public let name: String
        public let bodyPart: String
        public let primaryMuscles: [String]
        public let secondaryMuscles: [String]
        public let equipment: String
        public let category: String
        public let level: String
        public var imageUrl: String? = nil
        public var youtubeUrl: String? = nil
        public var instructions: [String]? = nil
    }

    nonisolated(unsafe) private static var _exercises: [ExerciseInfo]?

    public static var all: [ExerciseInfo] {
        if let cached = _exercises { return cached }
        guard let url = Bundle.module.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ExerciseInfo].self, from: data) else {
            return []
        }
        _exercises = decoded
        return decoded
    }

    public static func search(query: String) -> [ExerciseInfo] {
        let source = allWithCustom
        if query.isEmpty { return source }
        let queryLower = query.lowercased()
        let words = queryLower.split(separator: " ").map(String.init)
        return source.filter { ex in
            words.allSatisfy { word in
                ex.name.lowercased().contains(word) ||
                ex.bodyPart.lowercased().contains(word) ||
                ex.primaryMuscles.contains { $0.lowercased().contains(word) } ||
                ex.equipment.lowercased().contains(word)
            }
        }.sorted { a, b in
            let aLower = a.name.lowercased()
            let bLower = b.name.lowercased()
            let favs = WorkoutService.exerciseFavorites
            // 1. Favorites first
            let aFav = favs.contains(a.name)
            let bFav = favs.contains(b.name)
            if aFav != bFav { return aFav }
            // 2. Exact match
            let aExact = aLower == queryLower
            let bExact = bLower == queryLower
            if aExact != bExact { return aExact }
            // 3. Starts with query (e.g., "Chest Press" for "chest press")
            let aPrefix = aLower.hasPrefix(queryLower)
            let bPrefix = bLower.hasPrefix(queryLower)
            if aPrefix != bPrefix { return aPrefix }
            // 4. Name contains query as contiguous substring vs scattered words
            let aContiguous = aLower.contains(queryLower)
            let bContiguous = bLower.contains(queryLower)
            if aContiguous != bContiguous { return aContiguous }
            // 5. Shorter names = more specific
            if a.name.count != b.name.count { return a.name.count < b.name.count }
            // 6. Alphabetical
            return aLower < bLower
        }
    }

    /// Resolve a spoken/parsed exercise name to a canonical library entry.
    ///
    /// Unlike `search`, this matches on the *name only* (not muscle / equipment /
    /// bodyPart) and demands **full coverage** — every meaningful word the user
    /// said must appear in the candidate name. This is the grounding gate for
    /// voice logging: a confident utterance ("squats", "incline bench") maps to a
    /// real catalog entry, while a garbled or novel one ("chest ups") returns nil
    /// so the caller can flag it for the user instead of silently inventing an
    /// exercise. Plurals/short suffixes are handled by prefix matching
    /// (squat/squats, curl/curls, push/push-ups). Among fully-covering names the
    /// most specific (fewest extra words) wins.
    public static func match(name raw: String) -> ExerciseInfo? {
        let q = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return nil }
        let source = allWithCustom

        if let exact = source.first(where: { $0.name.lowercased() == q }) { return exact }

        let stop: Set<String> = ["the", "a", "and", "with", "of", "for", "to", "on", "my", "in"]
        func tokenize(_ s: String) -> [String] {
            s.lowercased()
                .split { !$0.isLetter }
                .map(String.init)
                .filter { $0.count >= 2 && !stop.contains($0) }
        }
        func tokensMatch(_ a: String, _ b: String) -> Bool {
            if a == b { return true }
            return min(a.count, b.count) >= 4 && (a.hasPrefix(b) || b.hasPrefix(a))
        }

        let qTokens = tokenize(q)
        guard !qTokens.isEmpty else { return nil }

        var best: ExerciseInfo?
        var bestPrecision = 0.0
        for ex in source {
            let nTokens = tokenize(ex.name)
            guard !nTokens.isEmpty else { continue }
            // Every spoken token must be covered by the candidate name.
            let covered = qTokens.allSatisfy { qt in nTokens.contains { tokensMatch(qt, $0) } }
            guard covered else { continue }
            // Prefer the most specific full-covering name (fewest extra words).
            let precision = Double(qTokens.count) / Double(nTokens.count)
            if precision > bestPrecision { bestPrecision = precision; best = ex }
        }
        return best
    }

    // MARK: - Custom Exercises (persisted in UserDefaults)

    private static let customKey = "drift_custom_exercises"

    static var customExercises: [ExerciseInfo] {
        guard let data = UserDefaults.standard.data(forKey: customKey),
              let decoded = try? JSONDecoder().decode([ExerciseInfo].self, from: data) else { return [] }
        return decoded
    }

    public static func addCustomExercise(name: String, bodyPart: String) {
        var customs = customExercises
        guard !customs.contains(where: { $0.name.lowercased() == name.lowercased() }) else { return }
        customs.append(ExerciseInfo(name: name, bodyPart: bodyPart, primaryMuscles: [bodyPart.lowercased()],
                                    secondaryMuscles: [], equipment: "other", category: "strength", level: "intermediate"))
        if let data = try? JSONEncoder().encode(customs) {
            UserDefaults.standard.set(data, forKey: customKey)
        }
        _exercises = nil // clear cache so `all` reloads
    }

    // Include custom exercises in all searches, deduplicating by name
    public static var allWithCustom: [ExerciseInfo] {
        let base = all
        let baseNames = Set(base.map { $0.name.lowercased() })
        let unique = customExercises.filter { !baseNames.contains($0.name.lowercased()) }
        return base + unique
    }

    public static func byBodyPart(_ part: String) -> [ExerciseInfo] {
        allWithCustom.filter { $0.bodyPart == part }
    }

    public static func info(for name: String) -> ExerciseInfo? {
        allWithCustom.first { $0.name.lowercased() == name.lowercased() }
    }

    public static func bodyPart(for name: String) -> String {
        info(for: name)?.bodyPart ?? guessBodyPart(name)
    }

    public static func guessBodyPart(_ name: String) -> String {
        let e = name.lowercased()
        // Check more specific patterns first to avoid false matches (e.g., "lateral" matching "lat")
        if e.contains("lateral raise") || e.contains("shoulder") || e.contains("overhead press") || e.contains("face pull") || e.contains("military") || e.contains("shrug") { return "Shoulders" }
        if e.contains("bench") || e.contains("chest") || e.contains("fly") || e.contains("dip") || e.contains("push-up") || e.contains("push up") { return "Chest" }
        if e.contains("squat") || e.contains("leg") || e.contains("calf") || e.contains("deadlift") || e.contains("lunge") || e.contains("hip") || e.contains("thrust") || e.contains("glute") { return "Legs" }
        if e.contains("lat ") || e.contains("lat\t") || e.contains("row") || e.contains("pull") || e.contains("back") || e.contains("pulldown") { return "Back" }
        if e.contains("bicep") || e.contains("curl") || e.contains("tricep") || e.contains("hammer") || e.contains("extension") { return "Arms" }
        if e.contains("crunch") || e.contains("plank") || e.contains("ab") || e.contains("leg raise") || e.contains("core") { return "Core" }
        return "Other"
    }
}
