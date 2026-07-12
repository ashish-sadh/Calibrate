import Foundation

/// Seeds default workout templates on demand. Respects user edits — only adds
/// templates/exercises that don't already exist by name.
///
/// Four packages (renumbered 2026-07-11 — operator: the latest-sent program
/// gets top billing):
///  - **Drift Package I** — the Cindy full-body program (trainer text,
///    received 2026-07-11).
///  - **Drift Package II** — the Srijith training program (total-body free
///    weights / dumbbells / circuits / strength + pull & push days).
///  - **Drift Package III** — the whiteboard resistance band program
///    (A/B days, imported 2026-07-09).
///  - **Drift Package IV** — the original curated programs 1–4 (#940;
///    was Package I).
/// Packages load ONLY from the Templates menu — never on install. Loading
/// skips templates the user already has by name, and none arrive favorited
/// (field report: seeded `isFavorite` stars looked random).
/// Every custom exercise registered here carries real catalog muscle slugs
/// (drives the anatomy diagram) and, where a genuine free-exercise-db analog
/// exists, an imageUrl so the bundled pose crossfade resolves (#929). A nil
/// fedDir means the movement has no honest photo analog — the muscle diagram
/// is the fallback, never a wrong demo.
public enum DefaultTemplates {
    /// Load Drift Package I templates (Cindy full-body program) on demand.
    /// Skips any that already exist by name.
    @discardableResult
    public static func loadPackageI() -> Int {
        let added = load(templates: packageI)
        Log.app.info("Loaded \(added) Drift Package I templates")
        return added
    }

    /// Load Drift Package II templates (Srijith program) on demand.
    @discardableResult
    public static func loadPackageII() -> Int {
        let added = load(templates: packageII)
        Log.app.info("Loaded \(added) Drift Package II templates")
        return added
    }

    /// Load Drift Package III templates (whiteboard resistance A/B) on demand.
    @discardableResult
    public static func loadPackageIII() -> Int {
        let added = load(templates: packageIII)
        Log.app.info("Loaded \(added) Drift Package III templates")
        return added
    }

    /// Load Drift Package IV templates (original curated programs 1–4) on demand.
    @discardableResult
    public static func loadPackageIV() -> Int {
        let added = load(templates: packageIV)
        Log.app.info("Loaded \(added) Drift Package IV templates")
        return added
    }

    private static func load(templates: [WorkoutTemplate]) -> Int {
        let existing = Set((try? WorkoutService.fetchTemplates())?.map(\.name) ?? [])
        var added = 0
        for template in templates {
            guard !existing.contains(template.name) else { continue }
            var t = template
            try? WorkoutService.saveTemplate(&t)
            added += 1
        }
        registerCustomExercises()
        return added
    }

    // MARK: - Custom exercise registry

    struct CustomExercise {
        let name: String
        let bodyPart: String
        /// Real catalog muscle slugs — the anatomy diagram highlights these.
        var muscles: [String]? = nil
        /// free-exercise-db directory for the bundled pose crossfade; nil =
        /// no honest photo analog, diagram-only.
        var fedDir: String? = nil
    }

    /// Idempotent — safe to call at every launch: fills missing visual
    /// fields (muscles/poses) on customs registered by older builds (#941).
    public static func registerCustomExercises() {
        let dbNames = Set(ExerciseDatabase.all.map { $0.name.lowercased() })
        for c in customExercises where !dbNames.contains(c.name.lowercased()) {
            ExerciseDatabase.addCustomExercise(
                name: c.name, bodyPart: c.bodyPart,
                primaryMuscles: c.muscles,
                imageUrl: c.fedDir.map {
                    "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/\($0)/0.jpg"
                },
                imageUrlAuthoritative: true)
        }
    }

