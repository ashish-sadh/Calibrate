import Foundation
import DriftCore
import GRDB

/// Workout data operations and Strong CSV import.
public enum WorkoutService {
    private static let db = AppDatabase.shared

    // MARK: - CRUD

    public static func saveWorkout(_ workout: inout Workout) throws {
        // Capture the assigned id from WITHIN the write transaction. The old code read
        // back `Workout.order(id desc).fetchOne` — the highest id in the whole table —
        // which returns the WRONG row whenever another workout is inserted concurrently
        // (parallel tests, or a background save racing a foreground one). That mis-assigned
        // id also corrupted every subsequent saveSets/buildSummary/shareText for the workout.
        var m = workout
        try db.writer.write { dbConn in
            try m.save(dbConn)
            if m.id == nil { m.id = dbConn.lastInsertedRowID }
        }
        workout = m
    }

    public static func updateSet(id: Int64, weightLbs: Double?, reps: Int?, durationSec: Int? = nil) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE workout_set SET weight_lbs = ?, reps = ?, duration_sec = ? WHERE id = ?",
                arguments: [weightLbs, reps, durationSec, id])
        }
    }

    public static func deleteSet(id: Int64) throws {
        try db.writer.write { dbConn in
            _ = try WorkoutSet.deleteOne(dbConn, id: id)
        }
    }

    public static func updateWorkout(id: Int64, name: String, notes: String?) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE workout SET name = ?, notes = ? WHERE id = ?",
                arguments: [name, notes, id])
        }
    }

    public static func saveSets(_ sets: [WorkoutSet]) throws {
        try db.writer.write { dbConn in
            for var s in sets { try s.insert(dbConn) }
        }
    }

    // MARK: - Voice/text-logged workout → set rows (#868)

    /// One exercise as confirmed in `ExerciseVoiceLogSheet` (after any user
    /// edits), ready to be expanded into `WorkoutSet` rows. Mirrors the numeric
    /// shape of `FMExerciseEntry` but carries the post-edit values from the
    /// confirmation card. `isDuration` is true for cardio/mobility/sports.
    public struct VoiceLoggedExercise: Sendable, Equatable {
        public let name: String
        public let isDuration: Bool
        public let sets: Int?
        public let reps: Int?
        public let weightLbs: Double?
        public let durationMinutes: Int?

        public init(name: String, isDuration: Bool, sets: Int? = nil, reps: Int? = nil,
                    weightLbs: Double? = nil, durationMinutes: Int? = nil) {
            self.name = name
            self.isDuration = isDuration
            self.sets = sets
            self.reps = reps
            self.weightLbs = weightLbs
            self.durationMinutes = durationMinutes
        }
    }

    /// Expand confirmed voice/text-logged exercises into `WorkoutSet` rows for a
    /// saved workout. Strength entries produce one row per set (defaulting to a
    /// single set when count is missing) carrying reps + weight; duration entries
    /// produce one row carrying `durationSec` (minutes × 60). Pure — no DB access
    /// — so the `ExerciseVoiceLogSheet` save mapping is Tier-0 testable.
    /// `exerciseOrder` preserves the order the user spoke/typed; entries with a
    /// blank name are skipped (but their original index is still consumed, so the
    /// surviving rows keep the spoken order).
    public static func buildVoiceLogSets(workoutId: Int64, exercises: [VoiceLoggedExercise]) -> [WorkoutSet] {
        var rows: [WorkoutSet] = []
        for (index, ex) in exercises.enumerated() {
            let name = ex.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if ex.isDuration {
                let mins = ex.durationMinutes ?? 0
                let secs: Int? = mins > 0 ? mins * 60 : nil
                rows.append(WorkoutSet(workoutId: workoutId, exerciseName: name, setOrder: 1,
                                       weightLbs: nil, reps: nil, isWarmup: false,
                                       durationSec: secs, exerciseOrder: index))
            } else {
                let count = max(1, ex.sets ?? 1)
                let weight = (ex.weightLbs ?? 0) > 0 ? ex.weightLbs : nil
                for setOrder in 1...count {
                    rows.append(WorkoutSet(workoutId: workoutId, exerciseName: name, setOrder: setOrder,
                                           weightLbs: weight, reps: ex.reps, isWarmup: false,
                                           durationSec: nil, exerciseOrder: index))
                }
            }
        }
        return rows
    }

    /// Persist a voice/text-logged workout: create the `Workout` row, expand the
    /// confirmed exercises into set rows via `buildVoiceLogSets`, and save them.
    /// Returns the saved workout (id assigned), or nil when no exercise carries a
    /// non-blank name (nothing to log). Mirrors the create-workout-then-save-sets
    /// pattern `importStrongCSV` uses. `date` defaults to now.
    @discardableResult
    public static func saveVoiceLoggedWorkout(name: String, date: Date = Date(),
                                              exercises: [VoiceLoggedExercise]) throws -> Workout? {
        let hasLoggable = exercises.contains { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard hasLoggable else { return nil }

        var workout = Workout(name: name,
                              date: DateFormatters.dateOnly.string(from: date),
                              durationSeconds: nil, notes: nil,
                              createdAt: ISO8601DateFormatter().string(from: date))
        try saveWorkout(&workout)
        guard let wid = workout.id else { return workout }
        try saveSets(buildVoiceLogSets(workoutId: wid, exercises: exercises))
        return workout
    }

    public static func fetchWorkouts(limit: Int = 100) throws -> [Workout] {
        try db.reader.read { dbConn in
            try Workout.order(Column("date").desc).limit(limit).fetchAll(dbConn)
        }
    }

    public static func fetchSets(forWorkout workoutId: Int64) throws -> [WorkoutSet] {
        try db.reader.read { dbConn in
            try WorkoutSet.filter(Column("workout_id") == workoutId)
                .order(Column("exercise_order"), Column("set_order"))
                .fetchAll(dbConn)
        }
    }

    public static func deleteWorkout(id: Int64) throws {
        try db.writer.write { dbConn in
            _ = try Workout.deleteOne(dbConn, id: id)
        }
    }

    public static func totalWorkoutCount() throws -> Int {
        try db.reader.read { dbConn in
            try Workout.fetchCount(dbConn)
        }
    }

    public static func fetchTemplates() throws -> [WorkoutTemplate] {
        try db.reader.read { dbConn in
            try WorkoutTemplate.order(Column("is_favorite").desc, Column("created_at").desc).fetchAll(dbConn)
        }
    }

    public static func toggleFavorite(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: "UPDATE workout_template SET is_favorite = NOT is_favorite WHERE id = ?", arguments: [id])
        }
    }

    public static func saveTemplate(_ template: inout WorkoutTemplate) throws {
        try db.writer.write { [template] dbConn in
            var m = template
            try m.save(dbConn)
        }
    }

    public static func renameTemplate(id: Int64, name: String) {
        try? db.writer.write { dbConn in
            try dbConn.execute(sql: "UPDATE workout_template SET name = ? WHERE id = ?",
                               arguments: [name, id])
        }
    }

    public static func updateTemplate(id: Int64, name: String, exercisesJson: String) {
        try? db.writer.write { dbConn in
            try dbConn.execute(sql: "UPDATE workout_template SET name = ?, exercises_json = ? WHERE id = ?",
                               arguments: [name, exercisesJson, id])
        }
    }

    public static func deleteTemplate(id: Int64) {
        try? db.writer.write { dbConn in
            _ = try WorkoutTemplate.deleteOne(dbConn, id: id)
        }
    }

    // MARK: - History & PRs

    /// Get all sets for an exercise, most recent first.
    public static func fetchExerciseHistory(name: String) throws -> [WorkoutSet] {
        try db.reader.read { dbConn in
            try WorkoutSet.filter(Column("exercise_name") == name)
                .order(Column("id").desc)
                .fetchAll(dbConn)
        }
    }

    /// Personal record (heaviest 1RM estimate) for an exercise.
    public static func fetchPR(for exerciseName: String) throws -> Double? {
        let sets = try fetchExerciseHistory(name: exerciseName)
        return sets.compactMap(\.estimated1RM).max()
    }

    /// Last weight used for an exercise.
    public static func lastWeight(for exerciseName: String) throws -> Double? {
        try db.reader.read { dbConn in
            try WorkoutSet.filter(Column("exercise_name") == exerciseName)
                .filter(Column("is_warmup") == false)
                .order(Column("id").desc)
                .fetchOne(dbConn)?.weightLbs
        }
    }

    /// Build workout summary for display.
    public static func buildSummary(for workout: Workout) throws -> WorkoutSummary {
        guard let wid = workout.id else {
            return WorkoutSummary(workout: workout, exercises: [], totalSets: 0, totalVolume: 0, prs: 0, bestSets: [])
        }
        let sets = try fetchSets(forWorkout: wid)
        // #939: preserve performed order. fetchSets returns sets ordered by
        // exercise_order/set_order; the old Array(Set(...)) hashed that away,
        // so detail + share rendered a random order every read. Ordered
        // dedup by first appearance, warmup exercises grouped first.
        var seenNames = Set<String>()
        var warmupNames: [String] = []
        var workingNames: [String] = []
        for s in sets where seenNames.insert(s.exerciseName).inserted {
            if s.isWarmup {
                warmupNames.append(s.exerciseName)
            } else {
                workingNames.append(s.exerciseName)
            }
        }
        let exercises = warmupNames + workingNames

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

    // MARK: - Share text (#938: ONE builder for completion sheet + History)

    /// Render the share summary from a summary + its sets. Pure — both share
    /// surfaces call this, so they can never diverge; #939's ordered
    /// `summary.exercises` drives the exercise sequence (warmups first,
    /// performed order).
    public static func shareText(for summary: WorkoutSummary, sets: [WorkoutSet]) -> String {
        var t = "\u{1F4AA} \(summary.workout.name)\n\u{1F4C5} \(summary.workout.date)\n"
        if !summary.workout.durationDisplay.isEmpty { t += "\u{23F1} \(summary.workout.durationDisplay)  " }
        t += "\u{1F3CB} \(Int(summary.totalVolume)) lbs\n"
        if let notes = summary.workout.notes, !notes.isEmpty { t += "\u{1F4DD} \(notes)\n" }
        t += "\n"
        let grouped = Dictionary(grouping: sets) { $0.exerciseName }
        for ex in summary.exercises {
            guard let exSets = grouped[ex] else { continue }
            t += "\(ex)\n"
            for s in exSets {
                let prefix = s.isWarmup ? "  W\(s.setOrder). " : "  \(s.setOrder). "
                t += "\(prefix)\(s.display)\n"
            }
            t += "\n"
        }
        t += "Logged with Drift"
        return t
    }

    /// Share text for a just-saved workout — reads the PERSISTED rows, so the
    /// completion sheet shares exactly what History will show (never a stale
    /// or empty in-memory snapshot, #938).
    public static func shareText(forWorkoutId id: Int64) throws -> String {
        guard let workout = try db.reader.read({ try Workout.fetchOne($0, id: id) }) else {
            throw DatabaseError(message: "workout \(id) not found")
        }
        let summary = try buildSummary(for: workout)
        let sets = try fetchSets(forWorkout: id)
        return shareText(for: summary, sets: sets)
    }

    /// Unique exercise names from all workouts.
    public static func allExerciseNames() throws -> [String] {
        try db.reader.read { dbConn in
            try String.fetchAll(dbConn, sql: "SELECT DISTINCT exercise_name FROM workout_set ORDER BY exercise_name")
        }
    }

    /// Workouts per week for last N weeks.
    public static func weeklyWorkoutCounts(weeks: Int = 12) throws -> [(weekStart: Date, count: Int)] {
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
    public static func workoutStreak() throws -> (current: Int, longest: Int) {
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

    public static var exerciseFavorites: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: exerciseFavoritesKey) ?? [])
    }

    public static func toggleExerciseFavorite(_ name: String) {
        var favs = exerciseFavorites
        if favs.contains(name) { favs.remove(name) } else { favs.insert(name) }
        UserDefaults.standard.set(Array(favs), forKey: exerciseFavoritesKey)
    }

    /// Most recently used exercises (by last workout date), limited to N.
    public static func recentExerciseNames(limit: Int = 15) throws -> [String] {
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

    public struct SavedSession: Codable {
        public let workoutName: String
        public let startTime: Date
        public let exercises: [SessionExercise]

        public init(workoutName: String, startTime: Date, exercises: [SessionExercise]) {
            self.workoutName = workoutName
            self.startTime = startTime
            self.exercises = exercises
        }

        public struct SessionExercise: Codable {
            public let name: String
            public let isWarmup: Bool
            public let notes: String?
            public let restTime: Int
            public let sets: [SessionSet]

            public init(name: String, isWarmup: Bool, notes: String?, restTime: Int, sets: [SessionSet]) {
                self.name = name
                self.isWarmup = isWarmup
                self.notes = notes
                self.restTime = restTime
                self.sets = sets
            }
        }

        public struct SessionSet: Codable {
            public let weight: String
            public let reps: String
            public let done: Bool
            public let isWarmup: Bool

            public init(weight: String, reps: String, done: Bool, isWarmup: Bool) {
                self.weight = weight
                self.reps = reps
                self.done = done
                self.isWarmup = isWarmup
            }
        }
    }

    public static func saveSession(_ session: SavedSession) {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }

    public static func loadSession() -> SavedSession? {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(SavedSession.self, from: data) else { return nil }
        // Expire after 5 hours
        if Date().timeIntervalSince(session.startTime) > 5 * 3600 {
            clearSession()
            return nil
        }
        return session
    }

    public static func clearSession() {
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    public static var hasActiveSession: Bool {
        loadSession() != nil
    }

    // MARK: - Strong CSV Import

    public struct ImportResult: Sendable {
        public let workouts: Int
        public let sets: Int
        public let exercises: Int
    }

    enum ImportError: LocalizedError {
        case fileAccessDenied
        var errorDescription: String? { "Could not access the selected file. Try re-selecting it." }
    }

    /// Import from Strong or Hevy CSV (auto-detected by column names).
    public static func importStrongCSV(url: URL) throws -> ImportResult {
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
