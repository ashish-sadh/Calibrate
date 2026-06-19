import SwiftUI
import DriftCore

/// The voice-first hero of Drift Coach — a large tap-to-talk circle shown in the
/// empty state. Tapping starts/stops voice capture (same flow as the small mic
/// button); the ring animates per state so the user can read what's happening.
struct ListeningCircle: View {
    enum CircleState { case idle, listening, processing, speaking, unavailable }

    let state: CircleState
    let onTap: () -> Void
    /// Diameter of the circle. Default suits the empty-state hero; the immersive
    /// talk-mode passes a larger value.
    var size: CGFloat = 150

    @State private var pulse = false

    private var tint: Color {
        switch state {
        case .listening:   return Theme.surplus        // red while capturing voice
        case .unavailable: return Theme.textTertiary
        default:           return Theme.accent
        }
    }

    private var glyph: String {
        switch state {
        case .idle:        return "mic.fill"
        case .listening:   return "waveform"
        case .processing:  return "ellipsis"
        case .speaking:    return "speaker.wave.3.fill"
        case .unavailable: return "mic.slash.fill"
        }
    }

    private var caption: String {
        switch state {
        case .idle:        return "Tap to talk"
        case .listening:   return "Listening…"
        case .processing:  return "Thinking…"
        case .speaking:    return "Speaking…"
        case .unavailable: return "Voice unavailable"
        }
    }

    private var animating: Bool { state == .listening || state == .speaking }

    var body: some View {
        VStack(spacing: 16) {
            Button(action: onTap) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.12))
                        .frame(width: size, height: size)
                        .overlay(Circle().stroke(tint.opacity(0.5), lineWidth: 2))
                        .scaleEffect(animating && pulse ? 1.08 : 1.0)
                    if state == .processing {
                        ProgressView().scaleEffect(1.4 * (size / 150)).tint(tint)
                    } else {
                        Image(systemName: glyph)
                            .font(.system(size: 44 * (size / 150), weight: .medium))
                            .foregroundStyle(tint)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(state == .unavailable)
            .accessibilityLabel(caption)
            .accessibilityIdentifier("coach-listening-circle")

            Text(caption)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .onAppear { updateAnimation() }
        .onChange(of: state) { _, _ in updateAnimation() }
    }

    private func updateAnimation() {
        if animating {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        } else {
            // Stop the repeating animation when idle/processing so it doesn't
            // spin forever off-screen once a conversation starts.
            withAnimation(.default) { pulse = false }
        }
    }
}
