import Foundation
@testable import DriftCore
import Testing

/// The Android shell's launch-sequence contract.
///
/// `DriftAndroidApp.swift` is not linkable from any test target — it imports
/// SkipFuse and only compiles in the Skip Android pass — so the wiring is
/// pinned by reading the source, the same trick `MoreTabFeedbackRegressionTests`
/// uses. iOS pins the equivalent by instantiating the shell
/// (`DriftTests/DriftAppLaunchTests.swift`); Android cannot, and "cannot run it"
/// is exactly why the gap keeps shipping.
///
/// It has now shipped three times. #1209: `ToolRegistration.registerAll()` was
/// never called, so every Coach turn answered "unknown tool". #1212:
/// `WeightTrendService.shared.refresh()` and `TDEEEstimator.shared.refresh()`
/// were never called, so `TDEEEstimator.current` stayed nil and food targets +
/// AI reasoning computed against the hardcoded 2000 kcal fallback
/// (`FoodService.swift:374`, `:794`, `AIRuleEngine.swift:182`) on every entry
/// path that didn't visit the Today tab first. #1214 stopped waiting for
/// occurrence #4 and diffed the whole of `DriftApp.init()` + its launch `.task`
/// + its scenePhase handlers against the shell, finding four more.
///
/// The rule the two incidents share: `DriftAndroidApp` must mirror *every*
/// `DriftApp.init()` launch call, not just the `DriftPlatform` seams.
@Suite struct AndroidLaunchWiringTests {

    /// Calls the Android shell owes at launch, each with the reason it exists
    /// so a future reader deleting one has to argue with the incident.
    static let requiredLaunchCalls: [(call: String, why: String)] = [
        ("ToolRegistration.registerAll()",
         "#1209 — without it ToolRegistry is empty, every Coach turn resolves to 'unknown tool', and toolsJSONString is nil so cloud requests carry no function schemas"),
        ("WeightTrendService.shared.refresh()",
         "#1212 — without it latestWeightKg/trend are populated only as a side effect of the Today tab"),
        ("TDEEEstimator.shared.refresh()",
         "#1212 — without it TDEEEstimator.current stays nil and food targets fall back to a flat 2000 kcal"),
        ("DriftPlatform.uiRefreshKick =",
         "#1180 — without it bridged @Observable writes never schedule a Compose recomposition, so a tap that already wrote its rows leaves the frame unchanged; one Coach confirm tap read as dead and became three duplicate food_entry rows"),
        ("Preferences.seedInstallDateIfNeeded()",
         "#1214 — the #759 Feedback activation banner anchors on install date, and the anchor is 'first launch', which happens exactly once; skip it and no later port can ever backfill it"),
        ("Preferences.migrateCoachVoiceIfNeeded()",
         "#1214 — the one-time heal for the poisoned pre-#937 coachVoiceEnabled pref (#968); a restored cross-platform backup (#1094) can carry the bad value onto Android, and the migration is the only thing that clears it"),
        ("DefaultTemplates.registerCustomExercises()",
         "#1214 — the idempotent #941 upgrade that back-fills muscle slugs + pose assets onto template custom exercises; without it at launch it fires only as a side effect of DefaultTemplates.load(), i.e. only if the user taps 'load package', so older-build templates keep missing muscles and photos"),
        ("NotificationCenter.default.post(name: .saveConversationState",
         "#1214 — AIChatViewModel (SharedUI, live on Android) listens for this and snapshots the conversation; without a post on backgrounding, routine Android process death loses the in-flight Coach context that iOS keeps via scenePhase"),
    ]

