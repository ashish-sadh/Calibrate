import SwiftUI
import DriftCore

// MARK: - Workout tab root
//
// The active-workout flow is the SharedUI `ActiveWorkoutView` (single-source
// with iOS, #1064 1c), presented from DriftWorkoutView the same way iOS
// WorkoutView presents it.

struct WorkoutTab: View {
    var body: some View {
        NavigationStack {
            DriftWorkoutView()
        }
    }
}
