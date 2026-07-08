import XCTest

/// Tier-1 lint (#960): raw SwiftUI `.tertiary` / `.quaternary` system colors fail
/// WCAG AA contrast on the V7 light surfaces (tertiary ≈ 1.6:1, quaternary ≈
/// 1.1:1), so meta/caption text rendered with them is effectively invisible.
/// This scans Drift/Views/**/*.swift and asserts no `.foregroundStyle(.tertiary)` /
/// `.foregroundStyle(.quaternary)` (or the `.foregroundColor` equivalents) remain —
/// use `Theme.textTertiary` (AA-safe) instead.
///
/// `.secondary` is intentionally NOT flagged: it's borderline and still used in
/// a few conditional `.foregroundStyle(cond ? color : .secondary)` expressions
/// where a flat swap isn't always right. The sweep migrated the standalone ones.
final class LowContrastSystemColorsTests: XCTestCase {

    /// `(file, snippet)` pairs documenting any *intentional* remaining use — e.g.
    /// tertiary on a saturated background where contrast is fine. Empty today.
    private static let allowlist: [(file: String, snippet: String)] = []

    func testNoLowContrastTertiaryOrQuaternary() throws {
        let viewsRoot = try locateViewsDirectory()
        let offenders = try scanForOffenders(in: viewsRoot)
        if offenders.isEmpty { return }

        let formatted = offenders
            .map { "  \($0.file):\($0.line) — `\($0.snippet)`" }
            .joined(separator: "\n")

        XCTFail(
            "Low-contrast system color on text — fails WCAG AA on V7 light surfaces.\n" +
            "Switch to Theme.textTertiary (AA-safe). If genuinely intentional (e.g. on a " +
            "saturated background), add the (file, snippet) pair to " +
            "LowContrastSystemColorsTests.allowlist.\n\n\(formatted)"
        )
    }

    // MARK: - Helpers

    private struct Offender {
        let file: String
        let line: Int
        let snippet: String
    }

    private func locateViewsDirectory() throws -> URL {
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
                guard hasLowContrastSystemColor(line) else { continue }
                if !isAllowlisted(file: file, line: line) {
                    offenders.append(Offender(file: file, line: i + 1,
                                              snippet: line.trimmingCharacters(in: .whitespaces)))
                }
            }
        }
        return offenders.sorted { $0.file == $1.file ? $0.line < $1.line : $0.file < $1.file }
    }

    private func hasLowContrastSystemColor(_ line: String) -> Bool {
        line.contains(".foregroundStyle(.tertiary)")
            || line.contains(".foregroundStyle(.quaternary)")
            || line.contains(".foregroundColor(.tertiary)")
            || line.contains(".foregroundColor(.quaternary)")
    }

    private func isAllowlisted(file: String, line: String) -> Bool {
        Self.allowlist.contains { $0.file == file && line.contains($0.snippet) }
    }
}
