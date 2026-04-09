import Foundation
import GRDB

/// Workout data operations and Strong CSV import.
enum WorkoutService {
    private static let db = AppDatabase.shared

    // MARK: - CRUD

    static func saveWorkout(_ workout: inout Workout) throws {
        try db.writer.write { [workout] dbConn in
            var m = workout
            try m.save(dbConn)
        }
        // Read back to get the assigned ID
        workout = try db.reader.read { dbConn in
            try Workout.order(Column("id").desc).fetchOne(dbConn)
        } ?? workout
    }

    static func saveSets(_ sets: [WorkoutSet]) throws {
        try db.writer.write { dbConn in
            for var s in sets { try s.insert(dbConn) }
        }
    }

    static func fetchWorkouts(limit: Int = 100) throws -> [Workout] {
        try db.reader.read { dbConn in
            try Workout.order(Column("date").desc).limit(limit).fetchAll(dbConn)
        }
    }

    static func fetchSets(forWorkout workoutId: Int64) throws -> [WorkoutSet] {
        try db.reader.read { dbConn in
            try WorkoutSet.filter(Column("workout_id") == workoutId)
                .order(Column("exercise_order"), Column("set_order"))
                .fetchAll(dbConn)
        }
    }

    static func deleteWorkout(id: Int64) throws {
        try db.writer.write { dbConn in
            _ = try Workout.deleteOne(dbConn, id: id)
        }
    }

    static func totalWorkoutCount() throws -> Int {
        try db.reader.read { dbConn in
            try Workout.fetchCount(dbConn)
        }
    }

    static func fetchTemplates() throws -> [WorkoutTemplate] {
        try db.reader.read { dbConn in
            try WorkoutTemplate.order(Column("is_favorite").desc, Column("created_at").desc).fetchAll(dbConn)
        }
    }

