import Foundation

// MARK: - Domain result models

/// Structured result of scanning a workout photo / screenshot / PDF page.
/// A single page can carry BOTH a reusable program (the printed grid) AND
/// dated performance logs (handwritten columns) — the user's notebook is
/// exactly that — so the parser returns both lists and lets the review UI
/// decide what to save. Empty when the image isn't a workout.
public struct ScannedWorkoutResult: Sendable, Equatable {
    public var templates: [ScannedTemplate]
    public var sessions: [ScannedSession]

    public init(templates: [ScannedTemplate] = [], sessions: [ScannedSession] = []) {
        self.templates = templates
        self.sessions = sessions
    }

    public var isEmpty: Bool { templates.isEmpty && sessions.isEmpty }
}

/// A reusable program extracted from a printed/typed plan (no per-session
/// weights). Maps to `WorkoutTemplate` on save. Target reps live in `repsText`
/// (a template has no numeric reps field — they fold into the exercise notes).
public struct ScannedTemplate: Sendable, Equatable {
    public var name: String
    public var exercises: [ScannedTemplateExercise]

    public init(name: String, exercises: [ScannedTemplateExercise]) {
        self.name = name
        self.exercises = exercises
    }
}

public struct ScannedTemplateExercise: Sendable, Equatable {
    public var name: String
    public var sets: Int
    public var repsText: String?     // "8-12", "20", "AMRAP"
    public var restSeconds: Int?
    public var isWarmup: Bool
    public var notes: String?

    public init(name: String, sets: Int, repsText: String? = nil, restSeconds: Int? = nil,
                isWarmup: Bool = false, notes: String? = nil) {
        self.name = name
        self.sets = sets
        self.repsText = repsText
        self.restSeconds = restSeconds
        self.isWarmup = isWarmup
        self.notes = notes
    }

