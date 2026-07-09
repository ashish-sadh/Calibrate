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
        /// Per-exercise time-vs-reps tracking. Absent in `exercises.json`
        /// (decodes to nil → treated as reps by `trackingType(for:)`); set
        /// explicitly on custom exercises so agility drills / holds carry it.
        public var trackingType: TrackingType? = nil
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

    /// Serializes the custom-exercise read-modify-write below. `addCustomExercise`
    /// reads the current list, appends, then writes it back — a non-atomic sequence.
    /// Production has several call sites (manual add, workout save, default
    /// templates) and Swift Testing runs tests in parallel, so without this lock
    /// concurrent callers interleave their read→write and silently lose updates
    /// (the cause of the flaky `searchFindsCustomExercises`). #905.
    private static let customLock = NSLock()

    static var customExercises: [ExerciseInfo] {
        guard let data = UserDefaults.standard.data(forKey: customKey),
              let decoded = try? JSONDecoder().decode([ExerciseInfo].self, from: data) else { return [] }
        return decoded
    }

    /// Register a custom exercise. `primaryMuscles` should be real catalog
    /// muscle slugs (they drive the anatomy diagram); `imageUrl` may point
    /// into free-exercise-db so the bundled pose crossfade resolves (#929).
    /// Both optional — plain user-created exercises pass just name+bodyPart.
    public static func addCustomExercise(name: String, bodyPart: String,
                                         primaryMuscles: [String]? = nil,
                                         imageUrl: String? = nil) {
        customLock.lock()
        defer { customLock.unlock() }
        var customs = customExercises
        if let idx = customs.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            // Upgrade-in-place: installs that registered this exercise before
            // the richer registry existed (#941) have it stored without
            // imageUrl/muscles — fill the missing visual fields, never
            // overwrite ones already set (user edits win).
            var existing = customs[idx]
            var changed = false
            if existing.imageUrl == nil, let imageUrl {
                existing.imageUrl = imageUrl
                changed = true
            }
            // Backfill trackingType for customs persisted before the field
            // existed (a nil-tracking "Ladder Drill" would otherwise resolve
            // to reps under catalog-authority). Only sets when the name
            // classifies as time — reps is the default anyway.
            if existing.trackingType == nil, classifyTrackingType(name) == .time {
                existing.trackingType = .time
                changed = true
            }
            if let primaryMuscles,
               existing.primaryMuscles == [existing.bodyPart.lowercased()] {
                existing = ExerciseInfo(name: existing.name, bodyPart: existing.bodyPart,
                                        primaryMuscles: primaryMuscles,
                                        secondaryMuscles: existing.secondaryMuscles,
                                        equipment: existing.equipment, category: existing.category,
                                        level: existing.level, imageUrl: existing.imageUrl,
                                        youtubeUrl: existing.youtubeUrl,
                                        instructions: existing.instructions,
                                        trackingType: existing.trackingType)
                changed = true
            }
            guard changed else { return }
            customs[idx] = existing
        } else {
            customs.append(ExerciseInfo(name: name, bodyPart: bodyPart,
                                        primaryMuscles: primaryMuscles ?? [bodyPart.lowercased()],
                                        secondaryMuscles: [], equipment: "other", category: "strength", level: "intermediate",
                                        imageUrl: imageUrl,
                                        trackingType: classifyTrackingType(name)))
        }
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

    // MARK: - Tracking Type (time-based vs reps-based)

    /// Exercises Drift explicitly tracks by *time*, declared per-exercise rather
    /// than guessed. Agility/footwork drills where a rep count is meaningless —
    /// you log how long you moved. Lowercased for exact-name matching. Planks,
    /// holds, and carries are covered by `timeBasedFamilies` below, not here.
    static let timeBasedExerciseNames: Set<String> = [
        "ladder drill", "ladder drills", "agility ladder", "agility drill",
        "speed ladder", "footwork drill",
    ]

    /// WHOLE-WORD time cues for names Drift doesn't declare explicitly (custom
    /// exercises the user types, unseen imports). The per-exercise
    /// `trackingType` attribute and `timeBasedExerciseNames` take precedence;
    /// this is only the fallback for un-cataloged names.
    ///
    /// 2026-07-09 rewrite: the old list did naive SUBSTRING matching, which
    /// mis-timed ~15 rep exercises — "walk" caught *Walking Lunge*, "hang"
    /// caught every *Hang Clean/Snatch* and *Hanging Leg Raise*, "sled" caught
    /// *Sled Row/Reverse Flye*, "plank" caught *Push Up to Side Plank*. Now:
    ///  • matching is whole-word (token-based), so "walk"≠"walking lunge" and
    ///    a bare "hang" (the hold) ≠ "hang clean" (the Olympic lift);
    ///  • ambiguous roots that are usually a POSITION not a hold ("hang",
    ///    "sled", "walk") are gone — a genuine timed carry/cardio is caught by
    ///    an explicit phrase below or its catalog `trackingType`.
    static let timeBasedWords: Set<String> = [
        "plank", "hold", "wall-sit", "l-sit", "isometric", "carry",
    ]
    /// Multi-word time phrases (checked as substrings — these are unambiguous).
    static let timeBasedPhrases: [String] = [
        "wall sit", "dead hang", "farmer's walk", "farmers walk",
        "battle rope", "rope climb", "bear crawl", "treadmill",
        "elliptical", "stationary bike", "jump rope", "jumping rope",
    ]

    /// The tracking type for an exercise name, resolved data-first:
    ///  1. An explicit per-exercise `trackingType` (catalog OR an upgraded
    ///     custom) always wins — e.g. "Plank" ⇒ time.
    ///  2. Otherwise, a BUNDLED-CATALOG rep exercise is authoritative reps,
    ///     even when its name contains a time word: "Push Up to Side Plank",
    ///     "Hang Clean", "Sled Row" stay reps (2026-07-09 — the core fix; the
    ///     old substring classifier mis-timed all of these).
    ///  3. Otherwise (user custom or unknown name) fall to the whole-word
    ///     classifier so "Side Plank", "Wall Sit", "Ladder Drill" are timed.
    ///     This also rescues stale customs persisted with a nil trackingType
    ///     before the field existed.
    public static func trackingType(for name: String) -> TrackingType {
        if let t = info(for: name)?.trackingType { return t }
        if bundledCatalogContains(name) { return .reps }
        return classifyTrackingType(name)
    }

    /// True when `name` is an exact (case-insensitive) entry in the bundled
    /// exercises.json — NOT counting user customs. Lets `trackingType(for:)`
    /// treat catalog reps as authoritative while still classifying customs.
    static func bundledCatalogContains(_ name: String) -> Bool {
        let q = name.lowercased()
        return all.contains { $0.name.lowercased() == q }
    }

    /// Pure name-based classification (no catalog lookup) — used when *creating*
    /// a custom exercise so its stored `trackingType` reflects the declared data.
    static func classifyTrackingType(_ name: String) -> TrackingType {
        let n = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if timeBasedExerciseNames.contains(n) { return .time }
        if timeBasedPhrases.contains(where: { n.contains($0) }) { return .time }
        // Whole-word match: tokenize on non-alphanumerics so "plank" hits
        // "side plank" but "hang" does NOT hit "hang clean" (a rep lift).
        let words = Set(n.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        if !words.isDisjoint(with: timeBasedWords) { return .time }
        return .reps
    }
}
