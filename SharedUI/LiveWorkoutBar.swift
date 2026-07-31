import SwiftUI
import DriftCore
import Observation  // @Observable — not re-exported by Foundation on the Android Swift SDK

/// Cross-view state for the minimized-workout pill (#1167).
///
/// A live workout is a `.sheet` owned by `WorkoutView`, but the operator needs
/// to see and resume it from ANY tab: once the sheet closes, minimizing reads as
/// losing the session (it's persisted, just invisible). This singleton is the
/// seam — `ActiveWorkoutView` reports whether it's on screen, each platform's
/// root overlays the bar when a session is minimized, and a tap asks
/// `WorkoutView` to reopen the sheet.
///
/// `@MainActor` because every field is UI state; `@Observable` so the bar and
/// the roots re-render/react without a Combine publisher (Skip needs the
/// explicit `import Observation`). Fields are non-private so Skip Fuse can
/// bridge them ([Fuse Can't Bridge Private Views/State]).
@MainActor
@Observable
final class LiveWorkoutMonitor {
    static let shared = LiveWorkoutMonitor()

    /// True while `ActiveWorkoutView` is presented — the bar hides, since the
    /// workout is already on screen.
    var isPresented = false

    /// Name of the minimized workout, or nil when nothing is waiting. Cached
    /// here (refreshed only on lifecycle events) so the bar's body never does
    /// the `loadSession()` JSON-decode + possible DB write, which crosses the
    /// JNI bridge on every Compose recomposition on Android (directive 0e).
    var minimizedName: String?

    /// Seconds trained so far, frozen at the last save. It does NOT tick while
    /// minimized: Drift excludes away-time from the workout clock and rebases it
    /// on resume ([field report 2026-07-16]), so a live tick here would jump
    /// backward the moment the sheet reopened.
    var minimizedTrainedSeconds = 0

    /// Set by the bar; consumed by `WorkoutView` to re-present the sheet. A
    /// stored flag, not a notification, because the Android root tears the
    /// outgoing tab down on switch — a notification posted before `WorkoutView`
    /// rebuilds would be missed, whereas this flag is still true when its
    /// `onAppear` reads it.
    var wantsResume = false

    private init() {}

    /// Called by `ActiveWorkoutView` on appear/disappear. Recomputes what the
    /// bar should show. Cheap enough for lifecycle events (start / minimize /
    /// finish) and app launch — NOT for a view body.
    func setPresented(_ presented: Bool) {
        isPresented = presented
        refresh()
    }

    /// Re-read whether a session is waiting. Also the app-launch entry point:
    /// a workout the app was killed during shows its bar on next start.
    func refresh() {
        guard !isPresented, let session = WorkoutService.loadSession() else {
            minimizedName = nil
            return
        }
        minimizedName = session.workoutName
        minimizedTrainedSeconds = Int(session.trainedSeconds())
    }

    /// Ask the workout sheet to reopen. The root switches to the Workout tab;
    /// `WorkoutView` reads `wantsResume` and presents.
    func requestResume() { wantsResume = true }
}

/// The persistent minimized-workout pill — rendered at app root, above the tab
/// bar, on every tab. Shows the workout name and time trained so far; tapping
/// resumes the live sheet.
struct MinimizedWorkoutBar: View {
    var monitor = LiveWorkoutMonitor.shared

    var body: some View {
        // `minimizedName` is nil while the sheet is up (isPresented) and after a
        // finish (which clears the session), so the bar only shows for a genuine
        // minimized workout.
        if !monitor.isPresented, let name = monitor.minimizedName {
            Button { monitor.requestResume() } label: {
                HStack(spacing: 10) {
                    Image(systemName: sym("figure.strengthtraining.traditional"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name)
                            .font(.caption.weight(.semibold)).foregroundStyle(.white)
                            .lineLimit(1)
                        Text("\(Self.elapsed(monitor.minimizedTrainedSeconds)) · tap to resume")
                            .font(.caption2).foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: sym("chevron.up"))
                        .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 14)
                #if os(Android)
                .frame(minHeight: 48)  // Material touch-target floor, matching SocialPillRow
                #else
                .padding(.vertical, 10)
                #endif
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.ink, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
                .shadowSoft()
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            // The pill owns the 8pt gap above the tab bar, so the root VStacks
            // use spacing 0 — an empty (nothing-minimized) bar then reserves no
            // space at all rather than leaving a dead gap on every screen.
            .padding(.bottom, 8)
            .accessibilityLabel("Resume workout \(name)")
            .accessibilityIdentifier("minimized-workout-bar")
        }
    }

    /// Compact "trained so far" — "42m" or "1h 05m". Frozen; see the monitor's
    /// `minimizedTrainedSeconds` for why it doesn't tick.
    static func elapsed(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
    }
}
