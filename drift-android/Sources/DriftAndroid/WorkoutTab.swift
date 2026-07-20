import SwiftUI
import DriftCore

// MARK: - Workout tab root
//
// The whole workout surface is now single-source with iOS: this hosts the
// SharedUI `WorkoutView` itself (the Android-only DriftWorkoutView re-creation
// was deleted in #1064), which in turn presents ActiveWorkoutView and pushes
// WorkoutDetailView. `selectedTab` is vestigial on iOS too — WorkoutView never
// reads it — so a constant satisfies the binding.

struct WorkoutTab: View {
    var body: some View {
        NavigationStack {
            WorkoutView(selectedTab: .constant(0))
        }
    }
}
