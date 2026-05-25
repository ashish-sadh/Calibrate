import XCTest

/// Tier-1 lint: hardcoded `.foregroundStyle(.white)` / `.foregroundColor(.white)`
/// is a recurring source of V7 light-mode visibility bugs (text invisible on
/// the new light backgrounds). This test scans Drift/Views/**/*.swift, finds
/// every occurrence, and asserts each one is in the allowlist below.
///
/// **When this test fails**:
/// 1. If the new `.white` site is in a legitimate context (white text on a
///    saturated solid background — `Theme.accent`, `Theme.ink`,
///    `Theme.calorieBlue`, a red error chip, etc.), add it to `allowlist`
///    below with a short rationale.
/// 2. Otherwise, switch the foreground to a Theme token that adapts:
///      - `Theme.textPrimary` for body text
///      - `Theme.textSecondary` for de-emphasized text
///      - On a `Theme.ink` selected chip, `.white` is fine and goes to the
///        allowlist.
///
/// **Why a test, not a pre-commit hook**: lives next to the rest of the
/// iOS test suite, runs in CI, can't be bypassed by `--no-verify`.
final class HardcodedWhiteTextTests: XCTestCase {

    /// `(file, snippet)` pairs that document every legitimate `.white` text
    /// usage. Snippet is matched literally against the source line; small
    /// edits will require updating the allowlist (intentional friction —
    /// pushes the author to re-justify the contrast pairing).
    private static let allowlist: [(file: String, snippet: String)] = [
        // Coral / red CTAs
        ("FoodTabView.swift", ".background(Theme.deficit.opacity(0.9), in: Capsule())"),
        ("AIChatView.swift", ".background(Capsule().fill(Color.red.opacity(0.75)))"),
        ("AIChatView+ChatBubble.swift", ".background(Theme.accent"),
        ("AIChatView+Cards.swift", ".background(Capsule().fill(Theme.calorieBlue))"),
        ("CombosView.swift", ".background(Theme.accent, in: Capsule())"),
        ("BiomarkersTabView.swift", ".background(Theme.accent, in: RoundedRectangle"),
        ("LabReportUploadView.swift", ".background(Theme.accent, in: RoundedRectangle"),
        ("BackupOnboardingSheet.swift", ".background(Theme.ink, in: RoundedRectangle"),
        ("WeightTabView.swift", ".background(Theme.ink, in: RoundedRectangle(cornerRadius: 16))"),
        ("WorkoutView.swift", ".background(Theme.ink, in: RoundedRectangle(cornerRadius: 12))"),
        // Solid ink (V7 selected-chip pattern) — white reads on black
        ("FoodTabView.swift", "? Theme.ink : Color.clear, in: RoundedRectangle"),
        ("FoodTabView.swift", "? Theme.ink : Color.clear, in: Capsule()"),
        ("WeightTabView.swift", "? Theme.ink : Color.clear, in: RoundedRectangle"),
        ("GlucoseTabView.swift", "? Theme.ink : Color.clear, in: RoundedRectangle"),
        ("PlantPointsCardView.swift", "? Theme.ink : Color.clear"),
        ("ServingInputView.swift", "? Theme.ink"),
        ("QuickAddView.swift", "? Theme.ink : Theme.cardBackgroundElevated, in: Capsule()"),
        ("ManualFoodEntrySheet.swift", "? Theme.ink : Theme.cardBackgroundElevated, in: Capsule()"),
        ("EditFoodEntrySheet.swift", "? Theme.ink : Theme.cardBackgroundElevated,"),
        ("ExercisePickerView.swift", "? Theme.ink : Theme.cardBackgroundElevated, in: RoundedRectangle"),
        ("ExerciseBrowserView.swift", "? Theme.ink : Theme.cardBackgroundElevated, in: RoundedRectangle"),
        ("BiomarkersTabView.swift", "? Theme.ink : Theme.cardBackground, in: RoundedRectangle"),
        ("WorkoutView.swift", "Theme.ink"),
    ]

    func testNoUnauthorizedHardcodedWhiteText() throws {
        let viewsRoot = try locateViewsDirectory()
        let offenders = try scanForOffenders(in: viewsRoot)

        if offenders.isEmpty { return }

        let formatted = offenders
            .map { "  \($0.file):\($0.line) — `\($0.snippet)`" }
            .joined(separator: "\n")

        XCTFail(
            "Unauthorized hardcoded white text — would render invisible on V7 light surfaces.\n" +
            "If this is intentional (e.g. white text on a Theme.ink / Theme.accent / red.opacity / solid-color background), " +
            "add the (file, snippet) pair to `HardcodedWhiteTextTests.allowlist`.\n" +
            "Otherwise switch to `Theme.textPrimary` or `Theme.textSecondary`.\n\n\(formatted)"
        )
    }

    // MARK: - Helpers

    private struct Offender {
        let file: String
        let line: Int
        let snippet: String
    }

    private func locateViewsDirectory() throws -> URL {
        // #filePath = .../Drift/DriftTests/HardcodedWhiteTextTests.swift
        // Walk up to the workspace, then into Drift/Views.
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent() // DriftTests/
        url.deleteLastPathComponent() // workspace root
        url.appendPathComponent("Drift/Views")
        return url
    }

    private func scanForOffenders(in root: URL) throws -> [Offender] {
        let fm = FileManager.default
        var offenders: [Offender] = []
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return offenders
        }
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let file = fileURL.lastPathComponent
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            for (i, rawLine) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let line = String(rawLine)
                let lineNumber = i + 1
                guard hasWhiteForeground(line) else { continue }
                // Look back a few lines for an allowlisted context. This is
                // a loose match — author must place the allowlist entry on
                // the same file and matching one of the nearby lines.
                if !isAllowlisted(file: file, around: lineNumber, in: content) {
                    offenders.append(Offender(
                        file: file,
                        line: lineNumber,
                        snippet: line.trimmingCharacters(in: .whitespaces)
                    ))
                }
            }
        }
        return offenders.sorted { $0.file == $1.file ? $0.line < $1.line : $0.file < $1.file }
    }

    private func hasWhiteForeground(_ line: String) -> Bool {
        line.contains(".foregroundStyle(.white)")
            || line.contains(".foregroundColor(.white)")
            || line.contains(".foregroundStyle(Color.white)")
            || line.contains(".foregroundColor(Color.white)")
    }

    private func isAllowlisted(file: String, around lineNumber: Int, in content: String) -> Bool {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Wide enough to catch the `.background(...)` modifier that
        // usually sits 5-10 lines after the `.foregroundStyle(.white)`
        // (modifier-stack order: text first, layout next, background
        // last). Narrower windows missed the WeightTabView milestone
        // card (7 lines apart) and the WorkoutView active-session
        // banner (8 lines apart).
        let windowStart = max(0, lineNumber - 6)
        let windowEnd = min(lines.count, lineNumber + 12)
        let window = lines[windowStart..<windowEnd].joined(separator: "\n")
        return Self.allowlist.contains { entry in
            entry.file == file && window.contains(entry.snippet)
        }
    }
}
