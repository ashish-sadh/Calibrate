import Foundation

/// The anatomical body model powering Drift's muscle-highlight diagrams (#929).
/// Ported from react-native-body-highlighter (MIT, © 2022 ELABBASSI Hicham,
/// commit 15df9e2d) via `scripts/extract-body-highlighter.py` — the bundled
/// `bodyDiagram.json` contains four models (male/female × front/back) whose
/// paths are pre-normalized to absolute M/L/C/Z commands in a (0,0)-origin
/// viewBox, so the parser here stays tiny and fully Tier-0 testable.
///
/// Platform-neutral since #1064: paths are parsed into `SVGPath` command
/// lists (pure Doubles, no CoreGraphics), so the same model renders through
/// SwiftUI `Path` on iOS and Android alike.
public enum BodyDiagram {

    public enum Side: String, CaseIterable, Sendable { case front, back }
    public enum Gender: String, CaseIterable, Sendable { case male, female }

    public struct Model: Sendable {
        public let viewBoxWidth: Double
        public let viewBoxHeight: Double
        /// Body silhouette contours (stroked, not filled).
        public let outline: [SVGPath]
        /// Library muscle slug → filled region paths.
        public let muscles: [String: [SVGPath]]
    }

    // MARK: - Loading

    private struct RawDoc: Decodable {
        let models: [String: RawModel]
    }
    private struct RawModel: Decodable {
        let viewBox: [Double]
        let outline: [String]
        let muscles: [String: [String]]
    }

    /// All four models, parsed once. ~180KB JSON + ~320 paths — cheap.
    public static let models: [String: Model] = {
        guard let url = Bundle.module.url(forResource: "bodyDiagram", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let doc = try? JSONDecoder().decode(RawDoc.self, from: data) else {
            Log.app.error("bodyDiagram.json missing or unparseable — muscle diagrams disabled")
            return [:]
        }
        return doc.models.mapValues { raw in
            Model(
                viewBoxWidth: raw.viewBox[0],
                viewBoxHeight: raw.viewBox[1],
                outline: raw.outline.compactMap(SVGPathParser.parse),
                muscles: raw.muscles.mapValues { $0.compactMap(SVGPathParser.parse) }
            )
        }
    }()

    public static func model(gender: Gender, side: Side) -> Model? {
        models["\(gender.rawValue)\(side == .front ? "Front" : "Back")"]
    }

    /// Figure to render for THIS user: follows profile sex (Settings →
    /// Profile), male when unset (2026-07-09 inclusivity call — women should
    /// see a female figure on the recovery map and muscle diagrams).
    /// Female slug coverage matches male for every real muscle. The female
    /// BACK artwork has no separate `head`/`ankles` slivers because its
    /// figure draws those areas as `hair` and `feet` (verified against the
    /// pinned upstream source) — nothing is missing visually, and no Drift
    /// muscle ever maps to those cosmetic slugs.
    public static var userGender: Gender {
        // Decodes only the sex field of the TDEE config — TDEEEstimator is
        // MainActor-isolated and this must stay callable from any context.
        struct SexProbe: Decodable { let sex: TDEEEstimator.Sex? }
        guard let data = UserDefaults.standard.data(forKey: "drift_tdee_config"),
              let probe = try? JSONDecoder().decode(SexProbe.self, from: data) else { return .male }
        return probe.sex == .female ? .female : .male
    }

    // MARK: - Drift muscle slugs → library regions

    /// Maps Drift's 17 exercise-catalog muscle names onto library slugs.
    /// Documented approximations: `lats` and `middle back` both render as the
    /// library's single `upper-back` region; `abductors` has NO region in the
    /// v3 data (README claims one — stale) and returns [] → callers highlight
    /// nothing for it rather than lying.
    public static func librarySlugs(forDriftMuscle muscle: String) -> [String] {
        switch muscle.lowercased() {
        case "abdominals": ["abs"]
        case "adductors": ["adductors"]
        case "biceps": ["biceps"]
        case "calves": ["calves"]
        case "chest": ["chest"]
        case "forearms": ["forearm"]
        case "glutes": ["gluteal"]
        case "hamstrings": ["hamstring"]
        case "lats": ["upper-back"]
        case "lower back": ["lower-back"]
        case "middle back": ["upper-back"]
        case "neck": ["neck"]
        case "quadriceps": ["quadriceps"]
        case "shoulders": ["deltoids"]
        case "traps": ["trapezius"]
        case "triceps": ["triceps"]
        case "abductors": []  // no region in source data — documented gap
        default: []
        }
    }

    /// Which side shows a Drift muscle best (drives the default side toggle:
    /// pick the side that displays the most primary muscles).
    public static func preferredSide(forDriftMuscle muscle: String) -> Side {
        switch muscle.lowercased() {
        case "lats", "middle back", "lower back", "glutes", "hamstrings",
             "calves", "traps", "triceps":
            .back
        default:
            .front
        }
    }

    /// The side to show for an exercise: majority vote of its primary
    /// muscles' preferred sides (front wins ties — the familiar view).
    public static func preferredSide(primaryMuscles: [String]) -> Side {
        let backVotes = primaryMuscles.filter { preferredSide(forDriftMuscle: $0) == .back }.count
        return backVotes * 2 > primaryMuscles.count ? .back : .front
    }
}

/// A parsed body-model path: absolute M/L/C/Z commands plus precomputed
/// bounds. Pure value data — the SwiftUI layer turns commands into `Path`.
public struct SVGPath: Sendable, Equatable {
    public enum Command: Sendable, Equatable {
        case move(x: Double, y: Double)
        case line(x: Double, y: Double)
        case curve(c1x: Double, c1y: Double, c2x: Double, c2y: Double, x: Double, y: Double)
        case close
    }