    static func toggleFavorite(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: "UPDATE workout_template SET is_favorite = NOT is_favorite WHERE id = ?", arguments: [id])
        }
    }

    static func saveTemplate(_ template: inout WorkoutTemplate) throws {
        try db.writer.write { [template] dbConn in
            var m = template
            try m.save(dbConn)
        }
    }

    // MARK: - History & PRs

    /// Get all sets for an exercise, most recent first.
    static func fetchExerciseHistory(name: String) throws -> [WorkoutSet] {
        try db.reader.read { dbConn in
            try WorkoutSet.filter(Column("exercise_name") == name)
                .order(Column("id").desc)
                .fetchAll(dbConn)
        }
    }

    /// Personal record (heaviest 1RM estimate) for an exercise.
    static func fetchPR(for exerciseName: String) throws -> Double? {
        let sets = try fetchExerciseHistory(name: exerciseName)
        return sets.compactMap(\.estimated1RM).max()
    }

    /// Last weight used for an exercise.
    static func lastWeight(for exerciseName: String) throws -> Double? {
        try db.reader.read { dbConn in
            try WorkoutSet.filter(Column("exercise_name") == exerciseName)
                .filter(Column("is_warmup") == false)
                .order(Column("id").desc)
                .fetchOne(dbConn)?.weightLbs
        }
    }

    /// Build workout summary for display.
    static func buildSummary(for workout: Workout) throws -> WorkoutSummary {
        guard let wid = workout.id else {
            return WorkoutSummary(workout: workout, exercises: [], totalSets: 0, totalVolume: 0, prs: 0, bestSets: [])
        }
        let sets = try fetchSets(forWorkout: wid)
        let exercises = Array(Set(sets.map(\.exerciseName)))

        let workingSets = sets.filter { !$0.isWarmup }
        let totalVolume = workingSets.reduce(0.0) { $0 + ($1.weightLbs ?? 0) * Double($1.reps ?? 0) }

        // Best set per exercise (highest estimated 1RM)
        var bestSets: [(String, Double, Int)] = []
        for ex in exercises {
            let exSets = workingSets.filter { $0.exerciseName == ex }
            if let best = exSets.max(by: { ($0.estimated1RM ?? 0) < ($1.estimated1RM ?? 0) }),
               let w = best.weightLbs, let r = best.reps {
                bestSets.append((ex, w, r))
            }
        }

        return WorkoutSummary(workout: workout, exercises: exercises, totalSets: workingSets.count,
                              totalVolume: totalVolume, prs: 0, bestSets: bestSets)
    }

    /// Unique exercise names from all workouts.
    static func allExerciseNames() throws -> [String] {
        try db.reader.read { dbConn in
            try String.fetchAll(dbConn, sql: "SELECT DISTINCT exercise_name FROM workout_set ORDER BY exercise_name")
        }
    }

    /// Workouts per week for last N weeks.
    static func weeklyWorkoutCounts(weeks: Int = 12) throws -> [(weekStart: Date, count: Int)] {
        let workouts = try fetchWorkouts(limit: 500)
        let cal = Calendar.current
        let now = Date()
        var counts: [Date: Int] = [:]

        for w in workouts {
            guard let date = DateFormatters.dateOnly.date(from: String(w.date.prefix(10))) else { continue }
            let weekStart = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            counts[weekStart, default: 0] += 1
        }

        guard let currentWeekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        return (0..<weeks).compactMap { offset -> (weekStart: Date, count: Int)? in
            guard let weekStart = cal.date(byAdding: .weekOfYear, value: -offset, to: currentWeekStart) else { return nil }
            return (weekStart, counts[weekStart] ?? 0)
        }.reversed()
    }

    /// Calculate workout streak: consecutive weeks with at least 1 workout.
    static func workoutStreak() throws -> (current: Int, longest: Int) {
        let counts = try weeklyWorkoutCounts(weeks: 52)
        var current = 0
        var longest = 0
        var streak = 0

        // Count from most recent week backwards
        for week in counts.reversed() {
            if week.count > 0 {
                streak += 1
                longest = max(longest, streak)
            } else {
                if current == 0 { current = streak } // First break = current streak
                streak = 0
            }
        }
        if current == 0 { current = streak } // Still going
        longest = max(longest, streak)
        return (current, longest)
    }

    // MARK: - Exercise Favorites

    private static let exerciseFavoritesKey = "drift_exercise_favorites"

    static var exerciseFavorites: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: exerciseFavoritesKey) ?? [])
    }

    static func toggleExerciseFavorite(_ name: String) {
        var favs = exerciseFavorites
        if favs.contains(name) { favs.remove(name) } else { favs.insert(name) }
        UserDefaults.standard.set(Array(favs), forKey: exerciseFavoritesKey)
    }

    /// Most recently used exercises (by last workout date), limited to N.
    static func recentExerciseNames(limit: Int = 15) throws -> [String] {
        try db.reader.read { dbConn in
            try String.fetchAll(dbConn, sql: """
                SELECT exercise_name FROM workout_set
                JOIN workout ON workout.id = workout_set.workout_id
                GROUP BY exercise_name
                ORDER BY MAX(workout.date) DESC
                LIMIT ?
                """, arguments: [limit])
        }
    }

    // MARK: - Active Session Persistence

    private static let sessionKey = "drift_active_workout_session"

    struct SavedSession: Codable {
        let workoutName: String
        let startTime: Date
        let exercises: [SessionExercise]

        struct SessionExercise: Codable {
            let name: String
            let isWarmup: Bool
            let notes: String?
            let restTime: Int
            let sets: [SessionSet]
        }

        struct SessionSet: Codable {
            let weight: String
            let reps: String
            let done: Bool
            let isWarmup: Bool
        }
    }

    static func saveSession(_ session: SavedSession) {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }

    static func loadSession() -> SavedSession? {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(SavedSession.self, from: data) else { return nil }
        // Expire after 5 hours
        if Date().timeIntervalSince(session.startTime) > 5 * 3600 {
            clearSession()
            return nil
        }
        return session
    }

    static func clearSession() {
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    static var hasActiveSession: Bool {
        loadSession() != nil
    }

    // MARK: - Strong CSV Import

    struct ImportResult: Sendable {
        let workouts: Int
        let sets: Int
        let exercises: Int
    }

    enum ImportError: LocalizedError {
        case fileAccessDenied
        var errorDescription: String? { "Could not access the selected file. Try re-selecting it." }
    }

    /// Import from Strong or Hevy CSV (auto-detected by column names).
    static func importStrongCSV(url: URL) throws -> ImportResult {
        guard url.startAccessingSecurityScopedResource() else { throw ImportError.fileAccessDenied }
        defer { url.stopAccessingSecurityScopedResource() }

        let content = try String(contentsOf: url, encoding: .utf8)
        let isHevy = content.lowercased().contains("exercise_title") || content.lowercased().contains("set_type")
        let result = CSVParser.parse(content: content)

        // Key by full timestamp — rows from the same workout share exact timestamp
        struct WorkoutKey: Hashable { let timestamp: String; let name: String }
        var workoutsByKey: [WorkoutKey: (name: String, duration: String, notes: String)] = [:]
        var setsByKey: [WorkoutKey: [WorkoutSet]] = [:]
        var exerciseNames = Set<String>()

        for row in result.rows {
            // Auto-detect column names: Strong vs Hevy
            let dateStr: String?
            let exerciseName: String?
            let workoutName: String
            let duration: String
            let notes: String

            if isHevy {
                dateStr = row["start_time"]
                exerciseName = row["exercise_title"]
                workoutName = row["title"] ?? "Workout"
                duration = "" // Hevy has start_time + end_time, duration computed elsewhere
                notes = row["description"] ?? ""
            } else {
                dateStr = row["Date"]
                exerciseName = row["Exercise Name"]
                workoutName = row["Workout Name"] ?? "Workout"
                duration = row["Duration"] ?? row["Workout Duration"] ?? ""
                notes = row["Workout Notes"] ?? ""
            }

            guard let ds = dateStr, let en = exerciseName else { continue }
            let date = String(ds.prefix(10))
            let wKey = WorkoutKey(timestamp: ds, name: workoutName)

            workoutsByKey[wKey] = (workoutName, duration, notes)
            exerciseNames.insert(en)

            let setOrder = Int(row[isHevy ? "set_index" : "Set Order"] ?? "1") ?? 1
            var weight: Double
            let reps = Int(Double(row[isHevy ? "reps" : "Reps"] ?? "0") ?? 0)
            let rpe = Double(row[isHevy ? "rpe" : "RPE"] ?? "")

            if isHevy {
                // Hevy exports weight in lbs (column: weight_lbs)
                weight = Double(row["weight_lbs"] ?? "0") ?? 0
                // Fallback: try weight_kg if weight_lbs missing (older exports?)
                if weight == 0, let kg = Double(row["weight_kg"] ?? ""), kg > 0 {
                    weight = kg * 2.20462
                }
            } else {
                // Strong exports weight with a unit column
                weight = Double(row["Weight"] ?? "0") ?? 0
                let weightUnit = row["Weight Unit"] ?? "lbs"
                if weightUnit.lowercased() == "kg" { weight *= 2.20462 }
            }

            let isWarmup = isHevy && (row["set_type"] ?? "").lowercased() == "warmup"
            let set = WorkoutSet(workoutId: 0, exerciseName: en, setOrder: setOrder,
                                 weightLbs: weight, reps: reps, isWarmup: isWarmup, rpe: rpe,
                                 exerciseOrder: 0)
            setsByKey[wKey, default: []].append(set)
        }

        // Save workouts and sets
        var workoutCount = 0
        for (wKey, info) in workoutsByKey.sorted(by: { $0.key.timestamp < $1.key.timestamp }) {
            let date = String(wKey.timestamp.prefix(10))
            // Parse duration
            var durationSec: Int? = nil
            let durStr = info.duration.lowercased()
            if durStr.contains("h") || durStr.contains("m") {
                let parts = durStr.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
                if durStr.contains("h") {
                    let hours = Int(parts.first ?? "0") ?? 0
                    let minutes = parts.count >= 2 ? (Int(parts[1]) ?? 0) : 0
                    durationSec = hours * 3600 + minutes * 60
                } else if let m = Int(parts.first ?? "") {
                    durationSec = m * 60
                }
            }

            var workout = Workout(name: info.name, date: date, durationSeconds: durationSec,
                                  notes: info.notes.isEmpty ? nil : info.notes,
                                  createdAt: ISO8601DateFormatter().string(from: Date()))
            try saveWorkout(&workout)

            if let wid = workout.id, let sets = setsByKey[wKey] {
                let updatedSets = sets.map { var s = $0; s.workoutId = wid; return s }
                try saveSets(updatedSets)
            }
            workoutCount += 1
        }

        // Auto-add missing exercises to custom DB with smart body part guessing
        let dbNames = Set(ExerciseDatabase.allWithCustom.map { $0.name.lowercased() })
        for name in exerciseNames {
            if !dbNames.contains(name.lowercased()) {
                let bodyPart = ExerciseDatabase.guessBodyPart(name)
                ExerciseDatabase.addCustomExercise(name: name, bodyPart: bodyPart)
            }
        }

        // Smart template extraction: group by session, find frequently co-occurring exercises
        let nameKey = isHevy ? "title" : "Workout Name"
        let exerciseKey = isHevy ? "exercise_title" : "Exercise Name"
        let dateKey = isHevy ? "start_time" : "Date"

        // Build per-session exercise lists: workoutName → [[exercises in session1], [exercises in session2], ...]
        var sessionsByName: [String: [[String]]] = [:]
        var currentSession: [String: (date: String, exercises: [String])] = [:]

        // Use struct key instead of string concatenation (avoids pipe-in-name bug)
        struct SessionKey: Hashable { let name: String; let date: String }
        var sessionMap: [SessionKey: [String]] = [:]

        for row in result.rows {
            guard let name = row[nameKey], let exercise = row[exerciseKey],
                  let dateStr = row[dateKey].map({ String($0.prefix(10)) }) else { continue }
            let key = SessionKey(name: name, date: dateStr)
            if sessionMap[key] == nil { sessionMap[key] = [] }
            if !(sessionMap[key]?.contains(exercise) ?? false) {
                sessionMap[key]?.append(exercise)
            }
        }
        for (key, exercises) in sessionMap {
            sessionsByName[key.name, default: []].append(exercises)
        }

        // For each workout name: find exercises appearing in ≥50% of sessions
        var templatesCreated = 0
        let existingTemplates = Set((try? fetchTemplates())?.map(\.name) ?? [])
        let sortedNames = sessionsByName.sorted { $0.value.count > $1.value.count }.map(\.key)

        // Find typical max exercises per session across all workouts
        let allSessionSizes = sessionsByName.values.flatMap { $0 }.map(\.count)
        let typicalMax = allSessionSizes.sorted().dropLast(allSessionSizes.count / 10).last ?? 8 // 90th percentile

        for name in sortedNames where templatesCreated < 5 {
            let sessions = sessionsByName[name] ?? []
            guard sessions.count >= 2, !existingTemplates.contains(name) else { continue }

            // Count how often each exercise appears across sessions
            var exerciseFreq: [String: Int] = [:]
            var exerciseOrder: [String: Double] = [:] // average position
            for session in sessions {
                for (i, ex) in session.enumerated() {
                    exerciseFreq[ex, default: 0] += 1
                    exerciseOrder[ex, default: 0] += Double(i)
                }
            }

            // Keep exercises appearing in ≥50% of sessions, sorted by avg position
            let threshold = max(2, (sessions.count + 1) / 2) // proper ≥50% rounding up
            let frequent = exerciseFreq.filter { $0.value >= threshold }
                .sorted { (exerciseOrder[$0.key] ?? 0) / Double($0.value) < (exerciseOrder[$1.key] ?? 0) / Double($1.value) }
                .map(\.key)

            // Cap at typical session size
            let capped = Array(frequent.prefix(min(typicalMax, 10)))
            guard capped.count >= 2 else { continue }

            let templateExercises = capped.map {
                WorkoutTemplate.TemplateExercise(name: $0, sets: 3, restSeconds: 90)
            }
            if let json = try? JSONEncoder().encode(templateExercises),
               let jsonStr = String(data: json, encoding: .utf8) {
                var t = WorkoutTemplate(name: name, exercisesJson: jsonStr,
                                        createdAt: ISO8601DateFormatter().string(from: Date()))
                try? saveTemplate(&t)
                templatesCreated += 1
            }
        }

        Log.app.info("Imported \(workoutCount) workouts, \(result.rows.count) sets, \(exerciseNames.count) exercises, \(templatesCreated) templates")

        return ImportResult(workouts: workoutCount, sets: result.rows.count, exercises: exerciseNames.count)
    }
}
