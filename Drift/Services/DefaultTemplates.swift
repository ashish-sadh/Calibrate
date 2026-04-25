import Foundation
import DriftCore

/// Seeds default workout templates on first launch. Respects user edits - only seeds if no templates exist.
enum DefaultTemplates {
    private static let seededKey = "drift_default_templates_v3"

    /// Legacy auto-seed (no longer called from app launch).
    static func seedIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        loadCurated()
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    /// Load Drift Curated templates on demand. Skips any that already exist by name.
    @discardableResult
    static func loadCurated() -> Int {
        let existing = Set((try? WorkoutService.fetchTemplates())?.map(\.name) ?? [])
        var added = 0

        for template in allTemplates {
            guard !existing.contains(template.name) else { continue }
            var t = template
            try? WorkoutService.saveTemplate(&t)
            added += 1
        }

        // Add custom exercises needed by curated templates
        let dbNames = Set(ExerciseDatabase.all.map { $0.name.lowercased() })
        for (name, bodyPart) in customExercises {
            if !dbNames.contains(name.lowercased()) {
                ExerciseDatabase.addCustomExercise(name: name, bodyPart: bodyPart)
            }
        }

        Log.app.info("Loaded \(added) Drift Curated templates (skipped \(allTemplates.count - added) existing)")
        return added
    }

    /// All custom exercises needed across all programs
    private static let customExercises: [(String, String)] = [
        // Warmup
        ("Banded Shoulder Rotations", "Shoulders"),
        ("Banded Pull Aparts (Palms Up)", "Shoulders"),
        ("Banded Pull Aparts (Palms Down)", "Shoulders"),
        ("Shoulder Depressions", "Shoulders"),
        ("Rope Pulling Machine", "Full Body"),
        ("Ladder Drill", "Full Body"),
        ("90/90 Hip Stretch + Extensions", "Legs"),
        ("90/90 Switches", "Legs"),
        ("Banded Lateral Walks", "Legs"),
        // Chest
        ("Incline Chest Press", "Chest"),
        ("Standing Cable Chest Flies (High to Low)", "Chest"),
        ("Assisted Dips", "Chest"),
        // Core
        ("Crunch Machine", "Core"),
        ("Yoga Ball Pike", "Core"),
        ("Woodchopper", "Core"),
        ("Paloff Press", "Core"),
        ("Copenhagen Planks", "Core"),
        ("Side Planks", "Core"),
        ("Dragon Flags", "Core"),
        // Back
        ("High Rows", "Back"),
        ("TRX Rows", "Back"),
        ("Assisted Pull-Ups", "Back"),
        ("Seated Supinating Rows", "Back"),
        ("Chest Supported Row", "Back"),
        // Arms
        ("Wrist Extension", "Arms"),
        ("Wrist Flexion", "Arms"),
        ("Barbell Wrist Rolls", "Arms"),
        ("Plate Pinches", "Arms"),
        ("Crossbody Hammer Curls", "Arms"),
        ("Overhead Tricep Extensions", "Arms"),
        ("Cable Tricep Extensions", "Arms"),
        ("Reverse Curls", "Arms"),
        // Legs
        ("Bulgarian Split Squats", "Legs"),
        ("Heavy Suitcase Carries", "Full Body"),
        ("Hip Abduction Machine", "Legs"),
        ("Hip Adduction Machine", "Legs"),
        ("Seated Hamstring Curl", "Legs"),
        ("Single Leg Deadlift", "Legs"),
        ("Cossack Squats", "Legs"),
        // Shoulders
        ("Cable Lateral Raise", "Shoulders"),
        ("Arnold Press", "Shoulders"),
        ("Front Raise", "Shoulders"),
        ("Shrug", "Shoulders"),
        // Common aliases for better search
        ("Goblet Squat", "Legs"),
        ("Sumo Squat", "Legs"),
        ("Step-Ups", "Legs"),
        ("Glute Bridge", "Legs"),
        ("Wall Sit", "Legs"),
        ("Skull Crushers", "Arms"),
        ("Rope Pushdown", "Arms"),
        ("Cable Fly", "Chest"),
        ("Plank", "Core"),
        ("Dead Bug", "Core"),
        ("Pull-Up", "Back"),
        ("Burpee", "Full Body"),
        // Full Body
        ("Ab Wheel Rollout", "Core"),
        ("Battle Ropes", "Full Body"),
        ("Box Jump", "Legs"),
        ("Mountain Climber", "Core"),
        ("Machine Chest Press", "Chest"),
        ("Machine Shoulder Press", "Shoulders"),
        ("Seated Cable Row", "Back"),
        ("Spider Curl", "Arms"),
        ("Cable Tricep Kickback", "Arms"),
        // Common names used in templates (exist in DB under longer names)
        ("Deadlift", "Legs"),
        ("Dips", "Chest"),
        ("Push-Ups", "Chest"),
        ("Lat Pulldown", "Back"),
        ("Shoulder Press", "Shoulders"),
        ("Lateral Raise", "Shoulders"),
        ("Bicep Curl", "Arms"),
        ("Tricep Extension", "Arms"),
        ("Cable Tricep Extensions", "Arms"),
        ("Overhead Tricep Extensions", "Arms"),
        ("Reverse Curls", "Arms"),
        ("Upright Row", "Shoulders"),
        ("Bent-Over Row", "Back"),
        ("Dumbbell Row", "Back"),
        ("Leg Raise", "Core"),
        ("Back Extension", "Back"),
        ("Calf Raises", "Legs"),
        ("Cossack Squats", "Legs"),
        ("Seated Hamstring Curl", "Legs"),
        ("Heavy Suitcase Carries", "Full Body"),
        // Additional common exercises
        ("Chest Press Machine", "Chest"),
        ("Pec Deck", "Chest"),
        ("Preacher Curl Machine", "Arms"),
        ("EZ Bar Curl", "Arms"),
        ("Rope Pushdown", "Arms"),
        ("Turkish Get-Up", "Full Body"),
        ("Chin-Up", "Back"),
    ]