    @Test func androidShellMakesEveryRequiredLaunchCall() throws {
        let source = try Self.androidShellSource()
        for required in Self.requiredLaunchCalls {
            #expect(source.contains(required.call),
                    "The Android shell must call \(required.call) at startup — \(required.why)")
        }
    }

    /// Ordering is a real contract, not style: `TDEEEstimator.refresh()` reads
    /// `WeightTrendService.shared.latestWeightKg` (`TDEEEstimator.swift:265`),
    /// so refreshing TDEE first caches an estimate built on a nil weight — the
    /// precise failure the Today tab's own workaround comment describes. iOS
    /// encodes the same order at `DriftApp.swift:228` then `:233`.
    @Test func weightTrendRefreshPrecedesTDEERefresh() throws {
        let source = try Self.androidAppSource()
        guard let trendRange = source.range(of: "WeightTrendService.shared.refresh()"),
              let tdeeRange = source.range(of: "TDEEEstimator.shared.refresh()") else {
            Issue.record("Both launch refreshes must be present before their order can be checked")
            return
        }
        #expect(trendRange.lowerBound < tdeeRange.lowerBound,
                "WeightTrendService.shared.refresh() must run BEFORE TDEEEstimator.shared.refresh() — TDEE reads latestWeightKg, so the reverse order caches a no-weight estimate")
    }

    /// The launch refreshes sat behind `guard let health = ... else { return }`
    /// in the first draft of the fix, which would have skipped them entirely on
    /// any device without Health Connect. A `guard`-with-`return` between the
    /// database warm-up and the refreshes is a silent regression of #1212 for
    /// exactly the users least likely to be noticed.
    @Test func healthAvailabilityDoesNotGateTheLaunchRefreshes() throws {
        // Comments are stripped first: this file's own explanation of the fix
        // quotes `guard ... else { return }`, and a source scan that trips on
        // prose about the bug is worse than no scan at all.
        let source = try Self.strippingLineComments(Self.androidAppSource())
        guard let launchRange = source.range(of: "public func onLaunch()"),
              let trendRange = source.range(of: "WeightTrendService.shared.refresh()") else {
            Issue.record("onLaunch() and the trend refresh must both be present")
            return
        }
        let body = source[launchRange.lowerBound..<trendRange.lowerBound]
        #expect(!body.contains("else { return }"),
                "No early return may sit between onLaunch()'s start and the launch refreshes — an unavailable Health Connect must not skip them")
    }

    // MARK: - Source access

    /// Drop `//` line comments so structural assertions see code, not prose.
    private static func strippingLineComments(_ source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let commentStart = line.range(of: "//") else { return line }
                return line[line.startIndex..<commentStart.lowerBound]
            }
            .joined(separator: "\n")
    }

    private static func androidAppSource() throws -> String {
        try shellFile("DriftAndroidApp.swift")
    }

    /// Every file the launch sequence is spread across, concatenated.
    ///
    /// The containment scan reads THIS, not `androidAppSource()` alone: not all
    /// of the sequence lives in the app delegate. The #941 catalog upgrade runs
    /// inside `CoreResourcesBootstrap.warmTask` because it has to be off-main
    /// (#1214), and a scan that only knew about `DriftAndroidApp.swift` would
    /// call a correctly-wired call site missing.
    ///
    /// The ordering and no-early-return tests deliberately keep reading
    /// `androidAppSource()`: their range logic assumes one file's line order,
    /// and neither of their target strings may ever legitimately appear in the
    /// bootstrap.
    private static func androidShellSource() throws -> String {
        try shellSourceFiles.map { try shellFile($0) }.joined(separator: "\n")
    }

    private static let shellSourceFiles = ["DriftAndroidApp.swift", "CoreResourcesBootstrap.swift"]

    private static func shellFile(_ name: String) throws -> String {
        let url = projectRoot()
            .appendingPathComponent("drift-android/Sources/DriftAndroid/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Resolve the project root from this test file's compile-time path.
    /// `#filePath` is `<root>/DriftCore/Tests/DriftCoreTests/<this>.swift`.
    private static func projectRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // DriftCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // DriftCore/
            .deletingLastPathComponent() // <project root>
    }
}
