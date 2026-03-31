import Foundation

/// Seeds default workout templates on first launch. Respects user edits - only seeds if no templates exist.
enum DefaultTemplates {
    private static let seededKey = "drift_default_templates_seeded"

    static func seedIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        guard (try? WorkoutService.fetchTemplates())?.isEmpty ?? true else {
            UserDefaults.standard.set(true, forKey: seededKey)
            return
        }

        for template in programTemplates {
            var t = template
            try? WorkoutService.saveTemplate(&t)
        }

        // Also add any missing exercises as custom
        let allExerciseNames = Set(ExerciseDatabase.all.map { $0.name.lowercased() })
        let customNames: [String: String] = [
            "Ladder Drill": "Full Body",
            "90/90 Hip Stretch + Extensions": "Legs",
            "Banded Shoulder Rotations": "Shoulders",
            "Banded Pull Aparts (Palms Up)": "Shoulders",
            "Banded Pull Aparts (Palms Down)": "Shoulders",
            "Shoulder Shrugs": "Shoulders",
            "Standing Cable Flyes": "Chest",
            "Machine Crunches": "Core",
            "Rope Climb Machine": "Full Body",
            "Low Cable Rows": "Back",
            "Rear Delt Flyes": "Shoulders",
            "Farmer's Walk": "Full Body",
            "Plate Pinches": "Arms",
            "Barbell Wrist Rolls": "Arms",
            "Incline Barbell Bench Press": "Chest",
            "Flat Dumbbell Press": "Chest",
            "Standing Cable Flyes (Alt Grip)": "Chest",
            "Hanging Knee Raises": "Core",
            "Bicycle Crunches": "Core",
            "Bulgarian Split Squats": "Legs",
            "TRX Rows": "Back",
            "Assisted Pull-Ups": "Back",
        ]
        for (name, bodyPart) in customNames {
            if !allExerciseNames.contains(name.lowercased()) {
                ExerciseDatabase.addCustomExercise(name: name, bodyPart: bodyPart)
            }
        }

