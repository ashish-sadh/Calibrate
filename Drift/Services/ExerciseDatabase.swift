import Foundation

/// 873 exercises from free-exercise-db with muscle groups and equipment.
enum ExerciseDatabase {
    struct ExerciseInfo: Codable, Sendable, Identifiable {
        var id: String { name }
        let name: String
        let bodyPart: String
        let primaryMuscles: [String]
        let secondaryMuscles: [String]
        let equipment: String
        let category: String
        let level: String
    }

    nonisolated(unsafe) private static var _exercises: [ExerciseInfo]?

    static var all: [ExerciseInfo] {
        if let cached = _exercises { return cached }
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ExerciseInfo].self, from: data) else {
            return []
        }
        _exercises = decoded
        return decoded
    }

    static func search(query: String) -> [ExerciseInfo] {
        if query.isEmpty { return all }
        let q = query.lowercased()
        return all.filter {
            $0.name.lowercased().contains(q) ||
            $0.bodyPart.lowercased().contains(q) ||
            $0.primaryMuscles.contains { $0.lowercased().contains(q) } ||
            $0.equipment.lowercased().contains(q)
        }
    }

    // MARK: - Custom Exercises (persisted in UserDefaults)

    private static let customKey = "drift_custom_exercises"

    static var customExercises: [ExerciseInfo] {
        guard let data = UserDefaults.standard.data(forKey: customKey),
              let decoded = try? JSONDecoder().decode([ExerciseInfo].self, from: data) else { return [] }
        return decoded
    }

    static func addCustomExercise(name: String, bodyPart: String) {
        var customs = customExercises
        guard !customs.contains(where: { $0.name.lowercased() == name.lowercased() }) else { return }
        customs.append(ExerciseInfo(name: name, bodyPart: bodyPart, primaryMuscles: [bodyPart.lowercased()],
                                    secondaryMuscles: [], equipment: "other", category: "strength", level: "intermediate"))
        if let data = try? JSONEncoder().encode(customs) {
            UserDefaults.standard.set(data, forKey: customKey)
        }
        _exercises = nil // clear cache so `all` reloads
    }

    // Include custom exercises in all searches
    static var allWithCustom: [ExerciseInfo] { all + customExercises }

    static func byBodyPart(_ part: String) -> [ExerciseInfo] {
        allWithCustom.filter { $0.bodyPart == part }
    }

    static func info(for name: String) -> ExerciseInfo? {
        allWithCustom.first { $0.name.lowercased() == name.lowercased() }
    }

    static func bodyPart(for name: String) -> String {
        info(for: name)?.bodyPart ?? guessBodyPart(name)
    }

    private static func guessBodyPart(_ name: String) -> String {
        let e = name.lowercased()
        if e.contains("bench") || e.contains("chest") || e.contains("fly") || e.contains("dip") { return "Chest" }
        if e.contains("squat") || e.contains("leg") || e.contains("calf") || e.contains("deadlift") || e.contains("lunge") || e.contains("hip") || e.contains("thrust") { return "Legs" }
        if e.contains("lat") || e.contains("row") || e.contains("pull") || e.contains("back") { return "Back" }
        if e.contains("shoulder") || e.contains("lateral raise") || e.contains("overhead") || e.contains("face pull") || e.contains("military") { return "Shoulders" }
        if e.contains("bicep") || e.contains("curl") || e.contains("tricep") || e.contains("hammer") { return "Arms" }
        if e.contains("crunch") || e.contains("plank") || e.contains("ab") || e.contains("leg raise") { return "Core" }
        return "Other"
    }
}
