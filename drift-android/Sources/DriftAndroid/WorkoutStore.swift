import Foundation
import Observation
import SkipFuse
import DriftCore

// MARK: - Sendable UI projections (DriftCore records stay off the UI layer)

struct WorkoutRow: Identifiable, Sendable {
    let id: Int64
    let name: String
    let date: String
    let exercises: String     // "Bench Press, Squat, …"
    let totalSets: Int
    let totalVolume: Int      // lbs
    let prs: Int
}

struct ExerciseRow: Identifiable, Sendable {
    let name: String
    let bodyPart: String
    let equipment: String
    var id: String { name }
}

struct WorkoutDetailRow: Identifiable, Sendable {
    let id: Int64
    let exerciseName: String
    let setOrder: Int
    let display: String       // "135 lbs × 8"
}

// MARK: - Active session (mutable mirror of WorkoutService.SavedSession)

struct ActiveSet: Identifiable {
    let id = UUID()
    var weight = ""
    var reps = ""
    var done = false
}

struct ActiveExercise: Identifiable {
    let id = UUID()
    let name: String
    var sets: [ActiveSet] = [ActiveSet()]
    var lastWeightHint: String?
}

// MARK: - Store

/// Drives the Android workout tab against the same DriftCore services the iOS
/// WorkoutView uses: WorkoutService (sessions/sets/streak/summaries) and
/// ExerciseDatabase (seeded catalog + custom). All DB work runs off the main
/// thread; the store publishes Sendable projections.
@MainActor @Observable public class WorkoutStore {
    var recent: [WorkoutRow] = []
    var streak = 0
    var thisWeekCount = 0
    var totalCount = 0

    var sessionActive = false
    var workoutName = "Workout"
    var startTime = Date()
    var exercises: [ActiveExercise] = []

    var detail: [WorkoutDetailRow] = []

    init() {
        resumeIfAny()
        reloadHome()
    }

    // MARK: Home

    func reloadHome() {
        Task {
            let snapshot = await Self.loadHomeSnapshot()
            recent = snapshot.rows
            streak = snapshot.streak
            thisWeekCount = snapshot.weekCount
            totalCount = snapshot.total
        }
    }

    private struct HomeSnapshot: Sendable {
        let rows: [WorkoutRow]
        let streak: Int
        let weekCount: Int
        let total: Int
    }

    private static func loadHomeSnapshot() async -> HomeSnapshot {
        await onDB {
            let workouts = (try? WorkoutService.fetchWorkouts(limit: 30)) ?? []
            let summaries = (try? WorkoutService.buildSummaries(for: workouts)) ?? []
            let rows = summaries.compactMap { s -> WorkoutRow? in
                guard let id = s.workout.id else { return nil }
                return WorkoutRow(id: id, name: s.workout.name, date: s.workout.date,
                                  exercises: s.exercises.joined(separator: ", "),
                                  totalSets: s.totalSets, totalVolume: Int(s.totalVolume), prs: s.prs)
            }
            let streak = (try? WorkoutService.workoutStreak())?.current ?? 0
            let week = (try? WorkoutService.weeklyWorkoutCounts(weeks: 1))?.first?.count ?? 0
            let total = (try? WorkoutService.totalWorkoutCount()) ?? 0
            return HomeSnapshot(rows: rows, streak: streak, weekCount: week, total: total)
        }
    }

    func loadDetail(workoutId: Int64) {
        detail = []
        Task {
            detail = await Self.loadDetailRows(workoutId: workoutId)
        }
    }

    private static func loadDetailRows(workoutId: Int64) async -> [WorkoutDetailRow] {
        await onDB {
            let sets = (try? WorkoutService.fetchSets(forWorkout: workoutId)) ?? []
            return sets.compactMap { s -> WorkoutDetailRow? in
                guard let id = s.id else { return nil }
                let weight = s.weightLbs.map { "\(Int($0)) lbs" }
                let reps = s.durationSec.map { "\($0)s" } ?? s.reps.map { "× \($0)" }
                let display = [weight, reps].compactMap { $0 }.joined(separator: " ")
                return WorkoutDetailRow(id: id, exerciseName: s.exerciseName, setOrder: s.setOrder,
                                        display: display.isEmpty ? "—" : display)
            }
        }
    }

    // MARK: Exercise catalog

    func searchExercises(_ query: String) async -> [ExerciseRow] {
        await Self.runCatalogSearch(query)
    }

    private static func runCatalogSearch(_ query: String) async -> [ExerciseRow] {
        await onDB {
            let hits = query.trimmingCharacters(in: .whitespaces).isEmpty
                ? Array(ExerciseDatabase.allWithCustom.prefix(60))
                : ExerciseDatabase.search(query: query)
            return hits.map { ExerciseRow(name: $0.name, bodyPart: $0.bodyPart, equipment: $0.equipment) }
        }
    }

    // MARK: Session lifecycle

    func startWorkout() {
        workoutName = defaultWorkoutName()
        startTime = Date()
        exercises = []
        sessionActive = true
        persistSession()
    }