    /// Fold target reps + notes into the single free-text `notes` slot a
    /// `WorkoutTemplate.TemplateExercise` exposes (it has no reps field).
    public var foldedNotes: String? {
        var parts: [String] = []
        if let r = repsText?.trimmingCharacters(in: .whitespaces), !r.isEmpty {
            parts.append(r.range(of: #"rep"#, options: .caseInsensitive) == nil ? "\(r) reps" : r)
        }
        if let n = notes?.trimmingCharacters(in: .whitespaces), !n.isEmpty { parts.append(n) }
        let joined = parts.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }
}

/// A performed workout on a specific day. Maps to a `Workout` + per-set
/// `WorkoutSet` rows on save (per-set detail is preserved — "45×10 / 60×15 /
/// 70×8" is three sets at ascending weight, not three identical ones).
public struct ScannedSession: Sendable, Equatable {
    public var date: Date?
    public var name: String
    public var exercises: [ScannedSessionExercise]

    public init(date: Date?, name: String, exercises: [ScannedSessionExercise]) {
        self.date = date
        self.name = name
        self.exercises = exercises
    }
}

public struct ScannedSessionExercise: Sendable, Equatable {
    public var name: String
    public var isDuration: Bool
    public var sets: [ScannedSet]
    public var durationMinutes: Int?

    public init(name: String, isDuration: Bool, sets: [ScannedSet] = [], durationMinutes: Int? = nil) {
        self.name = name
        self.isDuration = isDuration
        self.sets = sets
        self.durationMinutes = durationMinutes
    }
}

public struct ScannedSet: Sendable, Equatable {
    public var reps: Int?
    public var weightLbs: Double?
    public var isWarmup: Bool

    public init(reps: Int? = nil, weightLbs: Double? = nil, isWarmup: Bool = false) {
        self.reps = reps
        self.weightLbs = weightLbs
        self.isWarmup = isWarmup
    }
}

// MARK: - Parser

/// Reads a workout PHOTO / screenshot / PDF page (as JPEG data) with the same
/// cloud vision model that powers Drift Coach's photo turns (Nebius
/// `Qwen2.5-VL` when provisioned) and returns structured programs + sessions.
///
/// The image path is the twin of `NebiusExerciseLogger` (text): cloud-first,
/// bounds-guarded, prose-JSON (not tool-calling), pure decoder so the mapping
/// is Tier-0 testable. The vision model does the heavy lifting on-page —
/// handwriting, shorthand ("BW×20"), and canonicalising abbreviated names
/// ("Incline DB press" → "Incline Dumbbell Press") — because on-device Vision
/// OCR mangles handwriting and `ExerciseDatabase.match` deliberately won't
/// expand "DB" → "Dumbbell".
@MainActor
public enum NebiusWorkoutPhotoParser {

    static let systemPrompt = """
    You read a photo, screenshot, or scanned page of a workout and convert it into structured JSON.
    A page may be a REUSABLE PLAN (a printed/typed grid of exercises with target sets×reps — no real weights logged), or a PERFORMED LOG (handwritten, dated, with the actual weights and reps done that day), or BOTH on one page. Extract everything present.

    Return ONLY a JSON object — no prose, no markdown fences — in exactly this shape:
    {
      "templates": [
        {"name": "string", "exercises": [
          {"name": "string", "sets": number, "repsText": "string|null", "restSeconds": number|null, "isWarmup": boolean, "notes": "string|null"}
        ]}
      ],
      "sessions": [
        {"date": "YYYY-MM-DD|null", "name": "string", "exercises": [
          {"name": "string", "isDuration": boolean, "durationMinutes": number|null, "sets": [
            {"reps": number|null, "weightLbs": number|null, "isWarmup": boolean}
          ]}
        ]}
      ]
    }

    Rules:
    - Only extract what is on the page. Never invent exercises, sets, weights, or reps. If a field is unknown, use null.
    - Exercise NAMES: expand abbreviations to canonical full names. "DB"→"Dumbbell", "BB"→"Barbell", "OHP"→"Overhead Press", "RDL"→"Romanian Deadlift", "BW"→bodyweight (weightLbs=null), "SS"/"superset"→drop the marker, keep the movement. E.g. "Incline DB press" → "Incline Dumbbell Press".
    - WEIGHTS always in pounds. Convert kg×2.205→lbs, round to nearest pound. "45×10" usually means 45 lbs × 10 reps; "3x10" with no weight means 3 sets of 10 reps (weight null). "#" often denotes pounds ("10#" = 10 lbs).
    - Per-set logs like "45×10 / 60×15 / 70×8" → three sets: {45 lbs,10},{60 lbs,15},{70 lbs,8}. Preserve the order and each distinct weight/rep.
    - Bodyweight movements (pushups, pull-ups) → weightLbs null unless added weight is written.
    - DURATION exercises (yoga, plank, running, cycling, stretching): isDuration=true, put minutes in durationMinutes, leave sets empty (or one set with reps null).
    - TEMPLATE exercises: "sets" is the set count; put the rep target in "repsText" verbatim ("8-12", "20", "AMRAP"). Convert a written rest like "2 mins"→restSeconds 120, "1-1.5min"→90. Mark warmup rows isWarmup=true. Keep coaching cues in "notes".
    - DATES are written MONTH-FIRST: "3/12" = March 12, "3/26/26" = March 26 2026, "4/30/26" = April 30 2026. A trailing two-digit year is 20YY (26 → 2026) — never output a year before 2020 for a handwritten log. Output YYYY-MM-DD. If the year is missing, assume the most recent past occurrence relative to today. If a log has no date, use null.
    - Extract EVERY dated log separately — a page often has several dated columns/blocks side by side. Count the distinct dates first, then emit one session per date. Never emit the same column twice; if two sessions look identical, re-read the page.
    - COMPLETENESS IS MANDATORY: transcribe every line of every dated log to its end — handwritten logs often number their lines (1) 2) 3)…); if a log shows 6 numbered lines, its session must have 6 exercises. Do not stop early, do not summarize, do not skip hard-to-read lines (make your best reading instead).
    - A warmup list printed OUTSIDE the main table (e.g. a bulleted "Warmup — do as a circuit" block) still belongs in the template: one exercise per line with isWarmup=true.
    - SESSION name: a short label if written (e.g. "Push Day"); otherwise use null and the app will name it.
    - The user may include a NOTE with the image ("weights are in kg", "only log the right column", "this is my Tuesday push day"). Treat the note as authoritative — it overrides your reading of ambiguous marks (units, which section to extract, names, dates).
    - Return {"templates":[],"sessions":[]} when the image is not a workout at all.
    """

    /// Progress milestones surfaced to the scan UI. Each is a REAL signal, not
    /// cosmetic: `.reading` fires on the first streamed token (proof the upload
    /// + page-read succeeded and generation started); `.retrying` fires when a
    /// transient failure triggers the automatic second attempt.
    public enum ScanStage: Sendable, Equatable {
        case sending
        case reading
        case retrying
    }

    /// Parse workout `imageData` (JPEG) via the coach cloud vision model.
    /// `userNote` is an optional rider the user typed alongside the scan
    /// ("weights are in kg", "only the right column") — forwarded to the model
    /// as authoritative context. `onStage` reports real progress milestones.
    /// Transient failures (dropped connection / 5xx / timeout) get ONE
    /// automatic retry — the wait is long and a mid-scan network blip
    /// shouldn't cost the user their whole minute; auth/quota/rate errors
    /// never retry (they need the user to act). Returns nil when the cloud
    /// isn't configured, both attempts fail, or nothing decodes.
    public static func parse(imageData: Data, visionModelID: String,
                             userNote: String? = nil,
                             onStage: (@Sendable (ScanStage) -> Void)? = nil) async -> ScannedWorkoutResult? {
        guard !imageData.isEmpty else { return nil }
        guard CoachCloud.isConfigured else { return nil }
        CoachCloud.install()

        for attempt in 1...2 {
            onStage?(.sending)
            let firstToken = FirstTokenFlag()
            let raw = await LocalAIService.shared.respondDirectWithPhoto(
                systemPrompt: systemPrompt,
                message: requestMessage(userNote: userNote),
                imageData: imageData,
                visionModelID: visionModelID,
                maxTokens: scanMaxTokens,
                timeout: scanTimeout,
                temperature: scanTemperature,
                onToken: { _ in
                    if firstToken.markFired() { onStage?(.reading) }
                }
            )
            if let result = decode(raw, referenceDate: Date()) { return result }
            // Decide whether the miss is worth a second attempt.
            guard attempt == 1, isRetryable(LocalAIService.shared.lastRemoteError) else { return nil }
            onStage?(.retrying)
        }
        return nil
    }

    /// Only transient faults retry — a dropped connection or provider 5xx can
    /// succeed a second later; auth/quota/rate-limit will fail identically and
    /// retrying just doubles the wait before the user sees the real problem.
    /// A nil error means the reply arrived but didn't decode — retrying the
    /// same image at temperature 0 would return the same reply, so don't.
    nonisolated static func isRetryable(_ err: RemoteBackendError?) -> Bool {
        if case .transient = err { return true }
        return false
    }

    /// Thread-safe once-flag so the streaming callback fires `.reading` exactly
    /// once per attempt (onToken arrives on a background executor).
    private final class FirstTokenFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false
        func markFired() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if fired { return false }
            fired = true
            return true
        }
    }

