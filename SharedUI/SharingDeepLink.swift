import SwiftUI
import Observation
import DriftCore

/// Where an inbound `drift://add/<handle>` lands before the hub can act on it.
///
/// Android only in practice — iOS doesn't register the scheme (see
/// `InviteLink`). It may arrive long before the Friends screen exists — cold
/// launch from a tap — so the handle is parked here and the hub picks it up
/// whenever it appears. `@Observable` (needs `import Observation` on Skip) so a
/// stored handle re-triggers the hub's `onChange` even if the screen was
/// already open.
@Observable
final class SharingDeepLink {
    /// Set by each platform's URL handler; cleared by the hub once resolved.
    /// Static so the App-level handler doesn't need a reference to the view.
    nonisolated(unsafe) static var pendingUsername: String?

    /// Accepts anything and returns whether it was an invite we can act on, so
    /// each platform's handler is a one-liner.
    @discardableResult
    static func handle(_ raw: String) -> Bool {
        guard let handle = InviteLink.username(from: raw) else { return false }
        pendingUsername = handle
        return true
    }

    static func clear() { pendingUsername = nil }
}

/// The invite: your @handle and how to act on it.
///
/// NOT a link — see `InviteLink` for why the `https://drift.app/...` version
/// was removed. ShareLink on Skip shares TEXT only (no file attachment), which
/// is exactly what a handle invite needs, so this is one of the rare share
/// surfaces that behaves identically on both platforms.
struct InviteShareSheet: View {
    let username: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            // In-content chrome: a nav bar in a sheet reserves a dead band on
            // Android (#1089).
            HStack {
                Button("Close") { dismiss() }.foregroundStyle(Theme.accent)
                Spacer()
                Text("Invite").font(.headline)
                Spacer()
                // Balances the row so the title stays centred.
                Text("Close").font(.body).foregroundStyle(.clear)
            }

            Text(String(username.prefix(1)).uppercased())
                .font(.title.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Theme.accentGradient, in: Circle())

            Text("@\(username)")
                .font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)

            // No link, and the copy no longer promises one. This screen used to
            // show `https://drift.app/add/<handle>` and claim "tapping it opens
            // Drift" — we don't own that domain, so every invite anyone sent hit
            // a Safari TLS error (operator repro, 2026-07-30). Handle-sharing
            // works today on both platforms with nothing to host.
            Text("Send them your handle. They search it in Drift → Friends and tap Add friend.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            ShareLink(item: InviteLink.shareText(for: username)) {
                Label("Share handle", systemImage: sym("square.and.arrow.up"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent)

            // A QR code belongs here too — a coach signing up a client stood in
            // front of them shouldn't dictate a username. Deferred to its own
            // piece: SkipUI has no CoreImage, so doing it once for both
            // platforms means a pure-Swift encoder in DriftCore rather than
            // CIQRCodeGenerator plus a ZXing facade (#1162 C2).

            Spacer()
        }
        .padding(20)
        .background(Theme.background.ignoresSafeArea())
        #if os(Android)
        .presentationDetents([.fraction(0.75), .large])
        #else
        .presentationDetents([.medium, .large])
        #endif
    }
}