    private func resumeIfAny() {
        guard let saved = WorkoutService.loadSession() else { return }
        workoutName = saved.workoutName
        startTime = saved.startTime
        exercises = saved.exercises.map { ex in
            var active = ActiveExercise(name: ex.name)
            active.sets = ex.sets.map { s in
                var set = ActiveSet()
                set.weight = s.weight
                set.reps = s.reps
                set.done = s.done
                return set
            }
            if active.sets.isEmpty { active.sets = [ActiveSet()] }
            return active
        }
        sessionActive = true
    }

    func addExercise(_ name: String) {
        guard !exercises.contains(where: { $0.name == name }) else { return }
        exercises.append(ActiveExercise(name: name))
        let index = exercises.count - 1
        persistSession()
        Task {
            if let last = await Self.lastWeightHint(for: name), index < exercises.count {
                exercises[index].lastWeightHint = last
            }
        }
    }

    private static func lastWeightHint(for name: String) async -> String? {
        await onDB {
            (try? WorkoutService.lastWeight(for: name)).flatMap { $0 }.map { "last: \(Int($0)) lbs" }
        }
    }

    func addSet(exerciseIndex: Int) {
        guard exercises.indices.contains(exerciseIndex) else { return }
        // Prefill from the previous set, matching the iOS flow.
        let previous = exercises[exerciseIndex].sets.last
        var set = ActiveSet()
        set.weight = previous?.weight ?? ""
        set.reps = previous?.reps ?? ""
        exercises[exerciseIndex].sets.append(set)
        persistSession()
    }

    func removeExercise(at index: Int) {
        guard exercises.indices.contains(index) else { return }
        exercises.remove(at: index)
        persistSession()
    }

    /// Mirror of the iOS ActiveWorkoutView persistence: every mutation writes
    /// the SavedSession so a crash/kill never loses an in-progress workout.
    func persistSession() {
        guard sessionActive else { return }
        let session = WorkoutService.SavedSession(
            workoutName: workoutName,
            startTime: startTime,
            exercises: exercises.map { ex in
                .init(name: ex.name, isWarmup: false, notes: nil, restTime: 0,
                      sets: ex.sets.map { .init(weight: $0.weight, reps: $0.reps, done: $0.done, isWarmup: false) })
            })
        WorkoutService.saveSession(session)
    }

    func cancelWorkout() {
        sessionActive = false
        exercises = []
        WorkoutService.clearSession()
    }

    /// Same mapping as iOS saveWorkout: done sets first; if none were marked
    /// done, fall back to every filled-in set.
    func finishWorkout() {
        let name = workoutName
        let duration = Int(Date().timeIntervalSince(startTime))
        let snapshot = exercises
        sessionActive = false
        exercises = []
        Task {
            await Self.persistFinishedWorkout(name: name, durationSeconds: duration, exercises: snapshot.map {
                FinishedExercise(name: $0.name, sets: $0.sets.map {
                    FinishedSet(weight: $0.weight, reps: $0.reps, done: $0.done)
                })
            })
            reloadHome()
        }
    }

    struct FinishedSet: Sendable { let weight: String; let reps: String; let done: Bool }
    struct FinishedExercise: Sendable { let name: String; let sets: [FinishedSet] }

    private static func persistFinishedWorkout(name: String, durationSeconds: Int,
                                               exercises: [FinishedExercise]) async {
        await onDB {
            WorkoutService.clearSession()
            var workout = Workout(name: name, date: DateFormatters.dateOnly.string(from: Date()),
                                  durationSeconds: durationSeconds, notes: nil,
                                  createdAt: ISO8601DateFormatter().string(from: Date()))
            do {
                try WorkoutService.saveWorkout(&workout)
                guard let wid = workout.id else { return }
                func sets(requireDone: Bool) -> [WorkoutSet] {
                    var rows: [WorkoutSet] = []
                    for (ei, ex) in exercises.enumerated() {
                        for (si, s) in ex.sets.enumerated() where !requireDone || s.done {
                            let weight = Double(s.weight.replacingOccurrences(of: ",", with: ".")) ?? 0
                            let reps = Int(s.reps) ?? 0
                            guard reps > 0 else { continue }
                            rows.append(WorkoutSet(workoutId: wid, exerciseName: ex.name, setOrder: si + 1,
                                                   weightLbs: weight > 0 ? weight : nil, reps: reps,
                                                   isWarmup: false, exerciseOrder: ei))
                        }
                    }
                    return rows
                }
                var all = sets(requireDone: true)
                if all.isEmpty { all = sets(requireDone: false) }
                try WorkoutService.saveSets(all)
            } catch {
                Log.app.error("Android finishWorkout: \(error)")
            }
        }
    }

    private func defaultWorkoutName() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case ..<12: return "Morning Workout"
        case ..<17: return "Afternoon Workout"
        default: return "Evening Workout"
        }
    }

    // MARK: - Off-main DB helper

    private static func onDB<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }
}