    /// Control-point-inclusive bounds — the same semantics as
    /// `CGPath.boundingBox`, which the extraction-contract tests pin.
    public struct Bounds: Sendable, Equatable {
        public let minX: Double
        public let minY: Double
        public let maxX: Double
        public let maxY: Double
    }

    public let commands: [Command]
    public let bounds: Bounds
}

/// Parses the pre-normalized path strings in bodyDiagram.json: absolute
/// M/L/C/Z only (H,V,Q,S,T,A were resolved at extraction time).
public enum SVGPathParser {

    public static func parse(_ d: String) -> SVGPath? {
        var commands: [SVGPath.Command] = []
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        var i = d.startIndex

        func number() -> Double? {
            while i < d.endIndex, d[i] == " " { i = d.index(after: i) }
            let start = i
            if i < d.endIndex, d[i] == "-" { i = d.index(after: i) }
            var sawDigit = false
            while i < d.endIndex, d[i].isNumber || d[i] == "." {
                sawDigit = true
                i = d.index(after: i)
            }
            guard sawDigit, let v = Double(d[start..<i]) else { return nil }
            return v
        }

        func point() -> (x: Double, y: Double)? {
            guard let x = number(), let y = number() else { return nil }
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
            return (x, y)
        }

        while i < d.endIndex {
            let c = d[i]
            i = d.index(after: i)
            switch c {
            case "M":
                guard let p = point() else { return nil }
                commands.append(.move(x: p.x, y: p.y))
            case "L":
                guard let p = point() else { return nil }
                commands.append(.line(x: p.x, y: p.y))
            case "C":
                guard let c1 = point(), let c2 = point(), let p = point() else { return nil }
                commands.append(.curve(c1x: c1.x, c1y: c1.y, c2x: c2.x, c2y: c2.y, x: p.x, y: p.y))
            case "Z":
                commands.append(.close)
            case " ":
                continue
            default:
                return nil  // unexpected command — extraction contract violated
            }
        }
        // A path with no drawable points (empty string, or bare Z) parses to
        // nothing — mirrors the old CGPath.isEmpty guard.
        guard minX.isFinite else { return nil }
        return SVGPath(commands: commands,
                       bounds: .init(minX: minX, minY: minY, maxX: maxX, maxY: maxY))
    }
}

/// Plain-English education card content for the 17 catalog muscles — the
/// reference design shows the diagram beside a name + function line.
public struct MuscleInfo: Sendable {
    public let displayName: String
    public let latinName: String
    public let function: String

    public static func info(for driftMuscle: String) -> MuscleInfo? {
        infos[driftMuscle.lowercased()]
    }

    private static let infos: [String: MuscleInfo] = [
        "abdominals": .init(displayName: "Abs", latinName: "rectus abdominis", function: "Curls your torso forward and braces your core"),
        "abductors": .init(displayName: "Abductors", latinName: "gluteus medius/minimus", function: "Move your leg away from your body"),
        "adductors": .init(displayName: "Adductors", latinName: "adductor group", function: "Pull your legs together"),
        "biceps": .init(displayName: "Biceps", latinName: "biceps brachii", function: "Bend your elbow and turn your palm up"),
        "calves": .init(displayName: "Calves", latinName: "gastrocnemius & soleus", function: "Point your toes and push off the ground"),
        "chest": .init(displayName: "Chest", latinName: "pectoralis major", function: "Pushes your arms forward and together"),
        "forearms": .init(displayName: "Forearms", latinName: "flexors & extensors", function: "Grip strength and wrist control"),
        "glutes": .init(displayName: "Glutes", latinName: "gluteus maximus", function: "Drive your hips forward — stand, jump, climb"),
        "hamstrings": .init(displayName: "Hamstrings", latinName: "biceps femoris group", function: "Bend your knee and pull your hip back"),
        "lats": .init(displayName: "Lats", latinName: "latissimus dorsi", function: "Pull your arms down and toward you"),
        "lower back": .init(displayName: "Lower Back", latinName: "erector spinae", function: "Keeps your spine upright and extends it"),
        "middle back": .init(displayName: "Middle Back", latinName: "rhomboids & mid-traps", function: "Squeeze your shoulder blades together"),
        "neck": .init(displayName: "Neck", latinName: "sternocleidomastoid", function: "Turns and tilts your head"),
        "quadriceps": .init(displayName: "Quads", latinName: "quadriceps femoris", function: "Straighten your knee — squat, run, kick"),
        "shoulders": .init(displayName: "Shoulders", latinName: "deltoids", function: "Raise and rotate your arms in every direction"),
        "traps": .init(displayName: "Traps", latinName: "trapezius", function: "Shrug, and hold your shoulder blades steady"),
        "triceps": .init(displayName: "Triceps", latinName: "triceps brachii", function: "Straighten your elbow — every press finishes here"),
    ]
}