        UserDefaults.standard.set(true, forKey: seededKey)
        Log.app.info("Seeded \(programTemplates.count) default workout templates")
    }

    // MARK: - Program #4 (Trainer Plan)

    private static var programTemplates: [WorkoutTemplate] {
        let encoder = JSONEncoder()
        func json(_ exercises: [WorkoutTemplate.TemplateExercise]) -> String {
            (try? encoder.encode(exercises)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        }
        let now = ISO8601DateFormatter().string(from: Date())

        return [
            // Day 1 - Chest/Core (Monday)
            WorkoutTemplate(name: "Day 1 - Chest/Core", exercisesJson: json([
                .init(name: "Banded Shoulder Rotations", sets: 2, isWarmup: true, restSeconds: 30, notes: "2x10"),
                .init(name: "Banded Pull Aparts (Palms Up)", sets: 2, isWarmup: true, restSeconds: 30, notes: "2x10"),
                .init(name: "Shoulder Shrugs", sets: 1, isWarmup: true, restSeconds: 30, notes: "1x12"),
                .init(name: "Barbell Bench Press", sets: 3, restSeconds: 150, notes: "6-8 reps"),
                .init(name: "Incline Dumbbell Press", sets: 3, restSeconds: 120, notes: "8-10 reps"),
                .init(name: "Incline Dumbbell Flyes", sets: 3, restSeconds: 105, notes: "8-12 reps"),
                .init(name: "Standing Cable Flyes", sets: 3, restSeconds: 75, notes: "8-15 reps"),
                .init(name: "Leg Raises", sets: 3, restSeconds: 60, notes: "12 reps"),
                .init(name: "Machine Crunches", sets: 3, restSeconds: 60, notes: "15-20 reps"),
            ]), createdAt: now),

            // Day 2 - Forearms/Accessories (Tuesday)
            WorkoutTemplate(name: "Day 2 - Back/Forearms", exercisesJson: json([
                .init(name: "Banded Shoulder Rotations", sets: 2, isWarmup: true, restSeconds: 30, notes: "2x10"),
                .init(name: "Lat Pulldown", sets: 3, restSeconds: 105, notes: "8 reps"),
                .init(name: "Low Cable Rows", sets: 3, restSeconds: 105, notes: "8-10 reps"),
                .init(name: "Shoulder Shrugs", sets: 3, restSeconds: 75, notes: "8-10 reps"),
                .init(name: "Rear Delt Flyes", sets: 3, restSeconds: 75, notes: "8-12 reps"),
                .init(name: "Hammer Curls", sets: 3, restSeconds: 75, notes: "8-15 reps"),
                .init(name: "Farmer's Walk", sets: 3, restSeconds: 75, notes: "30-40 secs"),
                .init(name: "Plate Pinches", sets: 3, restSeconds: 75, notes: "20-30 secs"),
            ]), createdAt: now),

            // Day 3 - Chest/Core (Thursday)
            WorkoutTemplate(name: "Day 3 - Chest/Core", exercisesJson: json([
                .init(name: "Banded Shoulder Rotations", sets: 2, isWarmup: true, restSeconds: 30, notes: "Circuit: 2x10"),
                .init(name: "Banded Pull Aparts (Palms Up)", sets: 2, isWarmup: true, restSeconds: 30, notes: "Circuit: 2x10"),
                .init(name: "Shoulder Shrugs", sets: 1, isWarmup: true, restSeconds: 30, notes: "Circuit: 1x12"),
                .init(name: "Incline Barbell Bench Press", sets: 3, restSeconds: 150, notes: "6-8 reps"),
                .init(name: "Flat Dumbbell Press", sets: 3, restSeconds: 120, notes: "8-10 reps"),
                .init(name: "Dips", sets: 3, restSeconds: 105, notes: "8-12 reps"),
                .init(name: "Standing Cable Flyes (Alt Grip)", sets: 3, restSeconds: 75, notes: "8-15 reps"),
                .init(name: "Hanging Knee Raises", sets: 3, restSeconds: 60, notes: "15 reps"),
                .init(name: "Bicycle Crunches", sets: 3, restSeconds: 60, notes: "20/side"),
            ]), createdAt: now),

            // Day 4 - Lower Body/Forearms (flexible day)
            WorkoutTemplate(name: "Day 4 - Lower/Forearms", exercisesJson: json([
                .init(name: "Ladder Drill", sets: 1, isWarmup: true, restSeconds: 30, notes: "2-5 mins"),
                .init(name: "90/90 Hip Stretch + Extensions", sets: 2, isWarmup: true, restSeconds: 30, notes: "2x10"),
                .init(name: "Banded Shoulder Rotations", sets: 2, isWarmup: true, restSeconds: 30, notes: "2x10"),
                .init(name: "Banded Pull Aparts (Palms Up)", sets: 2, isWarmup: true, restSeconds: 30, notes: "2x10"),
                .init(name: "Banded Pull Aparts (Palms Down)", sets: 2, isWarmup: true, restSeconds: 30, notes: "2x10"),
                .init(name: "Deadlift", sets: 3, restSeconds: 150, notes: "5-8 reps"),
                .init(name: "Assisted Pull-Ups", sets: 3, restSeconds: 150, notes: "5-8 reps"),
                .init(name: "Bulgarian Split Squats", sets: 3, restSeconds: 120, notes: "8-10 reps"),
                .init(name: "TRX Rows", sets: 3, restSeconds: 105, notes: "8-12 reps"),
                .init(name: "Hammer Curls", sets: 3, restSeconds: 75, notes: "8-15 reps"),
                .init(name: "Barbell Wrist Rolls", sets: 3, restSeconds: 75, notes: "10-15 reps"),
                .init(name: "Plate Pinches", sets: 3, restSeconds: 75, notes: "20-30 secs"),
            ]), createdAt: now),
        ]
    }
}