    /// All custom exercises needed across both packages.
    static let customExercises: [CustomExercise] = [
        // Warmup / mobility
        .init(name: "Banded Shoulder Rotations", bodyPart: "Shoulders", muscles: ["shoulders"], fedDir: "External_Rotation_with_Band"),
        .init(name: "Banded Pull Aparts (Palms Up)", bodyPart: "Shoulders", muscles: ["shoulders", "middle back"], fedDir: "Band_Pull_Apart"),
        .init(name: "Banded Pull Aparts (Palms Down)", bodyPart: "Shoulders", muscles: ["shoulders", "middle back"], fedDir: "Band_Pull_Apart"),
        .init(name: "Shoulder Depressions", bodyPart: "Shoulders", muscles: ["traps"]),
        .init(name: "Rope Pulling Machine", bodyPart: "Full Body", muscles: ["lats", "biceps"]),
        .init(name: "Ladder Drill", bodyPart: "Full Body", muscles: ["quadriceps", "calves"]),
        .init(name: "90/90 Hip Stretch + Extensions", bodyPart: "Legs", muscles: ["glutes"]),
        .init(name: "90/90 Switches", bodyPart: "Legs", muscles: ["glutes"]),
        .init(name: "Banded Lateral Walks", bodyPart: "Legs", muscles: ["glutes"], fedDir: "Banded_Lateral_Walks"),
        .init(name: "Down Dog to Plank", bodyPart: "Core", muscles: ["abdominals", "shoulders"]),
        .init(name: "World's Greatest Stretch", bodyPart: "Full Body", muscles: ["hamstrings", "glutes"]),
        // Chest
        .init(name: "Incline Chest Press", bodyPart: "Chest", muscles: ["chest", "triceps"], fedDir: "Leverage_Incline_Chest_Press"),
        .init(name: "Standing Cable Chest Flies (High to Low)", bodyPart: "Chest", muscles: ["chest"], fedDir: "Cable_Crossover"),
        .init(name: "Assisted Dips", bodyPart: "Chest", muscles: ["chest", "triceps"], fedDir: "Dips_-_Chest_Version"),
        .init(name: "Banded Pushups", bodyPart: "Chest", muscles: ["chest", "triceps"], fedDir: "Band_Push_Up"),
        .init(name: "Box Pushups", bodyPart: "Chest", muscles: ["chest", "triceps"], fedDir: "Incline_Push-Up"),
        .init(name: "Tall Side Pushups", bodyPart: "Chest", muscles: ["chest", "triceps"]),
        .init(name: "Floor Dumbbell Press", bodyPart: "Chest", muscles: ["chest", "triceps"], fedDir: "Floor_Press"),
        .init(name: "Seated Cable Chest Fly", bodyPart: "Chest", muscles: ["chest"], fedDir: "Flat_Bench_Cable_Flyes"),
        // Core
        .init(name: "Crunch Machine", bodyPart: "Core", muscles: ["abdominals"], fedDir: "Ab_Crunch_Machine"),
        .init(name: "Yoga Ball Pike", bodyPart: "Core", muscles: ["abdominals"], fedDir: "Exercise_Ball_Pike"),
        .init(name: "Woodchopper", bodyPart: "Core", muscles: ["abdominals"], fedDir: "Standing_Cable_Wood_Chop"),
        .init(name: "Paloff Press", bodyPart: "Core", muscles: ["abdominals"], fedDir: "Pallof_Press"),
        .init(name: "Copenhagen Planks", bodyPart: "Core", muscles: ["abdominals", "adductors"], fedDir: "Copenhagen_Plank"),
        .init(name: "Side Planks", bodyPart: "Core", muscles: ["abdominals"], fedDir: "Side_Bridge"),
        .init(name: "Dragon Flags", bodyPart: "Core", muscles: ["abdominals"], fedDir: "Dragon_Flag_Demo"),
        .init(name: "Plank Shoulder Taps", bodyPart: "Core", muscles: ["abdominals", "shoulders"], fedDir: "Plank"),
        .init(name: "Plank Reaches", bodyPart: "Core", muscles: ["abdominals", "shoulders"], fedDir: "Plank"),
        .init(name: "Plank Knee Slider", bodyPart: "Core", muscles: ["abdominals"], fedDir: "Plank"),
        .init(name: "Hollow Hold", bodyPart: "Core", muscles: ["abdominals"], fedDir: "Hollow_Hold"),
        .init(name: "Alternating V-Ups", bodyPart: "Core", muscles: ["abdominals"], fedDir: "Jackknife_Sit-Up"),
        .init(name: "Leg Lowers", bodyPart: "Core", muscles: ["abdominals"], fedDir: "Lying_Floor_Leg_Raise"),
        .init(name: "Lying Single Leg Raise", bodyPart: "Core", muscles: ["abdominals"], fedDir: "Alternate_Lying_Floor_Leg_Raise"),
        .init(name: "Sit-Ups", bodyPart: "Core", muscles: ["abdominals"], fedDir: "Sit-Up"),
        // Back
        .init(name: "High Rows", bodyPart: "Back", muscles: ["middle back", "lats"], fedDir: "Leverage_High_Row"),
        .init(name: "TRX Rows", bodyPart: "Back", muscles: ["middle back", "biceps"], fedDir: "Inverted_Row_with_Straps"),
        .init(name: "Assisted Pull-Ups", bodyPart: "Back", muscles: ["lats", "biceps"], fedDir: "Band_Assisted_Pull-Up"),
        .init(name: "Wide Pull-Ups", bodyPart: "Back", muscles: ["lats", "biceps"], fedDir: "Pullups"),
        .init(name: "Seated Supinating Rows", bodyPart: "Back", muscles: ["middle back", "biceps"], fedDir: "Seated_Cable_Rows"),
        .init(name: "Chest Supported Row", bodyPart: "Back", muscles: ["middle back"], fedDir: "Lying_T-Bar_Row"),
        .init(name: "Iso-Lateral Front Pulldown", bodyPart: "Back", muscles: ["lats", "biceps"], fedDir: "Wide-Grip_Lat_Pulldown"),
        .init(name: "Wide Cable Pulldown", bodyPart: "Back", muscles: ["lats"], fedDir: "Wide-Grip_Lat_Pulldown"),
        .init(name: "Close-Grip Pulldown", bodyPart: "Back", muscles: ["lats", "biceps"], fedDir: "Close-Grip_Front_Lat_Pulldown"),
        .init(name: "Bar Hang", bodyPart: "Back", muscles: ["forearms", "lats"], fedDir: "Dead_Hang"),
        .init(name: "Cable Rear Delt Fly", bodyPart: "Shoulders", muscles: ["shoulders", "middle back"], fedDir: "Seated_Bent-Over_Rear_Delt_Raise"),
        // Arms
        .init(name: "Wrist Extension", bodyPart: "Arms", muscles: ["forearms"], fedDir: "Seated_Palms-Down_Barbell_Wrist_Curl"),
        .init(name: "Wrist Flexion", bodyPart: "Arms", muscles: ["forearms"], fedDir: "Palms-Up_Barbell_Wrist_Curl_Over_A_Bench"),
        .init(name: "Barbell Wrist Rolls", bodyPart: "Arms", muscles: ["forearms"], fedDir: "Wrist_Roller"),
        .init(name: "Plate Pinches", bodyPart: "Arms", muscles: ["forearms"]),
        .init(name: "Crossbody Hammer Curls", bodyPart: "Arms", muscles: ["biceps", "forearms"], fedDir: "Cross_Body_Hammer_Curl"),
        .init(name: "Overhead Tricep Extensions", bodyPart: "Arms", muscles: ["triceps"], fedDir: "Standing_Dumbbell_Triceps_Extension"),
        .init(name: "Cable Tricep Extensions", bodyPart: "Arms", muscles: ["triceps"], fedDir: "Triceps_Pushdown"),
        .init(name: "Cable Tricep Pushdown", bodyPart: "Arms", muscles: ["triceps"], fedDir: "Triceps_Pushdown"),
        .init(name: "Reverse Curls", bodyPart: "Arms", muscles: ["biceps", "forearms"], fedDir: "Reverse_Barbell_Curl"),
        .init(name: "Seated Incline Bicep Curl", bodyPart: "Arms", muscles: ["biceps"], fedDir: "Incline_Dumbbell_Curl"),
        // Legs
        .init(name: "Bulgarian Split Squat", bodyPart: "Legs", muscles: ["quadriceps", "glutes"], fedDir: "Dumbbell_Bulgarian_Split_Squat"),
        .init(name: "Box Bulgarian Split Squat", bodyPart: "Legs", muscles: ["quadriceps", "glutes"], fedDir: "Dumbbell_Bulgarian_Split_Squat"),
        .init(name: "Heavy Suitcase Carries", bodyPart: "Full Body", muscles: ["forearms", "traps"], fedDir: "Suitcase_Carry"),
        .init(name: "Hip Abduction Machine", bodyPart: "Legs", muscles: ["abductors"], fedDir: "Thigh_Abductor"),
        .init(name: "Hip Adduction Machine", bodyPart: "Legs", muscles: ["adductors"], fedDir: "Thigh_Adductor"),
        .init(name: "Seated Hamstring Curl", bodyPart: "Legs", muscles: ["hamstrings"], fedDir: "Seated_Leg_Curl"),
        .init(name: "Single Leg Deadlift", bodyPart: "Legs", muscles: ["hamstrings", "glutes"], fedDir: "Kettlebell_One-Legged_Deadlift"),
        .init(name: "Single-Leg RDL", bodyPart: "Legs", muscles: ["hamstrings", "glutes"], fedDir: "Kettlebell_One-Legged_Deadlift"),
        // Package III (resistance band program) gaps — no free-exercise-db
        // band analog. Pose pairs were sourced from the web (operator-approved,
        // 2026-07-09) and dropped into Drift/ExercisePoses under minted
        // FED-style dir names; fedDir here is purely a bundle key — the URL
        // it expands to is never fetched (see PoseCrossfadeView).
        // Operator does this with the band looped behind the neck — the
        // bundled Band Good Morning photos show exactly that setup.
        .init(name: "B-Stance RDL", bodyPart: "Legs", muscles: ["hamstrings", "glutes"], fedDir: "Band_Good_Morning"),
        .init(name: "Banded Bent-Over Row", bodyPart: "Back", muscles: ["middle back", "lats", "biceps"], fedDir: "Banded_Bent_Over_Row"),
        .init(name: "Banded Bicep Curl", bodyPart: "Arms", muscles: ["biceps"], fedDir: "Banded_Bicep_Curl"),
        .init(name: "Cossack Squats", bodyPart: "Legs", muscles: ["quadriceps", "adductors"], fedDir: "Cossack_Squat"),
        .init(name: "Single Leg Hip Thrust", bodyPart: "Legs", muscles: ["glutes", "hamstrings"], fedDir: "Single_Leg_Glute_Bridge"),
        .init(name: "Walking Lunges", bodyPart: "Legs", muscles: ["quadriceps", "glutes"], fedDir: "Bodyweight_Walking_Lunge"),
        .init(name: "Heels Elevated Squat Hold", bodyPart: "Legs", muscles: ["quadriceps"], fedDir: "Heel_Elevated_Goblet_Squat"),
        .init(name: "Single Leg Calf Raise", bodyPart: "Legs", muscles: ["calves"], fedDir: "Calf_Raise_On_A_Dumbbell"),
        // Shoulders
        .init(name: "Cable Lateral Raise", bodyPart: "Shoulders", muscles: ["shoulders"], fedDir: "Standing_Cable_Lateral_Raise"),
        .init(name: "Arnold Press", bodyPart: "Shoulders", muscles: ["shoulders", "triceps"], fedDir: "Arnold_Dumbbell_Press"),
        .init(name: "Front Raise", bodyPart: "Shoulders", muscles: ["shoulders"], fedDir: "Front_Dumbbell_Raise"),
        .init(name: "Shrug", bodyPart: "Shoulders", muscles: ["traps"], fedDir: "Barbell_Shrug"),
        .init(name: "Incline Y Raise", bodyPart: "Shoulders", muscles: ["shoulders", "middle back"], fedDir: "Incline_Y_Raise"),
        .init(name: "Around the World", bodyPart: "Shoulders", muscles: ["shoulders", "chest"]),
        .init(name: "Kneeling Landmine Press", bodyPart: "Shoulders", muscles: ["shoulders", "triceps"], fedDir: "Kneeling_Landmine_Press"),
        // Common aliases for better search — now with poses (#929)
        .init(name: "Goblet Squat", bodyPart: "Legs", muscles: ["quadriceps", "glutes"], fedDir: "Goblet_Squat"),
        .init(name: "Sumo Squat", bodyPart: "Legs", muscles: ["quadriceps", "adductors"], fedDir: "Plie_Dumbbell_Squat"),
        .init(name: "Step-Ups", bodyPart: "Legs", muscles: ["quadriceps", "glutes"], fedDir: "Barbell_Step_Ups"),
        .init(name: "Glute Bridge", bodyPart: "Legs", muscles: ["glutes"], fedDir: "Butt_Lift_Bridge"),
        .init(name: "Wall Sit", bodyPart: "Legs", muscles: ["quadriceps"], fedDir: "Wall_Sit"),
        .init(name: "Skull Crushers", bodyPart: "Arms", muscles: ["triceps"], fedDir: "Lying_Triceps_Press"),
        .init(name: "Rope Pushdown", bodyPart: "Arms", muscles: ["triceps"], fedDir: "Triceps_Pushdown_-_Rope_Attachment"),
        .init(name: "Cable Fly", bodyPart: "Chest", muscles: ["chest"], fedDir: "Cable_Crossover"),
        .init(name: "Plank", bodyPart: "Core", muscles: ["abdominals"], fedDir: "Plank"),
        .init(name: "Dead Bug", bodyPart: "Core", muscles: ["abdominals"], fedDir: "Dead_Bug"),
        .init(name: "Pull-Up", bodyPart: "Back", muscles: ["lats", "biceps"], fedDir: "Pullups"),
        .init(name: "Burpee", bodyPart: "Full Body", muscles: ["chest", "quadriceps"], fedDir: "Burpee_Demo"),
        // Full Body
        .init(name: "Ab Wheel Rollout", bodyPart: "Core", muscles: ["abdominals"], fedDir: "Ab_Roller"),
        .init(name: "Battle Ropes", bodyPart: "Full Body", muscles: ["shoulders", "forearms"], fedDir: "Battling_Ropes"),
        .init(name: "Box Jump", bodyPart: "Legs", muscles: ["quadriceps", "glutes"], fedDir: "Box_Jump_Multiple_Response"),
        .init(name: "Mountain Climber", bodyPart: "Core", muscles: ["abdominals", "quadriceps"], fedDir: "Mountain_Climbers"),
        .init(name: "Machine Chest Press", bodyPart: "Chest", muscles: ["chest", "triceps"], fedDir: "Machine_Bench_Press"),
        .init(name: "Machine Shoulder Press", bodyPart: "Shoulders", muscles: ["shoulders"], fedDir: "Machine_Shoulder_Military_Press"),
        .init(name: "Seated Cable Row", bodyPart: "Back", muscles: ["middle back", "biceps"], fedDir: "Seated_Cable_Rows"),
        .init(name: "Spider Curl", bodyPart: "Arms", muscles: ["biceps"], fedDir: "Spider_Curl"),
        .init(name: "Cable Tricep Kickback", bodyPart: "Arms", muscles: ["triceps"], fedDir: "Cable_Tricep_Kickback"),
        .init(name: "Ball Slams", bodyPart: "Full Body", muscles: ["abdominals", "shoulders"], fedDir: "Overhead_Slam"),
        .init(name: "Sled Push", bodyPart: "Full Body", muscles: ["quadriceps", "glutes"], fedDir: "Sled_Push"),
        .init(name: "Air Bike", bodyPart: "Full Body", muscles: ["quadriceps"], fedDir: "Air_Bike"),
        // Common names used in templates (exist in DB under longer names)
        .init(name: "Deadlift", bodyPart: "Legs", muscles: ["lower back", "glutes", "hamstrings"], fedDir: "Barbell_Deadlift"),
        .init(name: "Dips", bodyPart: "Chest", muscles: ["chest", "triceps"], fedDir: "Dips_-_Chest_Version"),
        .init(name: "Push-Ups", bodyPart: "Chest", muscles: ["chest", "triceps"], fedDir: "Pushups"),
        .init(name: "Lat Pulldown", bodyPart: "Back", muscles: ["lats", "biceps"], fedDir: "Wide-Grip_Lat_Pulldown"),
        .init(name: "Shoulder Press", bodyPart: "Shoulders", muscles: ["shoulders", "triceps"], fedDir: "Dumbbell_Shoulder_Press"),
        .init(name: "Lateral Raise", bodyPart: "Shoulders", muscles: ["shoulders"], fedDir: "Side_Lateral_Raise"),
        .init(name: "Bicep Curl", bodyPart: "Arms", muscles: ["biceps"], fedDir: "Dumbbell_Bicep_Curl"),
        .init(name: "Tricep Extension", bodyPart: "Arms", muscles: ["triceps"], fedDir: "Triceps_Pushdown"),
        .init(name: "Upright Row", bodyPart: "Shoulders", muscles: ["shoulders", "traps"], fedDir: "Upright_Barbell_Row"),
        .init(name: "Bent-Over Row", bodyPart: "Back", muscles: ["middle back", "lats"], fedDir: "Bent_Over_Barbell_Row"),
        .init(name: "Dumbbell Row", bodyPart: "Back", muscles: ["middle back", "lats"], fedDir: "One-Arm_Dumbbell_Row"),
        .init(name: "Leg Raise", bodyPart: "Core", muscles: ["abdominals"], fedDir: "Flat_Bench_Lying_Leg_Raise"),
        .init(name: "Back Extension", bodyPart: "Back", muscles: ["lower back", "glutes"], fedDir: "Hyperextensions_Back_Extensions"),
        .init(name: "Calf Raises", bodyPart: "Legs", muscles: ["calves"], fedDir: "Standing_Calf_Raises"),
        // Additional common exercises
        .init(name: "Chest Press Machine", bodyPart: "Chest", muscles: ["chest", "triceps"], fedDir: "Machine_Bench_Press"),
        .init(name: "Pec Deck", bodyPart: "Chest", muscles: ["chest"], fedDir: "Butterfly"),
        .init(name: "Preacher Curl Machine", bodyPart: "Arms", muscles: ["biceps"], fedDir: "Machine_Preacher_Curls"),
        .init(name: "EZ Bar Curl", bodyPart: "Arms", muscles: ["biceps"], fedDir: "EZ-Bar_Curl"),
        .init(name: "Turkish Get-Up", bodyPart: "Full Body", muscles: ["shoulders", "abdominals"], fedDir: "Kettlebell_Turkish_Get-Up_Squat_style"),
        .init(name: "Chin-Up", bodyPart: "Back", muscles: ["lats", "biceps"], fedDir: "Chin-Up"),
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

    // MARK: - Package IV (original curated programs; was Package I)

    static var packageIV: [WorkoutTemplate] {
        program4 + program3 + program2 + program1
    }

    // MARK: - Package I (Cindy full-body program, trainer text received 2026-07-11)
    //
    // "Hi Ashish! Here's your HW" — leg press, dumbbell chest press, TRX rows,
    // hanging leg raises (AMRAP, control the descent), back extension; forearm
    // work after if there's time. All names resolve: catalog rows for four,
    // the registered "TRX Rows" / "Wrist Flexion" / "Wrist Extension" customs
    // for the rest.

    static var packageI: [WorkoutTemplate] {
        [
            WorkoutTemplate(name: "Cindy Full Body", exercisesJson: json([
                e("Leg Press", notes: "8-10 reps"),
                e("Dumbbell Bench Press", notes: "8-10 reps — dumbbell chest press"),
                e("TRX Rows", notes: "8-12 reps"),
                e("Hanging Leg Raise", notes: "AMRAP — control the descent"),
                e("Hyperextensions (Back Extensions)", notes: "8-12 reps"),
                e("Wrist Extension", rest: 45, notes: "optional — if time, 10-15 reps"),
                e("Wrist Flexion", rest: 45, notes: "optional — if time, 10-15 reps"),
            ]), createdAt: now),
        ]
    }

    // MARK: - Package II (Srijith program, imported 2026-07-07)

    static var packageII: [WorkoutTemplate] {
        [
            WorkoutTemplate(name: "Total Body Free Weights", exercisesJson: json([
                w("Down Dog to Plank", sets: 1, notes: "10 reps"),
                w("World's Greatest Stretch", sets: 1, notes: "10 per side"),
                e("Plank Shoulder Taps", rest: 60, notes: "20 taps, engage core"),
                e("Single Leg Hip Thrust", rest: 75, notes: "10-12 per side, hips level, use glute"),
                e("Front Squat", sets: 4, rest: 105, notes: "10-12 reps, sit to box, band optional"),
                e("Kneeling Landmine Press", sets: 4, rest: 105, notes: "6-8 per side, kneeling"),
                e("Iso-Lateral Front Pulldown", sets: 4, rest: 90, notes: "8-10 reps, plate loaded"),
                e("Seated Incline Bicep Curl", rest: 75, notes: "13-15 reps, 60° bench"),
                e("Seated Calf Raise", rest: 60, notes: "12 reps — optional"),
                e("Sled Push", sets: 1, rest: 60, notes: "4 pushes or 1 mile air bike — optional cardio"),
            ]), createdAt: now),

            WorkoutTemplate(name: "Total Body Dumbbells", exercisesJson: json([
                w("World's Greatest Stretch", sets: 1, notes: "hold 45-60 secs"),
                w("Dead Bug", sets: 3, notes: "12-20 reps, with band and stick"),
                w("Side Planks", notes: "20-25 secs"),
                e("Banded Pushups", sets: 4, rest: 90, notes: "5-8 reps, at barbell rack"),
                e("Bar Hang", sets: 4, rest: 60, notes: "10 secs, hold core tight"),
                e("Box Bulgarian Split Squat", rest: 90, notes: "6-10 per side, control with standing leg"),
                e("Romanian Deadlift", sets: 4, rest: 105, notes: "8 reps — lat engagement, hips back"),
                e("Close-Grip Pulldown", sets: 4, rest: 90, notes: "8 reps, or seated plate row"),
                e("Incline Y Raise", rest: 75, notes: "8-12 reps, 30° bench, 2-5 lbs"),
                e("Skull Crushers", rest: 45, notes: "12-15 reps — optional"),
                e("Wall Sit", sets: 1, rest: 60, notes: "35-45 secs"),
            ]), createdAt: now),

            WorkoutTemplate(name: "Dumbbell Circuits", exercisesJson: json([
                e("Walking Lunges", sets: 4, rest: 45, notes: "Circuit 1 — 12 alternating"),
                e("Plank Reaches", sets: 4, rest: 45, notes: "Circuit 1 — 20-30 reaches"),
                e("Dumbbell Row", rest: 45, notes: "Circuit 1 — 10 per side, floor, lats"),
                e("Floor Dumbbell Press", sets: 4, rest: 45, notes: "Circuit 2 — 10-12 reps"),
                e("Sit-Ups", sets: 4, rest: 45, notes: "Circuit 2 — 8-10, feet under dumbbells"),
                e("Lying Single Leg Raise", rest: 45, notes: "Circuit 2 — 12-15 per side"),
                e("Wall Sit", sets: 4, rest: 45, notes: "Circuit 3 — 20 secs"),
                e("Around the World", sets: 4, rest: 45, notes: "Circuit 3 — 10 reps, light dumbbells"),
                e("Bicep Curl", sets: 4, rest: 45, notes: "Circuit 3 — 8-10 reps"),
            ]), createdAt: now),

            WorkoutTemplate(name: "Total Body Strength", exercisesJson: json([
                w("90/90 Switches", sets: 1, notes: "ankle rocks + 90/90 hips, 10 each"),
                w("World's Greatest Stretch", sets: 1, notes: "stretch chest, hamstring, glute, hip flexor"),
                e("Single-Leg RDL", rest: 75, notes: "6-8 per side, cross arms, back flat"),
                e("Tall Side Pushups", rest: 60, notes: "12-15 reps — hips forward, glutes squeezed"),
                e("Ball Slams", rest: 60, notes: "20-25 slams, 10-12 lbs"),
                e("Walking Lunges", rest: 75, notes: "20 reps, chest upright, HR 140-160"),
                e("Wide Cable Pulldown", rest: 75, notes: "12-15 reps"),
                e("Plank Knee Slider", rest: 60, notes: "10-15 reps"),
                e("Cable Tricep Pushdown", rest: 60, notes: "12-15 reps"),
                e("Wall Sit", sets: 2, rest: 60, notes: "15-30 secs"),
                e("Seated Hamstring Curl", rest: 60, notes: "12-15 reps, or lying leg curl"),
            ]), createdAt: now),

            WorkoutTemplate(name: "Pull Day", exercisesJson: json([
                w("World's Greatest Stretch", sets: 1, notes: "10 per side"),
                w("Down Dog to Plank", sets: 1, notes: "doorway chest stretch 30 secs per side"),
                e("Assisted Pull-Ups", rest: 90, notes: "12-15 reps, or wide pulldown"),
                e("Seated Hamstring Curl", rest: 45, notes: "10-12 reps, or lying leg curl"),
                e("Seated Cable Row", rest: 45, notes: "10-12 reps"),
                e("Cable Rear Delt Fly", rest: 30, notes: "12-20 reps, light — superset with calf raises"),
                e("Single Leg Calf Raise", rest: 30, notes: "10-15 per side, on the floor"),
                e("Air Bike", sets: 1, rest: 60, notes: "0.5 mile under 3.5 min, no rest; optional 1 mile finish"),
            ]), createdAt: now),

            WorkoutTemplate(name: "Push Day", exercisesJson: json([
                w("World's Greatest Stretch", sets: 1, notes: "10 per side"),
                w("Goblet Squat", sets: 1, rest: 20, notes: "10 bodyweight squats + hamstring stretch"),
                e("Goblet Squat", rest: 30, notes: "12-15 reps, sit to box — superset with pushups"),
                e("Box Pushups", rest: 30, notes: "10-15 reps"),
                e("Step-Ups", rest: 30, notes: "12-15 per leg"),
                e("Dead Bug", rest: 30, notes: "10-20 leg extensions, with yoga ball, legs only"),
                e("Seated Cable Chest Fly", sets: 2, rest: 45, notes: "20-25 reps, light"),
                e("Cable Tricep Pushdown", sets: 2, rest: 45, notes: "12-25 reps"),
            ]), createdAt: now),
        ]
    }

    // MARK: - Package III (whiteboard resistance band program, imported 2026-07-09)
    //
    // Band-specific catalog entries are preferred (they carry honest band
    // pose photos); the four customs with no free-exercise-db band analog
    // use web-sourced pose pairs bundled under minted asset names (see the
    // custom-exercise registry note).

    static var packageIII: [WorkoutTemplate] {
        [
            WorkoutTemplate(name: "Resistance Band A", exercisesJson: json([
                e("Bulgarian Split Squat", notes: "12 per leg"),
                e("Push-Ups", notes: "12-15 reps"),
                e("Banded Bent-Over Row", notes: "15 reps"),
                e("Shoulder Press - With Bands", notes: "15-20 reps"),
                e("Banded Bicep Curl", notes: "15-20 reps"),
            ]), createdAt: now),

            WorkoutTemplate(name: "Resistance Band B", exercisesJson: json([
                e("B-Stance RDL", notes: "12 per leg"),
                e("Cross Over - With Bands", notes: "15-20 reps, band chest fly"),
                e("Band Pull Apart", notes: "15 reps"),
                e("Banded Lateral Walks", notes: "20 per leg"),
                e("Speed Band Overhead Triceps", notes: "15-20 reps, tricep extension"),
            ]), createdAt: now),
        ]
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
            ]), createdAt: now),

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
            ]), createdAt: now),

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
            ]), createdAt: now),

            WorkoutTemplate(name: "Day 4 - Lower/Forearms", exercisesJson: json([
                w("Ladder Drill", sets: 1, rest: 30, notes: "2-5 mins"),
                w("90/90 Hip Stretch + Extensions", notes: "2x10"),
                w("Banded Shoulder Rotations", notes: "2x10"),
                w("Banded Pull Aparts (Palms Up)", notes: "2x10"),
                w("Banded Pull Aparts (Palms Down)", notes: "2x10"),
                e("Deadlift", rest: 150, notes: "2-3x5-8 reps"),
                e("Assisted Pull-Ups", rest: 150, notes: "5-8 reps"),
                e("Bulgarian Split Squat", rest: 120, notes: "8-10 reps"),
                e("TRX Rows", rest: 105, notes: "8-12 reps"),
                e("Hammer Curl", rest: 75, notes: "8-15 reps"),
                e("Barbell Wrist Rolls", rest: 75, notes: "10-15 reps"),
                e("Plate Pinches", rest: 75, notes: "20-30 secs"),
            ]), createdAt: now),
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
                e("Leg Extension", rest: 75, notes: "3x8-12"),
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
                e("Bulgarian Split Squat", rest: 105, notes: "3x8-12"),
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
                e("Bulgarian Split Squat", rest: 105, notes: "3x8-12"),
                e("Leg Extension", rest: 75, notes: "3x8-12"),
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
                e("Bulgarian Split Squat", rest: 105, notes: "3x8-12"),
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
