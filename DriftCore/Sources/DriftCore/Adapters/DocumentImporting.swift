import Foundation

/// File-in seam (#1175) — the ONE API every "pick a file the user already has"
/// surface calls, so document-picker plumbing never becomes an `#if` forest in
/// views. Sibling of `ImagePicking` (#1128, photo-in).
///
/// Presents the OS document picker filtered to `allowedMIMETypes`
/// (e.g. `["text/csv", "text/comma-separated-values", "text/plain"]`) and
/// returns the picked file's raw bytes, or nil if the user cancels or the read
/// fails. Consumers never see a URL, a security scope, or a `content://` Uri —
/// just `Data`.
///
/// iOS registers no implementation: SwiftUI's `.fileImporter` already does this
/// natively there, so `DriftPlatform.documentImporter` stays nil and the iOS
/// views keep their existing modifier. Android wraps `DocumentPickerFacade`
/// (SAF `ACTION_OPEN_DOCUMENT` Activity-result, polled from Kotlin companion
/// state because Skip's bridge can neither await a `suspend` fn nor deliver a
/// Kotlin→Swift callback). nil on macOS/tests = fail-soft: import entry points
/// hide or no-op, exactly like `health` and `imagePicker`.
public protocol DocumentImporting: Sendable {
    @MainActor func importDocument(allowedMIMETypes: [String]) async -> Data?
}
