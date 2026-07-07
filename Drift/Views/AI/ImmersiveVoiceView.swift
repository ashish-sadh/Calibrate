import SwiftUI
import DriftCore

/// Full-screen "tap to talk" surface for Drift Coach's immersive talk-mode.
///
/// Replaces the chat log + input bar with a single large `ListeningCircle`, a
/// live caption (what you're saying / what the coach said), and — when the coach
/// has proposed an action — a compact Confirm / Cancel card so you can tap as an
/// alternative to saying "yes"/"no". A small "Aa" button drops back to text chat.
/// All voice plumbing (auto-send, speak, keep-listening) is the existing loop in
/// `AIChatView`; this view is the presentation layer over it. #coach-talk-mode
struct ImmersiveVoiceView: View {
    let state: ListeningCircle.CircleState
    let caption: String
    /// Non-nil when the coach is waiting on a yes/no for a proposed meal — drives
    /// the tap Confirm/Cancel card (voice "yes"/"no" works in parallel).
    let proposal: AIChatViewModel.ProposedMealCardData?
    let onCircleTap: () -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                ListeningCircle(state: state, onTap: onCircleTap, size: 240)

                if !caption.isEmpty {
                    Text(caption)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 32)
                        .padding(.top, 24)
                        .transition(.opacity)
                }

                if let proposal {
                    confirmCard(proposal)
                        .padding(.horizontal, 24)
                        .padding(.top, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer(minLength: 0)

                Button(action: onExit) {
                    Label("Text", systemImage: "keyboard")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Theme.pillBackground))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coach-talk-to-text")
                .padding(.bottom, 24)
            }
            // #premium-polish: key the layout animation to caption PRESENCE,
            // not its content — keyed to the full string it re-fired on every
            // partial transcript while speaking, so the caption + surrounding
            // layout were perpetually mid-animation (text wobble/reflow). The
            // streaming text now updates unanimated; appear/disappear still eases.
            .animation(Theme.Motion.passive, value: caption.isEmpty)
            .animation(Theme.Motion.passive, value: proposal != nil)
        }
    }

    /// Compact confirm card — the tap alternative to a spoken "yes"/"no".
    @ViewBuilder
    private func confirmCard(_ p: AIChatViewModel.ProposedMealCardData) -> some View {
        let total = p.items.reduce(0) { $0 + $1.calories }
        let names = p.items.prefix(3).map(\.name).joined(separator: ", ")
        let extra = p.items.count > 3 ? " +\(p.items.count - 3) more" : ""
        VStack(spacing: 14) {
            Text("\(names)\(extra)")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text("\(total) cal")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Label("Cancel", systemImage: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Capsule().fill(Theme.pillBackground))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coach-confirm-cancel")
                Button(action: onConfirm) {
                    Label("Confirm", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Capsule().fill(Theme.accent))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coach-confirm-ok")
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.separator, lineWidth: 1))
    }
}
