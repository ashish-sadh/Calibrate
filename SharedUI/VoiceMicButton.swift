import SwiftUI

/// Shared mic-disc affordance used by every voice-entry surface: food's
/// `VoiceLogSheet`, the Workout tab's `ExerciseVoiceLogSheet`, and the
/// Workout-tab "Log by Voice or Text" entry control. A single named component
/// so the mic treatment reads identically everywhere instead of each surface
/// re-styling its own copy.
///
/// Callers pass their own `tint`: food keeps `Theme.accent` (its existing
/// look); the V7 workout surfaces pass `Theme.ink` (no pink default). At the
/// default 140 / 44 sizing this is pixel-identical to the inline disc it
/// replaced in `VoiceLogSheet`, so the food path is visually unchanged.
struct VoiceMicButton: View {
    let tint: Color
    var diameter: CGFloat = 140
    var iconSize: CGFloat = 44

    var body: some View {
        ZStack {
            // Static disc — no pulsing animation (V7: users found the moving
            // circle distracting on the food sheet; keep it calm here too).
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: diameter, height: diameter)
            Image(systemName: sym("mic.fill"))
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(tint)
        }
    }
}

// The #Preview macro isn't available in the Android Swift build (same gate
// ExerciseVoiceLogSheet uses).
#if DRIFT_IOS_APP
#Preview {
    VStack(spacing: 32) {
        VoiceMicButton(tint: Theme.accent)
        VoiceMicButton(tint: Theme.ink, diameter: 40, iconSize: 18)
    }
    .padding()
}
#endif
