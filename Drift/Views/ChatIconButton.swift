import SwiftUI

/// Reusable chat-icon button intended for the trailing nav-bar item of
/// every primary tab root (#822). Tapping presents `DriftCoachSheet` —
/// the per-screen, one-tap path into AI chat that replaces the V6
/// floating bubble (#831).
///
/// Caller owns the `isPresented` binding so the sheet survives view
/// rotation (the binding lives on the tab root's `@State`).
struct ChatIconButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(Theme.cardBackground, in: Circle())
                .overlay(Circle().strokeBorder(Theme.separator, lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Drift Coach")
        .accessibilityIdentifier("nav-chat-icon")
    }
}