    /// A full page (template grid + several dated sessions with per-set data)
    /// emits well over the 512-token chat ceiling — truncation snapped the JSON
    /// mid-object and read as "couldn't reach the cloud" (field bug, build 358).
    public static let scanMaxTokens = 4096
    /// The 72B VL model reading a dense handwritten page overruns the 60s chat
    /// deadline; scans are a deliberate wait-for-it flow, so give it headroom.
    /// 240s per attempt: longest observed live read was 115s on Mac Wi-Fi, and
    /// a device on cellular pays extra upload time on top.
    public static let scanTimeout: TimeInterval = 240
    /// Extraction is transcription, not conversation: at the provider-default
    /// sampling temperature the same notebook photo returned different weights
    /// on every run (live test, 2026-07-22). Pin to 0 for determinism.
    public static let scanTemperature: Double = 0

    /// The user-turn text sent with the image; a non-blank note is appended as
    /// authoritative context. Pure so the note plumbing is Tier-0 testable.
    nonisolated static func requestMessage(userNote: String?) -> String {
        var message = "Extract the workout plan and/or logged sessions from this image as JSON."
        if let note = userNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            message += "\nUser note about this image: \(note)"
        }
        return message
    }

    /// Extract + decode the first top-level JSON object, sanity-clamp everything
    /// against `ExerciseTranscriptBounds`, and drop empty entries. Pure (no I/O,
    /// `referenceDate` injected) so it's Tier-0 unit-testable. nil when nothing
    /// decodable, or a non-nil-but-empty result when the model saw no workout.
    nonisolated static func decode(_ raw: String, referenceDate: Date) -> ScannedWorkoutResult? {
        guard let json = extractJSONObject(raw),
              let data = json.data(using: .utf8),
              let resp = try? JSONDecoder().decode(Response.self, from: data) else { return nil }

        let templates: [ScannedTemplate] = (resp.templates ?? []).compactMap { t in
            let exercises: [ScannedTemplateExercise] = (t.exercises ?? []).compactMap { e in
                let name = ExerciseNameNormalizer.canonical(e.name)
                guard !name.isEmpty else { return nil }
                let sets = min(max(1, e.sets ?? 1), ExerciseTranscriptBounds.setsRange.upperBound)
                let rest = e.restSeconds.map { min(max(0, $0), 3600) }
                return ScannedTemplateExercise(
                    name: name, sets: sets,
                    repsText: e.repsText?.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                    restSeconds: rest, isWarmup: e.isWarmup ?? false,
                    notes: e.notes?.trimmingCharacters(in: .whitespaces).nilIfEmpty)
            }
            guard !exercises.isEmpty else { return nil }
            let name = t.name?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "Scanned Template"
            return ScannedTemplate(name: name, exercises: Array(exercises.prefix(ExerciseTranscriptBounds.maxEntries)))
        }

        let sessions: [ScannedSession] = (resp.sessions ?? []).compactMap { s in
            let exercises: [ScannedSessionExercise] = (s.exercises ?? []).compactMap { e in
                let name = ExerciseNameNormalizer.canonical(e.name)
                guard !name.isEmpty else { return nil }
                let isDuration = e.isDuration ?? false
                let sets: [ScannedSet] = (e.sets ?? []).compactMap { set in
                    let reps = set.reps.map { min(max(1, $0), ExerciseTranscriptBounds.repsRange.upperBound) }
                    let weight = set.weightLbs.flatMap { w -> Double? in
                        w > 0 && w <= ExerciseTranscriptBounds.weightLbsRange.upperBound ? w : nil
                    }
                    // A set with neither reps nor weight carries no information.
                    guard reps != nil || weight != nil else { return nil }
                    return ScannedSet(reps: reps, weightLbs: weight, isWarmup: set.isWarmup ?? false)
                }
                let mins = e.durationMinutes.map { min(max(1, $0), ExerciseTranscriptBounds.durationMinutesRange.upperBound) }
                // Keep the exercise if it has any sets OR a duration.
                guard !sets.isEmpty || mins != nil else { return nil }
                return ScannedSessionExercise(name: name, isDuration: isDuration,
                                              sets: sets, durationMinutes: mins)
            }
            guard !exercises.isEmpty else { return nil }
            // Implausible dates are misreads, not history: the live test read a
            // handwritten "3/12/26" as 2023-12-26 despite prompt rules. Null the
            // date instead — the review screen's picker (defaulting to today)
            // makes the user set it, rather than silently logging years back.
            let date = s.date
                .flatMap { ExerciseNameNormalizer.parseDate($0, referenceDate: referenceDate) }
                .flatMap { plausibleLogDate($0, referenceDate: referenceDate) ? $0 : nil }
            let name = s.name?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "Scanned Workout"
            return ScannedSession(date: date, name: name,
                                  exercises: Array(exercises.prefix(ExerciseTranscriptBounds.maxEntries)))
        }

        return ScannedWorkoutResult(
            templates: Array(templates.prefix(8)),
            sessions: Array(sessions.prefix(20)))
    }

    /// A believable date for a personal training log photographed now: within
    /// the last two years and not more than a day ahead (timezone slack). Pure.
    nonisolated static func plausibleLogDate(_ date: Date, referenceDate: Date) -> Bool {
        let twoYearsBack = referenceDate.addingTimeInterval(-2 * 365.25 * 86400)
        let oneDayAhead = referenceDate.addingTimeInterval(86400)
        return date >= twoYearsBack && date <= oneDayAhead
    }

    /// First brace-balanced `{...}` substring, mirroring `NebiusExerciseLogger`.
    nonisolated static func extractJSONObject(_ s: String) -> String? {
        guard let start = s.firstIndex(of: "{") else { return nil }
        var depth = 0
        var idx = start
        while idx < s.endIndex {
            switch s[idx] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(s[start...idx]) }
            default: break
            }
            idx = s.index(after: idx)
        }
        return nil
    }

    // MARK: - Wire model

    private struct Response: Codable {
        let templates: [Template]?
        let sessions: [Session]?

        struct Template: Codable {
            let name: String?
            let exercises: [Exercise]?
            struct Exercise: Codable {
                let name: String
                let sets: Int?
                let repsText: String?
                let restSeconds: Int?
                let isWarmup: Bool?
                let notes: String?
            }
        }
        struct Session: Codable {
            let date: String?
            let name: String?
            let exercises: [Exercise]?
            struct Exercise: Codable {
                let name: String
                let isDuration: Bool?
                let durationMinutes: Int?
                let sets: [Set]?
                struct Set: Codable {
                    let reps: Int?
                    let weightLbs: Double?
                    let isWarmup: Bool?
                }
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Save mapping

public extension ScannedTemplate {
    /// Map to the `WorkoutTemplate.TemplateExercise` shape (reps + cues fold into
    /// `notes`, since a template exercise has no numeric reps field). Names are
    /// grounded to the catalog spelling so the prefilled editor and saved
    /// template exact-resolve for tracking type / poses.
    var templateExercises: [WorkoutTemplate.TemplateExercise] {
        exercises.map { e in
            WorkoutTemplate.TemplateExercise(
                name: WorkoutService.groundedExerciseName(e.name),
                sets: e.sets, isWarmup: e.isWarmup,
                restSeconds: e.restSeconds ?? 90, notes: e.foldedNotes)
        }
    }

    /// The `exercises_json` blob a `WorkoutTemplate` persists. Pure/testable.
    var exercisesJSON: String {
        let data = (try? JSONEncoder().encode(templateExercises)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
