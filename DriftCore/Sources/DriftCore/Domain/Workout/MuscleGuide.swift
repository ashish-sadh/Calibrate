import Foundation

/// **Know Your Muscles** — the app's anatomy knowledge base.
///
/// Content is the operator's Drift Guide, Chapter One (2026-08-02), encoded
/// rather than paraphrased: the plain-English name, what the muscle actually
/// does, the parts it splits into, and how it's trained. The guide's own thesis
/// is the one worth keeping — "every muscle is just a rope that pulls on bone" —
/// and every line here is written to survive being read by someone who has
/// never heard the Latin.
///
/// This is a KNOWLEDGE BASE, not a script. `MuscleGuide` knows things;
/// `MuscleEducation` decides whether saying one of them is welcome. Keeping
/// those apart is what stops the coach lecturing — the operator's constraint was
/// explicit: "Don't force education but know when you bring and tell them".
public enum MuscleGuide {

    // MARK: - How a muscle works

    /// The four ideas that apply to every muscle in the body.
    ///
    /// Worth teaching ONCE, early, because they make every later explanation
    /// land: someone who knows a muscle can only pull already understands why
    /// there's no such thing as a "pushing" muscle, and why we train opposites.
    public struct Principle: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        /// The technical framing, for the person who wants it. Never leads.
        public let term: String?
        public let plain: String
    }

    public static let principles: [Principle] = [
        .init(id: "pull", title: "It can only pull", term: nil,
              plain: "A muscle shortens to pull two bones closer together, then relaxes. It never pushes — even when you're pressing a bar overhead, something is pulling your arm straight."),
        .init(id: "anchors", title: "Two anchor points", term: "origin & insertion",
              plain: "Each end attaches to bone. One end is the anchored one, the other is the end that moves — and which is which can flip depending on the exercise."),
        .init(id: "pairs", title: "They work in pairs", term: "agonist & antagonist",
              plain: "Biceps bend the elbow, triceps straighten it. When one contracts its partner relaxes — which is why training only one side of a joint eventually catches up with you."),
        .init(id: "heads", title: "One name, many parts", term: "heads",
              plain: "Big muscles split into heads or regions that pull different sections into one motion. Hitting all of them takes more than one movement — that's why your chest day isn't just bench press."),
    ]

    // MARK: - Lookup

    /// Everything the guide knows about one muscle.
    public static func info(for driftMuscle: String) -> MuscleInfo? {
        MuscleInfo.info(for: driftMuscle)
    }

    /// The library slugs to light up on the figure for a Drift muscle — the
    /// diagram half of a lesson.
    public static func slugs(for driftMuscle: String) -> [String] {
        BodyDiagram.librarySlugs(forDriftMuscle: driftMuscle)
    }
}

/// Plain-English education content for the catalog muscles — the reference
/// design shows the diagram beside a name + function line, and the guide adds
/// the parts and the training.
public struct MuscleInfo: Sendable, Equatable {
    public let displayName: String
    public let latinName: String
    /// What people actually call it in a gym. Nil where the plain name is
    /// already what everyone says ("Calves" has no nickname worth printing).
    public let nickname: String?
    public let function: String
    /// A movement from outside the gym that uses it. The line that makes an
    /// abstract muscle concrete — "curling a grocery bag up to your shoulder"
    /// teaches more than "elbow flexion" ever does.
    public let everyday: String?
    /// The parts it splits into, and what each one does.
    public let heads: [Head]
    /// How it's actually trained.
    public let trainedBy: [String]

    public struct Head: Sendable, Equatable {
        public let name: String
        public let role: String
        public init(_ name: String, _ role: String) {
            self.name = name
            self.role = role
        }
    }

    public init(displayName: String, latinName: String, nickname: String? = nil,
                function: String, everyday: String? = nil,
                heads: [Head] = [], trainedBy: [String] = []) {
        self.displayName = displayName
        self.latinName = latinName
        self.nickname = nickname
        self.function = function
        self.everyday = everyday
        self.heads = heads
        self.trainedBy = trainedBy
    }

    public static func info(for driftMuscle: String) -> MuscleInfo? {
        infos[driftMuscle.lowercased()]
    }

    /// Every muscle the guide covers, for tests and for the browsable version.
    public static var allCovered: [String] { Array(infos.keys).sorted() }

