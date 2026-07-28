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
                // #986: a duration exercise can still be weighted (weighted carry / plank) — keep the weight.
                let weight = (ex.weightLbs ?? 0) > 0 ? ex.weightLbs : nil
                rows.append(WorkoutSet(workoutId: workoutId, exerciseName: name, setOrder: 1,
                                       weightLbs: weight, reps: nil, isWarmup: false,
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

    // MARK: - Exercise library grounding (scan / import)

    /// Ground a free-text exercise name against the catalog: the catalog's
    /// spelling when it confidently matches ("pushups" → the library entry),
    /// else the trimmed original. Keeps scanned rows exact-lookup-able for
    /// tracking type / poses instead of minting near-duplicate customs.
    public static func groundedExerciseName(_ raw: String) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return ExerciseDatabase.match(name: name)?.name ?? name
    }

    /// Names absent from `known` (a lowercased name set) — trimmed, deduped
    /// case-insensitively, input order preserved. Pure; `known` injected so the
    /// filter is Tier-0 testable without touching the custom-exercise store.
    public static func unknownExerciseNames(_ names: [String], known: Set<String>) -> [String] {
        var seen = Set<String>()
        return names.compactMap { raw in
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = name.lowercased()
            guard !name.isEmpty, !known.contains(key), seen.insert(key).inserted else { return nil }
            return name
        }
    }

    /// Register every name the catalog doesn't know as a custom exercise with a
    /// guessed body part, so scanned/imported movements land in the library
    /// (browse, tracking type, anatomy) instead of existing only as history
    /// rows. Mirrors what Strong/Hevy CSV import always did. Returns the newly
    /// registered names (empty when everything was already known).
    @discardableResult
    public static func autoRegisterUnknownExercises(_ names: [String]) -> [String] {
        let known = Set(ExerciseDatabase.allWithCustom.map { $0.name.lowercased() })
        let unknown = unknownExerciseNames(names, known: known)
        ExerciseDatabase.addCustomExercises(unknown.map {
            ExerciseDatabase.CustomExerciseSpec(name: $0, bodyPart: ExerciseDatabase.guessBodyPart($0))
        })
        return unknown
    }

    // MARK: - Scanned workout (photo / PDF → session)

    /// Expand a scanned session's exercises into `WorkoutSet` rows, preserving
    /// PER-SET detail (a photographed "45×10 / 60×15 / 70×8" becomes three rows
    /// at ascending weight, not three identical sets — that's the whole point of
    /// reading the notebook faithfully). Duration exercises with no per-set data
    /// produce one duration row. Pure — no DB access — so the mapping is Tier-0
    /// testable; blank-named exercises are skipped but still consume their order.
    public static func buildScannedSessionSets(workoutId: Int64, exercises: [ScannedSessionExercise]) -> [WorkoutSet] {
        var rows: [WorkoutSet] = []
        for (exIndex, ex) in exercises.enumerated() {
            let name = ex.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if ex.isDuration && ex.sets.isEmpty {
                let mins = ex.durationMinutes ?? 0
                let secs: Int? = mins > 0 ? mins * 60 : nil
                rows.append(WorkoutSet(workoutId: workoutId, exerciseName: name, setOrder: 1,
                                       weightLbs: nil, reps: nil, isWarmup: false,
                                       durationSec: secs, exerciseOrder: exIndex))
            } else {
                for (i, set) in ex.sets.enumerated() {
                    let weight = (set.weightLbs ?? 0) > 0 ? set.weightLbs : nil
                    rows.append(WorkoutSet(workoutId: workoutId, exerciseName: name, setOrder: i + 1,
                                           weightLbs: weight, reps: set.reps, isWarmup: set.isWarmup,
                                           durationSec: nil, exerciseOrder: exIndex))
                }
            }
        }
        return rows
    }

    /// Persist a scanned session: ground each exercise name against the catalog
    /// (so rows exact-resolve for tracking type / poses), create the `Workout`
    /// row (past-dating honoured — the notebook records days that already
    /// happened), expand to per-set rows, save, and auto-register any truly
    /// novel names as custom exercises so they land in the library. Returns nil
    /// when nothing loggable. Mirrors `saveVoiceLoggedWorkout` but keeps
    /// per-set weights.
    @discardableResult
    public static func saveScannedSession(name: String, date: Date = Date(),
                                          exercises: [ScannedSessionExercise]) throws -> Workout? {
        let grounded = exercises.map { ex -> ScannedSessionExercise in
            var e = ex
            e.name = groundedExerciseName(ex.name)
            return e
        }
        let hasLoggable = grounded.contains { !$0.name.isEmpty }
        guard hasLoggable else { return nil }

        var workout = Workout(name: name,
                              date: DateFormatters.dateOnly.string(from: date),
                              durationSeconds: nil, notes: nil,
                              createdAt: ISO8601DateFormatter().string(from: date))
        try saveWorkout(&workout)
        guard let wid = workout.id else { return workout }
        let sets = buildScannedSessionSets(workoutId: wid, exercises: grounded)
        guard !sets.isEmpty else { return workout }
        try saveSets(sets)
        autoRegisterUnknownExercises(grounded.map(\.name))
        return workout
    }

    // MARK: - Usual-workout replay ("log my usual push day")

    /// Most-recent workout whose name contains `query` (case-insensitive).
    /// Empty query = the most recent workout, full stop. Pure — Tier-0 tested.
    public static func mostRecentWorkout(matching query: String, in workouts: [Workout]) -> Workout? {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return workouts.first { q.isEmpty || $0.name.lowercased().contains(q) }
    }

    /// Clone a session's sets onto a new workout id: weights/reps/duration/
    /// warmup/order carry over (that's the "usual"); RPE does NOT — felt
    /// effort is per-day and cloning it would fabricate data. Pure.
    public static func clonedSets(from source: [WorkoutSet], to workoutId: Int64) -> [WorkoutSet] {
        source.map { s in
            WorkoutSet(workoutId: workoutId, exerciseName: s.exerciseName,
                       setOrder: s.setOrder, weightLbs: s.weightLbs, reps: s.reps,
                       isWarmup: s.isWarmup, durationSec: s.durationSec,
                       exerciseOrder: s.exerciseOrder)
        }
    }

    /// "Log my usual push day": replay the most recent matching workout
    /// set-for-set as a completed workout on `date`. Returns nil when nothing
    /// matches or the source has no sets — the caller narrates the miss.
    @discardableResult
    public static func replayMostRecentWorkout(matching query: String, on date: Date = Date())
        throws -> (workout: Workout, sets: [WorkoutSet])? {
        let workouts = try fetchWorkouts(limit: 90)
        guard let source = mostRecentWorkout(matching: query, in: workouts),
              let sourceId = source.id else { return nil }
        let sourceSets = try fetchSets(forWorkout: sourceId)
        guard !sourceSets.isEmpty else { return nil }

        var workout = Workout(name: source.name,
                              date: DateFormatters.dateOnly.string(from: date),
                              durationSeconds: nil, notes: nil,
                              createdAt: ISO8601DateFormatter().string(from: date))
        try saveWorkout(&workout)
        guard let wid = workout.id else { return nil }
        let cloned = clonedSets(from: sourceSets, to: wid)
        try saveSets(cloned)
        return (workout, cloned)
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

    /// Batched last weights: ONE query for every visible exercise instead of one
    /// per row. The exercise picker issued 50-60 serial round-trips per keystroke,
    /// each crossing JNI on Android (#1074) — same shape as the `buildSummaries`
    /// fix below. Per name the result is identical to `lastWeight(for:)`: the
    /// newest non-warmup set, and a nil `weightLbs` on that set yields no entry
    /// rather than falling through to an older one.
    public static func lastWeights(for exerciseNames: [String]) throws -> [String: Double] {
        guard !exerciseNames.isEmpty else { return [:] }
        let rows = try db.reader.read { dbConn in
            try WorkoutSet
                .filter(exerciseNames.contains(Column("exercise_name")))
                .filter(Column("is_warmup") == false)
                .order(Column("id").desc)
                .fetchAll(dbConn)
        }
        var weights: [String: Double] = [:]
        var seen = Set<String>()
        seen.reserveCapacity(exerciseNames.count)
        for row in rows where seen.insert(row.exerciseName).inserted {
            if let weight = row.weightLbs { weights[row.exerciseName] = weight }
        }
        return weights
    }

    // MARK: - Legacy custom-exercise cleanup (#1107)

    /// Every exercise name with at least one logged set, lowercased — the
    /// safety guard `pruneLegacyUtteranceCustomExercisesOnce` uses so a
    /// custom exercise referenced by history is never orphaned.
    public static func loggedExerciseNames() throws -> Set<String> {
        try db.reader.read { dbConn in
            let names = try String.fetchSet(dbConn, sql: "SELECT DISTINCT exercise_name FROM workout_set")
            return Set(names.map { $0.lowercased() })
        }
    }

    /// Run-once launch cleanup: deletes legacy raw-utterance custom
    /// exercises (the pre-#1079 Android parser bug that saved names like
    /// "3x10 bench press at 135" into "Your Exercises"). Gated so it runs
    /// exactly once per device/install.
    public static func pruneLegacyUtteranceCustomExercisesOnce() {
        guard !DriftPlatform.keyValueStore.bool(forKey: "drift_pruned_utterance_customs_v1") else { return }
        let logged = (try? loggedExerciseNames()) ?? []
        let removed = ExerciseDatabase.pruneLegacyUtteranceCustoms(loggedExerciseNames: logged)
        DriftPlatform.keyValueStore.set(true, forKey: "drift_pruned_utterance_customs_v1")
        if !removed.isEmpty {
            Log.app.info("Pruned \(removed.count) legacy utterance custom exercises")
        }
    }

    /// Build workout summary for display.
    public static func buildSummary(for workout: Workout) throws -> WorkoutSummary {
        guard let wid = workout.id else {
            return WorkoutSummary(workout: workout, exercises: [], totalSets: 0, totalVolume: 0, prs: 0, bestSets: [])
        }
        let sets = try fetchSets(forWorkout: wid)
        return summarize(workout, sets: sets)
    }

    /// Batched summaries: ONE query for all workouts' sets instead of one
    /// per workout — `fetchWorkouts(500).map(buildSummary)` was 500 serial
    /// queries on the tab-switch frame (perf field report 2026-07-09).
    public static func buildSummaries(for workouts: [Workout]) throws -> [WorkoutSummary] {
        let ids = workouts.compactMap(\.id)
        guard !ids.isEmpty else { return workouts.map { summarize($0, sets: []) } }
        let all = try db.reader.read { dbConn in
            try WorkoutSet
                .filter(ids.contains(Column("workout_id")))
                .order(Column("exercise_order").asc, Column("set_order").asc, Column("id").asc)
                .fetchAll(dbConn)
        }
        let byWorkout = Dictionary(grouping: all, by: \.workoutId)
        return workouts.map { summarize($0, sets: $0.id.flatMap { byWorkout[$0] } ?? []) }
    }

    /// Pure summary construction from already-fetched sets (must be in
    /// exercise_order/set_order — see #939 ordering note below).
    private static func summarize(_ workout: Workout, sets: [WorkoutSet]) -> WorkoutSummary {
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
    public static func shareText(for summary: WorkoutSummary, sets: [WorkoutSet], unit: WeightUnit) -> String {
        var t = "\u{1F4AA} \(summary.workout.name)\n\u{1F4C5} \(summary.workout.date)\n"
        if !summary.workout.durationDisplay.isEmpty { t += "\u{23F1} \(summary.workout.durationDisplay)  " }
        t += "\u{1F3CB} \(Int(unit.convertFromLbs(summary.totalVolume))) \(unit.displayName)\n"
        if let notes = summary.workout.notes, !notes.isEmpty { t += "\u{1F4DD} \(notes)\n" }
        t += "\n"
        let grouped = Dictionary(grouping: sets) { $0.exerciseName }
        for ex in summary.exercises {
            guard let exSets = grouped[ex] else { continue }
            t += "\(ex)\n"
            for s in exSets {
                let prefix = s.isWarmup ? "  W\(s.setOrder). " : "  \(s.setOrder). "
                t += "\(prefix)\(s.display(in: unit))\n"
            }
            t += "\n"
        }
        t += "Logged with Drift"
        return t
    }

    /// Share text for a just-saved workout — reads the PERSISTED rows, so the
    /// completion sheet shares exactly what History will show (never a stale
    /// or empty in-memory snapshot, #938).
    public static func shareText(forWorkoutId id: Int64, unit: WeightUnit) throws -> String {
        guard let workout = try db.reader.read({ try Workout.fetchOne($0, id: id) }) else {
            throw DatabaseError(message: "workout \(id) not found")
        }
        let summary = try buildSummary(for: workout)
        let sets = try fetchSets(forWorkout: id)
        return shareText(for: summary, sets: sets, unit: unit)
    }

    /// Unique exercise names from all workouts.
    public static func allExerciseNames() throws -> [String] {
        try db.reader.read { dbConn in
            try String.fetchAll(dbConn, sql: "SELECT DISTINCT exercise_name FROM workout_set ORDER BY exercise_name")
        }
    }

    /// Start of the calendar week (respecting `firstWeekday`) containing `date`,
    /// normalized to midnight.
    ///
    /// Deliberately avoids `Calendar.dateInterval(of: .weekOfYear, for:)`: on
    /// Android (Skip's Foundation) that returns a different bucket than it does
    /// for `Date()` on the same day, so workouts logged TODAY landed in an older
    /// week and every "this week" counter read 0 while the 12-week total was
    /// right (#1076, reproduced on build 21). Day arithmetic off `startOfDay`
    /// behaves identically on both platforms.
    static func startOfWeek(for date: Date, calendar cal: Calendar = .current) -> Date {
        let day = cal.startOfDay(for: date)
        let offset = (cal.component(.weekday, from: day) - cal.firstWeekday + 7) % 7
        return cal.date(byAdding: .day, value: -offset, to: day) ?? day
    }

    /// Workouts per week for last N weeks, ordered **oldest → newest** (so the
    /// current week is `.last`; see `WorkoutWeeklyCountsTests`).
    public static func weeklyWorkoutCounts(weeks: Int = 12) throws -> [(weekStart: Date, count: Int)] {
        let workouts = try fetchWorkouts(limit: 500)
        let cal = Calendar.current
        let currentWeekStart = startOfWeek(for: Date(), calendar: cal)

        // Bucket by whole weeks BACK from the current week, keyed by that integer
        // rather than by `Date`: dictionary lookup on Date needs exact instant
        // equality, which is what made the old bucketing silently miss.
        var counts: [Int: Int] = [:]
        for w in workouts {
            guard let date = DateFormatters.dateOnly.date(from: String(w.date.prefix(10))) else { continue }
            let weekStart = startOfWeek(for: date, calendar: cal)
            guard let days = cal.dateComponents([.day], from: weekStart, to: currentWeekStart).day else { continue }
            let offset = days / 7
            guard offset >= 0, offset < weeks else { continue }
            counts[offset, default: 0] += 1
        }

        return (0..<weeks).compactMap { offset -> (weekStart: Date, count: Int)? in
            guard let weekStart = cal.date(byAdding: .day, value: -offset * 7, to: currentWeekStart) else { return nil }
            return (weekStart, counts[offset] ?? 0)
        }.reversed()
    }

    /// Calculate workout streak: consecutive weeks with at least 1 workout.
    public static func workoutStreak() throws -> (current: Int, longest: Int) {
        let counts = try weeklyWorkoutCounts(weeks: 52)
        return streak(fromWeeklyCounts: counts.map(\.count))
    }

    /// Pure streak over chronological (oldest→newest) weekly workout counts. The CURRENT
    /// streak is the leading run of active weeks from the newest, and a break locks it.
    /// #985: the old code overwrote `current` with a trailing (older) run, reporting a
    /// non-zero streak after a recent break.
    static func streak(fromWeeklyCounts counts: [Int]) -> (current: Int, longest: Int) {
        var current = 0
        var longest = 0
        var run = 0
        var currentLocked = false
        for count in counts.reversed() {  // newest first
            if count > 0 {
                run += 1
                longest = max(longest, run)
                if !currentLocked { current = run }
            } else {
                run = 0
                currentLocked = true
            }
        }
        return (current, longest)
    }

    // MARK: - Exercise Favorites

    private static let exerciseFavoritesKey = "drift_exercise_favorites"

    public static var exerciseFavorites: Set<String> {
        Set(DriftPlatform.keyValueStore.stringArray(forKey: exerciseFavoritesKey) ?? [])
    }

    public static func toggleExerciseFavorite(_ name: String) {
        var favs = exerciseFavorites
        if favs.contains(name) { favs.remove(name) } else { favs.insert(name) }
        DriftPlatform.keyValueStore.set(Array(favs), forKey: exerciseFavoritesKey)
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
    /// Wall-clock time of the most recent `clearSession()`. `saveSession`
    /// refuses to write a session that STARTED before this stamp — once a
    /// workout is finished or discarded, no late async persist may resurrect
    /// it. Field bug 2026-07-13: the 30s auto-save tick raced the Finish
    /// button, re-wrote the just-cleared session, and the zombie produced
    /// both a phantom "Workout in progress" banner and a duplicate saved
    /// workout ("P5 Day 1" saved at 1h39m and again at 2h22m).
    private static let sessionClearedAtKey = "drift_active_workout_session_cleared_at"
    /// Clock-skew grace on the tombstone comparison. A zombie session
    /// started hours before the clear; a legitimate new session starts
    /// after it. 2 minutes absorbs NTP adjustments without re-admitting
    /// any realistic zombie.
    private static let sessionClearGraceSeconds: TimeInterval = 120

    public struct SavedSession: Codable {
        public let workoutName: String
        public let startTime: Date
        public let exercises: [SessionExercise]
        /// Stamped by saveSession on every persist. Optional so payloads
        /// written by older builds still decode (they fall back to startTime).
        public var lastSavedAt: Date?

        public init(workoutName: String, startTime: Date, exercises: [SessionExercise], lastSavedAt: Date? = nil) {
            self.workoutName = workoutName
            self.startTime = startTime
            self.exercises = exercises
            self.lastSavedAt = lastSavedAt
        }

        /// Seconds actually TRAINED: start → last persist. Resume rebases the
        /// live timer on this so hours away don't count as workout time
        /// (field report 2026-07-16: resumed session started at the full
        /// wall-clock gap). Pre-lastSavedAt payloads fall back to wall clock.
        public func trainedSeconds(asOf now: Date = Date()) -> TimeInterval {
            guard let lastSavedAt else { return max(0, now.timeIntervalSince(startTime)) }
            return max(0, lastSavedAt.timeIntervalSince(startTime))
        }

        public struct SessionExercise: Codable {
            public let name: String
            public let isWarmup: Bool
            public let notes: String?
            public let restTime: Int
            public let sets: [SessionSet]
            /// Per-exercise reps↔timer override (nil = classify by name).
            /// Optional so payloads from older builds still decode.
            public var trackByTime: Bool?
            /// Weight-entry unit option: typed numbers are kg when true
            /// (nil/false = lbs, the field's historical meaning).
            public var weighInKg: Bool?

            public init(name: String, isWarmup: Bool, notes: String?, restTime: Int, sets: [SessionSet], trackByTime: Bool? = nil, weighInKg: Bool? = nil) {
                self.name = name
                self.isWarmup = isWarmup
                self.notes = notes
                self.restTime = restTime
                self.sets = sets
                self.trackByTime = trackByTime
                self.weighInKg = weighInKg
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
        let clearedAt = DriftPlatform.keyValueStore.double(forKey: sessionClearedAtKey)
        guard session.startTime.timeIntervalSince1970 >= clearedAt - sessionClearGraceSeconds else {
            Log.app.info("Rejected stale session write for '\(session.workoutName)' — started before the last clearSession()")
            return
        }
        var stamped = session
        stamped.lastSavedAt = Date()
        if let data = try? JSONEncoder().encode(stamped),
           let json = String(data: data, encoding: .utf8) {
            DriftPlatform.keyValueStore.set(json, forKey: sessionKey)   // String → SharedPreferences putString; Data is dropped by the Skip bridge (#1102)
        }
    }

    /// Sessions idle for 5+ hours are treated as abandoned — but NEVER
    /// silently discarded (field report 2026-07-09: operator lost a full
    /// logged workout by leaving the phone without tapping Finish). Any
    /// entered sets are auto-saved as a completed workout dated to the day
    /// it actually happened; only a session with nothing logged is dropped.
    public static func loadSession(now: Date = Date()) -> SavedSession? {
        let raw = DriftPlatform.keyValueStore.string(forKey: sessionKey)?.data(using: .utf8)
                ?? DriftPlatform.keyValueStore.data(forKey: sessionKey)   // migrate pre-#1102 Data payloads
        guard let raw, let session = try? JSONDecoder().decode(SavedSession.self, from: raw) else { return nil }
        let lastActivity = session.lastSavedAt ?? session.startTime
        if now.timeIntervalSince(lastActivity) > 5 * 3600 {
            finalizeAbandonedSession(session, into: db)
            clearSession()
            return nil
        }
        return session
    }

    /// Convert an abandoned session's entered sets into a real workout.
    /// Mirrors ActiveWorkoutView.saveWorkout: completed (done) sets win;
    /// if none were ticked done, any set with data still counts — losing
    /// typed-in work is worse than saving an unticked set.
    /// Internal + db-injected for tests.
    static func finalizeAbandonedSession(_ session: SavedSession, into db: AppDatabase) {
        func buildSets(for wid: Int64, requireDone: Bool) -> [WorkoutSet] {
            var sets: [WorkoutSet] = []
            for (ei, ex) in session.exercises.enumerated() {
                let isDuration = ex.trackByTime ?? WorkoutSet.isDurationExercise(ex.name)
                // Same converter the live sheet reads its fields with, so the
                // two paths cannot drift apart again (#1084).
                let unit: WeightUnit = (ex.weighInKg ?? false) ? .kg : .lbs
                for (si, s) in ex.sets.enumerated() where s.done || !requireDone {
                    let w = unit.entryTextToLbs(s.weight) ?? 0
                    let r = Int(s.reps) ?? 0
                    let dur = isDuration ? (Int(s.reps) ?? 0) : nil
                    guard r > 0 || (isDuration && (dur ?? 0) > 0) else { continue }
                    sets.append(WorkoutSet(workoutId: wid, exerciseName: ex.name, setOrder: si + 1,
                                           weightLbs: w > 0 ? w : nil, reps: isDuration ? nil : r,
                                           isWarmup: s.isWarmup || ex.isWarmup,
                                           durationSec: dur, exerciseOrder: ei))
                }
            }
            return sets
        }
        // Probe with a placeholder id — only touch the DB if there is data.
        let hasData = !buildSets(for: 0, requireDone: true).isEmpty || !buildSets(for: 0, requireDone: false).isEmpty
        guard hasData else { return }
        do {
            let lastActivity = session.lastSavedAt ?? session.startTime
            let duration = max(60, Int(lastActivity.timeIntervalSince(session.startTime)))
            var workout = Workout(name: session.workoutName,
                                  date: DateFormatters.dateOnly.string(from: session.startTime),
                                  durationSeconds: duration,
                                  notes: "Auto-saved — workout was left unfinished",
                                  createdAt: ISO8601DateFormatter().string(from: session.startTime))
            var m = workout
            try db.writer.write { dbConn in
                try m.save(dbConn)
                if m.id == nil { m.id = dbConn.lastInsertedRowID }
            }
            workout = m
            guard let wid = workout.id else { return }
            var sets = buildSets(for: wid, requireDone: true)
            if sets.isEmpty { sets = buildSets(for: wid, requireDone: false) }
            try db.writer.write { dbConn in
                for var s in sets { try s.insert(dbConn) }
            }
            Log.app.info("Auto-saved abandoned workout session '\(session.workoutName)' with \(sets.count) sets")
        } catch {
            Log.app.error("Auto-save abandoned session failed: \(error.localizedDescription)")
        }
    }

    /// `now` is injectable for tests that need to persist deliberately
    /// backdated sessions after a clear (expiry tests).
    public static func clearSession(now: Date = Date()) {
        DriftPlatform.keyValueStore.removeObject(forKey: sessionKey)
        DriftPlatform.keyValueStore.set(now.timeIntervalSince1970, forKey: sessionClearedAtKey)
    }

    public static var hasActiveSession: Bool {
        loadSession() != nil
    }

    /// Merge Drift-logged workouts with watch/Health events into display lines,
    /// newest first, capped at 6. Watch STRENGTH sessions on a day with a
    /// Drift-logged workout are skipped — same session recorded twice.
    /// Pure so Tier-0 can pin the merge (field bug 2026-07-14: the chat tool
    /// listed only HealthKit, hiding the user's own logged workouts).
    public static func mergedRecentWorkoutLines(
        drift: [Workout],
        health: [(date: Date, type: String, duration: TimeInterval, calories: Double)]
    ) -> [String] {
        var entries: [(date: Date, line: String)] = []
        var driftDates = Set<String>()
        for w in drift {
            guard let d = DateFormatters.dateOnly.date(from: w.date) else { continue }
            driftDates.insert(w.date)
            let dur = w.durationSeconds.map { " — \(Int($0) / 60) min" } ?? ""
            entries.append((d, "  \(DateFormatters.shortDisplay.string(from: d)): \(w.name)\(dur)"))
        }
        for w in health.prefix(5) {
            let t = w.type.lowercased()
            let strengthy = t.contains("strength") || t.contains("traditional")
                || t.contains("functional") || t == "workout"
            if strengthy && driftDates.contains(DateFormatters.dateOnly.string(from: w.date)) { continue }
            entries.append((w.date, "  \(DateFormatters.shortDisplay.string(from: w.date)): \(w.type) — \(Int(w.duration / 60)) min, \(Int(w.calories)) cal"))
        }
        return entries.sorted { $0.date > $1.date }.prefix(6).map(\.line)
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
        #if canImport(Darwin)
        guard url.startAccessingSecurityScopedResource() else { throw ImportError.fileAccessDenied }
        defer { url.stopAccessingSecurityScopedResource() }
        #endif

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
        // (same helper the workout-scan save path uses).
        autoRegisterUnknownExercises(Array(exerciseNames))

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
