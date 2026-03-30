import Foundation
import GRDB

/// Workout data operations and Strong CSV import.
enum WorkoutService {
    private static let db = AppDatabase.shared

    // MARK: - CRUD

    static func saveWorkout(_ workout: inout Workout) throws {
        let savedWorkout = try db.writer.write { [workout] dbConn -> Workout in
            var m = workout
            try m.save(dbConn)
            return m
        }
        workout = savedWorkout
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
            try WorkoutSet.filter(Column("workout_id") == workoutId).order(Column("set_order")).fetchAll(dbConn)
        }
    }

    static func deleteWorkout(id: Int64) throws {
        try db.writer.write { dbConn in
            _ = try Workout.deleteOne(dbConn, id: id)
        }
    }

    static func fetchTemplates() throws -> [WorkoutTemplate] {
        try db.reader.read { dbConn in
            try WorkoutTemplate.fetchAll(dbConn)
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

    // MARK: - Strong CSV Import

    struct ImportResult: Sendable {
        let workouts: Int
        let sets: Int
        let exercises: Int
    }

    static func importStrongCSV(url: URL) throws -> ImportResult {
        guard url.startAccessingSecurityScopedResource() else { throw NSError(domain: "", code: -1) }
        defer { url.stopAccessingSecurityScopedResource() }

        let content = try String(contentsOf: url, encoding: .utf8)
        let result = CSVParser.parse(content: content)

        var workoutsByDate: [String: (name: String, duration: String, notes: String)] = [:]
        var setsByDate: [String: [WorkoutSet]] = [:]
        var exerciseNames = Set<String>()

        for row in result.rows {
            guard let dateStr = row["Date"], let exerciseName = row["Exercise Name"] else { continue }
            let date = String(dateStr.prefix(10))
            let workoutName = row["Workout Name"] ?? "Workout"
            let duration = row["Duration"] ?? ""
            let notes = row["Workout Notes"] ?? ""

            workoutsByDate[date] = (workoutName, duration, notes)
            exerciseNames.insert(exerciseName)

            let setOrder = Int(row["Set Order"] ?? "1") ?? 1
            let weight = Double(row["Weight"] ?? "0") ?? 0
            let reps = Int(Double(row["Reps"] ?? "0") ?? 0)

            let set = WorkoutSet(workoutId: 0, exerciseName: exerciseName, setOrder: setOrder,
                                 weightLbs: weight, reps: reps, isWarmup: false, rpe: nil)
            setsByDate[date, default: []].append(set)
        }

        // Save workouts and sets
        var workoutCount = 0
        for (date, info) in workoutsByDate.sorted(by: { $0.key < $1.key }) {
            // Parse duration
            var durationSec: Int? = nil
            let durStr = info.duration.lowercased()
            if durStr.contains("h") || durStr.contains("m") {
                let parts = durStr.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
                if durStr.contains("h") && parts.count >= 2 {
                    durationSec = (Int(parts[0]) ?? 0) * 3600 + (Int(parts[1]) ?? 0) * 60
                } else if let m = Int(parts.first ?? "") {
                    durationSec = m * 60
                }
            }

            var workout = Workout(name: info.name, date: date, durationSeconds: durationSec,
                                  notes: info.notes.isEmpty ? nil : info.notes,
                                  createdAt: ISO8601DateFormatter().string(from: Date()))
            try saveWorkout(&workout)

            if let wid = workout.id, let sets = setsByDate[date] {
                let updatedSets = sets.map { var s = $0; s.workoutId = wid; return s }
                try saveSets(updatedSets)
            }
            workoutCount += 1
        }

        Log.app.info("Imported \(workoutCount) workouts, \(result.rows.count) sets, \(exerciseNames.count) exercises from Strong CSV")

        return ImportResult(workouts: workoutCount, sets: result.rows.count, exercises: exerciseNames.count)
    }
}