    private static let infos: [String: MuscleInfo] = [
        "abdominals": .init(
            displayName: "Abs", latinName: "rectus abdominis", nickname: "abs",
            function: "Curls your torso forward and braces your core",
            everyday: "Its real job isn't crunching — it's bracing your spine so it stays solid while everything else moves",
            heads: [.init("Top", "emphasised by crunches"),
                    .init("Bottom", "emphasised by leg raises")],
            trainedBy: ["crunches", "leg raises", "any heavy compound you brace for"]),
        "abductors": .init(
            displayName: "Abductors", latinName: "gluteus medius & minimus",
            function: "Move your leg away from your body",
            everyday: "Steadying your hips every time you stand on one leg",
            trainedBy: ["lateral band walks", "hip abduction"]),
        "adductors": .init(
            displayName: "Adductors", latinName: "adductor group", nickname: "inner thigh",
            function: "Pull your legs together",
            trainedBy: ["sumo squats", "adduction machine", "cossack squats"]),
        "biceps": .init(
            displayName: "Biceps", latinName: "biceps brachii", nickname: "bis",
            function: "Bend your elbow and turn your palm up",
            everyday: "Curling a grocery bag up toward your shoulder",
            heads: [.init("Long head", "the outer one — gives the peak"),
                    .init("Short head", "the inner one — adds thickness"),
                    .init("Brachialis", "underneath, pushes the whole arm up")],
            trainedBy: ["curls", "chin-ups", "hammer curls"]),
        "calves": .init(
            displayName: "Calves", latinName: "gastrocnemius & soleus",
            function: "Point your toes and push off the ground",
            everyday: "Every step, and every jump you've ever landed",
            heads: [.init("Gastrocnemius", "the diamond you can see — straight-leg raises"),
                    .init("Soleus", "deeper and flatter — seated, bent-knee raises")],
            trainedBy: ["standing calf raises", "seated calf raises"]),
        "chest": .init(
            displayName: "Chest", latinName: "pectoralis major", nickname: "pecs",
            function: "Pushes your arms forward and together",
            everyday: "Shoving a heavy door open",
            heads: [.init("Upper", "incline movements"),
                    .init("Middle", "flat pressing"),
                    .init("Lower", "dips and decline")],
            trainedBy: ["bench press", "push-ups", "dips", "flyes"]),
        "forearms": .init(
            displayName: "Forearms", latinName: "flexors & extensors",
            function: "Grip strength and wrist control",
            everyday: "Carrying the shopping in one trip — grip is usually what gives out first",
            heads: [.init("Flexors", "wrist curls"),
                    .init("Brachioradialis", "reverse and hammer curls")],
            trainedBy: ["carries", "wrist curls", "hanging"]),
        "glutes": .init(
            displayName: "Glutes", latinName: "gluteus maximus", nickname: "glutes",
            function: "Drive your hips forward — stand, jump, climb",
            everyday: "Your single most powerful muscle: standing tall, climbing stairs, sprinting",
            heads: [.init("Glute max", "the driver — hip thrusts, squats, RDLs"),
                    .init("Glute medius", "steadies the hip — lateral band walks")],
            trainedBy: ["hip thrusts", "squats", "RDLs"]),
        "hamstrings": .init(
            displayName: "Hamstrings", latinName: "biceps femoris group", nickname: "hams",
            function: "Bend your knee and pull your hip back",
            everyday: "Slowing your leg down every time you run — which is why they tear when they're untrained",
            trainedBy: ["RDLs", "leg curls", "good mornings"]),
        "lats": .init(
            displayName: "Lats", latinName: "latissimus dorsi", nickname: "lats",
            function: "Pull your arms down and toward you",
            everyday: "The wings that give a back its width — one of the largest muscles you own",
            heads: [.init("Upper fibres", "pull-ups and wide pulldowns"),
                    .init("Lower fibres", "rows, pulling toward the hip")],
            trainedBy: ["pull-ups", "pulldowns", "rows"]),
        "lower back": .init(
            displayName: "Lower Back", latinName: "erector spinae",
            function: "Keeps your spine upright and extends it",
            everyday: "Holding you up all day without being asked",
            trainedBy: ["deadlifts", "back extensions", "good mornings"]),
        "middle back": .init(
            displayName: "Middle Back", latinName: "rhomboids & mid-traps",
            function: "Squeeze your shoulder blades together",
            everyday: "The muscles that lose to a desk — and the ones that pull your posture back",
            trainedBy: ["rows", "band pull-aparts", "face pulls"]),
        "neck": .init(
            displayName: "Neck", latinName: "sternocleidomastoid",
            function: "Turns and tilts your head",
            trainedBy: ["neck curls", "carries"]),
        "obliques": .init(
            displayName: "Obliques", latinName: "internal & external obliques",
            function: "Twist your torso and bend it sideways",
            everyday: "Reaching across to grab something off the passenger seat",
            trainedBy: ["Russian twists", "cable rotations", "suitcase carries"]),
        "quadriceps": .init(
            displayName: "Quads", latinName: "quadriceps femoris", nickname: "quads",
            function: "Straighten your knee — squat, run, kick",
            everyday: "Standing up out of a chair, and every stair you've climbed",
            trainedBy: ["squats", "leg press", "split squats"]),
        "shoulders": .init(
            displayName: "Shoulders", latinName: "deltoids", nickname: "delts",
            function: "Raise and rotate your arms in every direction",
            everyday: "Putting a suitcase in the overhead locker",
            heads: [.init("Front", "presses — overhead and forward"),
                    .init("Side", "raises out to the side, where width comes from"),
                    .init("Rear", "pulls the arm back — the posture one")],
            trainedBy: ["overhead press", "lateral raises", "face pulls"]),
        "traps": .init(
            displayName: "Traps", latinName: "trapezius",
            function: "Shrug, and hold your shoulder blades steady",
            everyday: "The diamond from your neck down to mid-back",
            heads: [.init("Upper", "shrugs the shoulders up"),
                    .init("Mid & lower", "pulls the blades down and together")],
            trainedBy: ["shrugs", "rows", "pull-aparts"]),
        "triceps": .init(
            displayName: "Triceps", latinName: "triceps brachii", nickname: "tris",
            function: "Straighten your elbow — every press finishes here",
            everyday: "Roughly two-thirds of your arm's size, more than the biceps — if you want bigger arms, this is the one",
            heads: [.init("Lateral head", "the outer one — gives the horseshoe"),
                    .init("Long head", "inner and back — most of the mass"),
                    .init("Medial head", "deep, steadies the rest")],
            trainedBy: ["dips", "close-grip press", "overhead extensions"]),
        "transverse abdominis": .init(
            displayName: "Deep Core", latinName: "transverse abdominis",
            function: "Wraps your middle like a corset and braces it",
            everyday: "A deep belt around your midsection that tightens before you lift anything heavy",
            trainedBy: ["planks", "dead bugs", "heavy compounds"]),
    ]
}