    // MARK: - Helper

    private static func json(_ exercises: [WorkoutTemplate.TemplateExercise]) -> String {
        (try? JSONEncoder().encode(exercises)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
    private static let now = ISO8601DateFormatter().string(from: Date())
    private static func w(_ name: String, sets: Int = 2, rest: Int = 15, notes: String? = nil) -> WorkoutTemplate.TemplateExercise {
        .init(name: name, sets: sets, isWarmup: true, restSeconds: rest, notes: notes)
    }
    private static func e(_ name: String, sets: Int = 3, rest: Int = 90, notes: String? = nil) -> WorkoutTemplate.TemplateExercise {
        .init(name: name, sets: sets, restSeconds: rest, notes: notes)
    }

    // MARK: - All Templates

    private static var allTemplates: [WorkoutTemplate] {
        program4 + program3 + program2 + program1
    }

    // MARK: - Program 4 (Current - Start 3/12/26)

    private static var program4: [WorkoutTemplate] {
        [
            WorkoutTemplate(name: "Day 1 - Chest/Core", exercisesJson: json([
                w("Banded Shoulder Rotations", notes: "2x10"),
                w("Banded Pull Aparts (Palms Up)", notes: "2x10"),
                w("Banded Pull Aparts (Palms Down)", notes: "2x10"),
                w("Shoulder Depressions", notes: "2x10"),
                w("Dumbbell Shrug", sets: 2, notes: "2x15"),
                e("Incline Chest Press", rest: 150, notes: "5-8 reps"),
                e("Dumbbell Bench Press", rest: 120, notes: "8-10 reps"),
                e("Dips", rest: 120, notes: "8-12 reps"),
                e("Leg Raise", rest: 90, notes: "8-10 reps, Captain's Chair"),
                e("Crunch Machine", rest: 90, notes: "8-12 reps"),
                e("Back Extension", rest: 90, notes: "8-12 reps"),
            ]), createdAt: now, isFavorite: true),

            WorkoutTemplate(name: "Day 2 - Forearms/Accessories", exercisesJson: json([
                w("Rope Pulling Machine", sets: 1, rest: 30, notes: "5 mins"),
                w("Banded Shoulder Rotations", notes: "2x10"),
                e("Lat Pulldown", rest: 105, notes: "8-10 reps, scap depression"),
                e("High Rows", rest: 105, notes: "8-12 reps"),
                e("Reverse Barbell Curl", rest: 75, notes: "10-15 reps"),
                e("Wrist Extension", rest: 45, notes: "10-15 reps"),
                e("Wrist Flexion", rest: 45, notes: "10-15 reps"),
                e("Farmer's Walk", rest: 75, notes: "30-45 secs"),
                e("Shoulder Press", rest: 75, notes: "10-15 reps"),
                e("Lateral Raise", rest: 75, notes: "10-15 reps"),
            ]), createdAt: now, isFavorite: true),

            WorkoutTemplate(name: "Day 3 - Chest/Core", exercisesJson: json([
                w("Banded Shoulder Rotations", notes: "2x10"),
                w("Banded Pull Aparts (Palms Up)", notes: "2x10"),
                w("Banded Pull Aparts (Palms Down)", notes: "2x10"),
                w("Shoulder Depressions", notes: "2x10"),
                w("Dumbbell Shrug", sets: 2, notes: "2x15"),
                e("Incline Dumbbell Press", rest: 120, notes: "10-12 reps, 30° bench"),
                e("Push-Ups", rest: 120, notes: "20 reps, strict then assisted"),
                e("Standing Cable Chest Flies (High to Low)", rest: 60, notes: "12-15 reps"),
                e("Yoga Ball Pike", rest: 75, notes: "8-12 reps"),
                e("Woodchopper", rest: 75, notes: "8-15 reps, SS w/ Paloff Press"),
                e("Decline Crunch", rest: 75, notes: "8-15 reps, use weight"),
            ]), createdAt: now, isFavorite: true),

            WorkoutTemplate(name: "Day 4 - Lower/Forearms", exercisesJson: json([
                w("Ladder Drill", sets: 1, rest: 30, notes: "2-5 mins"),
                w("90/90 Hip Stretch + Extensions", notes: "2x10"),
                w("Banded Shoulder Rotations", notes: "2x10"),
                w("Banded Pull Aparts (Palms Up)", notes: "2x10"),
                w("Banded Pull Aparts (Palms Down)", notes: "2x10"),
                e("Deadlift", rest: 150, notes: "2-3x5-8 reps"),
                e("Assisted Pull-Ups", rest: 150, notes: "5-8 reps"),
                e("Bulgarian Split Squats", rest: 120, notes: "8-10 reps"),
                e("TRX Rows", rest: 105, notes: "8-12 reps"),
                e("Hammer Curls", rest: 75, notes: "8-15 reps"),
                e("Barbell Wrist Rolls", rest: 75, notes: "10-15 reps"),
                e("Plate Pinches", rest: 75, notes: "20-30 secs"),
            ]), createdAt: now, isFavorite: true),
        ]
    }

    // MARK: - Program 3

    private static var program3: [WorkoutTemplate] {
        [
            WorkoutTemplate(name: "P3 Day 1 - Lower", exercisesJson: json([
                w("90/90 Switches", notes: "10 per side"),
                w("Banded Lateral Walks", notes: "2x12"),
                w("Seated Hamstring Curl", sets: 2, notes: "2x8-10"),
                e("Deadlift", rest: 150, notes: "3x5-8"),
                e("Leg Press", rest: 105, notes: "3x8-10"),
                e("Cossack Squats", rest: 105, notes: "3x8-12"),
                e("Leg Extensions", rest: 75, notes: "3x8-12"),
                e("Seated Hamstring Curl", rest: 75, notes: "3x8-12"),
                e("Hip Abduction Machine", sets: 2, rest: 60, notes: "2x8-12"),
                e("Hip Adduction Machine", sets: 2, rest: 60, notes: "2x8-12"),
                e("Calf Raises", rest: 60, notes: "3x8-12"),
            ]), createdAt: now),

            WorkoutTemplate(name: "P3 Day 2 - Upper", exercisesJson: json([
                w("Banded Shoulder Rotations", sets: 1, notes: "10 reps"),
                w("Banded Pull Aparts (Palms Up)", notes: "2x10"),
                w("Upright Row", sets: 2, notes: "2x12"),
                w("Wrist Extension", sets: 2, notes: "2x12-15"),
                w("Wrist Flexion", sets: 2, notes: "2x12-15"),
                e("Assisted Pull-Ups", rest: 150, notes: "3x5-8"),
                e("Incline Chest Press", sets: 4, rest: 105, notes: "4x8-12"),
                e("Seated Supinating Rows", rest: 105, notes: "3x8-12"),
                e("Upright Row", rest: 75, notes: "3x12-15"),
                e("Crossbody Hammer Curls", rest: 75, notes: "3x8-12"),
                e("Cable Tricep Extensions", rest: 75, notes: "3x8-15, SS w/ lateral raises"),
                e("Lateral Raise", rest: 60, notes: "3x12-15"),
            ]), createdAt: now),

            WorkoutTemplate(name: "P3 Day 3 - Full Body", exercisesJson: json([
                w("90/90 Switches", notes: "10 per side"),
                w("Banded Lateral Walks", notes: "2x12"),
                w("Seated Hamstring Curl", sets: 2, notes: "2x8-10"),
                w("Banded Shoulder Rotations", sets: 1, notes: "10 reps"),
                w("Banded Pull Aparts (Palms Up)", notes: "2x10"),
                w("Upright Row", sets: 2, notes: "2x12"),
                e("Deadlift", rest: 180, notes: "3x3-5"),
                e("Bulgarian Split Squats", rest: 105, notes: "3x8-12"),
                e("Dumbbell Bench Press", sets: 4, rest: 105, notes: "4x8-12"),
                e("Shoulder Press", rest: 75, notes: "3x10-15"),
                e("Lat Pulldown", rest: 75, notes: "3x8-12, palms facing you"),
                e("Dumbbell Row", rest: 75, notes: "3x8-12"),
                e("Heavy Suitcase Carries", rest: 60, notes: "3x40-60 secs"),
            ]), createdAt: now),

            WorkoutTemplate(name: "P3 Day 4 - Core/Arms/Shoulders", exercisesJson: json([
                e("Crunch Machine", rest: 75, notes: "3x10-12, do obliques too"),
                e("Leg Raise", rest: 75, notes: "3x8-15, or dragon flags"),
                e("Face Pull", sets: 4, rest: 75, notes: "4x10-15"),
                e("Overhead Tricep Extensions", sets: 4, rest: 75, notes: "4x8-12"),
                e("Reverse Curls", sets: 4, rest: 75, notes: "4x8-12"),
                e("Lateral Raise", sets: 4, rest: 75, notes: "4x12-15"),
            ]), createdAt: now),
        ]
    }

    // MARK: - Program 2

    private static var program2: [WorkoutTemplate] {
        [
            WorkoutTemplate(name: "P2 Day 1 - Upper 1", exercisesJson: json([
                w("TRX Rows", notes: "2x10, easy-medium"),
                w("90/90 Switches", notes: "8 per side"),
                w("Dumbbell Shrug", sets: 2, notes: "Shrugs warmup"),
                e("Deadlift", rest: 150, notes: "3x5-8"),
                e("Seated Supinating Rows", rest: 105, notes: "3x8-12"),
                e("Dumbbell Bench Press", sets: 4, rest: 105, notes: "4x8-12"),
                e("Shoulder Press", rest: 75, notes: "3x12-15"),
                e("Upright Row", rest: 75, notes: "3x12-15"),
                e("Crossbody Hammer Curls", rest: 75, notes: "3x8-12"),
                e("Heavy Suitcase Carries", rest: 45, notes: "3x40-60 secs"),
            ]), createdAt: now),

            WorkoutTemplate(name: "P2 Day 2 - Upper 2", exercisesJson: json([
                w("Banded Shoulder Rotations", sets: 1, notes: "10 reps"),
                w("Banded Pull Aparts (Palms Up)", notes: "2x10"),
                w("Upright Row", sets: 2, notes: "2x12"),
                e("Assisted Pull-Ups", rest: 150, notes: "3x5-8"),
                e("Incline Chest Press", sets: 4, rest: 105, notes: "4x8-12"),
                e("Bent-Over Row", rest: 105, notes: "3x8-12"),
                e("Lat Pulldown", rest: 105, notes: "3x8-12, palms facing you"),
                e("Cossack Squats", rest: 105, notes: "3x8-12"),
                e("Cable Tricep Extensions", rest: 75, notes: "3x8-15, SS w/ lateral raises"),
                e("Lateral Raise", rest: 60, notes: "3x12-15"),
            ]), createdAt: now),

            WorkoutTemplate(name: "P2 Day 3 - Lower", exercisesJson: json([
                w("Banded Lateral Walks", notes: "2x12"),
                w("Seated Hamstring Curl", sets: 2, notes: "2x8-10"),
                e("Leg Press", rest: 105, notes: "3x8-10"),
                e("Romanian Deadlift", rest: 105, notes: "3x8-10"),
                e("Bulgarian Split Squats", rest: 105, notes: "3x8-12"),
                e("Leg Extensions", rest: 75, notes: "3x8-12"),
                e("Seated Hamstring Curl", rest: 75, notes: "3x8-12"),
                e("Hip Abduction Machine", rest: 60, notes: "3x10-12, SS w/ adduction"),
                e("Hip Adduction Machine", rest: 60, notes: "3x10-12"),
                e("Calf Raises", rest: 60, notes: "3x8-12"),
            ]), createdAt: now),

            WorkoutTemplate(name: "P2 Day 4 - Core/Arms/Shoulders", exercisesJson: json([
                e("Crunch Machine", rest: 75, notes: "3x10-12, do obliques too"),
                e("Leg Raise", rest: 75, notes: "3x8-15, or dragon flags"),
                e("Face Pull", sets: 4, rest: 75, notes: "4x10-15"),
                e("Overhead Tricep Extensions", sets: 4, rest: 75, notes: "4x8-12"),
                e("Reverse Curls", sets: 4, rest: 75, notes: "4x8-12"),
                e("Lateral Raise", sets: 4, rest: 75, notes: "4x12-15"),
            ]), createdAt: now),
        ]
    }

    // MARK: - Program 1

    private static var program1: [WorkoutTemplate] {
        [
            WorkoutTemplate(name: "P1 Lower + Core", exercisesJson: json([
                e("Deadlift", rest: 150, notes: "3x5-8"),
                e("Bulgarian Split Squats", rest: 105, notes: "3x8-12"),
                e("Seated Hamstring Curl", rest: 75, notes: "3x8-12"),
                e("Hip Adduction Machine", rest: 75, notes: "3x8-15"),
                e("Heavy Suitcase Carries", rest: 60, notes: "3x30-60 secs"),
                e("Leg Raise", rest: 75, notes: "3x8-15, or dragon flags"),
            ]), createdAt: now),

            WorkoutTemplate(name: "P1 Upper", exercisesJson: json([
                e("Assisted Pull-Ups", rest: 150, notes: "3x8-12"),
                e("Dumbbell Bench Press", rest: 105, notes: "3x8-12"),
                e("Seated Cable Row", rest: 75, notes: "3x8-15"),
                e("Bicep Curl", sets: 3, rest: 75, notes: "2-3x8-12"),
                e("Tricep Extension", sets: 3, rest: 75, notes: "2-3x8-12"),
                e("Lateral Raise", sets: 3, rest: 75, notes: "2-3x8-15"),
            ]), createdAt: now),

            WorkoutTemplate(name: "P1 Full Body + Core", exercisesJson: json([
                e("Leg Press", rest: 105, notes: "3x8-15"),
                e("Incline Dumbbell Press", rest: 105, notes: "3x8-12"),
                e("High Rows", rest: 75, notes: "3x8-15"),
                e("Assisted Dips", rest: 75, notes: "3x8-12"),
                e("Back Extension", rest: 75, notes: "3x8-12"),
                e("Side Planks", rest: 60, notes: "3 sets"),
            ]), createdAt: now),
        ]
    }
}
