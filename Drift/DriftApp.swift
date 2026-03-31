import SwiftUI

@main
struct DriftApp: App {
    @State private var hasRequestedHealthKit = false
    @State private var syncComplete = false

    var body: some Scene {
        WindowGroup {
            ContentView(syncComplete: $syncComplete)
                .preferredColorScheme(.dark)
                .task {
                    if !hasRequestedHealthKit {
                        hasRequestedHealthKit = true
                        DefaultTemplates.seedIfNeeded()
                        #if !targetEnvironment(simulator)
                        do {
                            try await HealthKitService.shared.requestAuthorization()
                            let count = try await HealthKitService.shared.syncWeight()
                            Log.app.info("Initial sync: \(count) weight entries")
                        } catch {
                            Log.app.error("Initial sync failed: \(error.localizedDescription)")
                        }
                        #endif
                        syncComplete = true
                    }
                }
        }
    }
}
