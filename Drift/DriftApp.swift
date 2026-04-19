import SwiftUI
import WidgetKit

@main
struct DriftApp: App {
    @State private var hasRequestedHealthKit = false
    @State private var syncComplete = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(syncComplete: $syncComplete)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, newPhase in
                    // Broadcast to any listening AIChatViewModel so it can snapshot state.
                    // Listener-based so the singleton doesn't need a VM reference.
                    if newPhase == .background || newPhase == .inactive {
                        NotificationCenter.default.post(name: .saveConversationState, object: nil)
                    }
                }
                .task {
                    if !hasRequestedHealthKit {
                        hasRequestedHealthKit = true
                        DefaultFoods.seedIfNeeded()
                        #if targetEnvironment(simulator)
                        // 🧪 Uncomment ONE to test on simulator:
                        // DebugSeedData.seedWeightGoalBug()    // reproduces "gain 14.1 kg" bug
                        // DebugSeedData.seedNormalGoal()        // normal losing goal (correct)
                        // DebugSeedData.seedGainingGoal()       // gaining goal scenario
                        #endif
                        #if !targetEnvironment(simulator)
                        do {
                            try await HealthKitService.shared.requestAuthorization()
                            let count = try await HealthKitService.shared.syncWeight()
                            Log.app.info("Initial sync: \(count) weight entries")
                            let bodyComp = try await HealthKitService.shared.syncBodyComposition()
                            Log.app.info("Initial sync: \(bodyComp) body composition entries")
                        } catch {
                            Log.app.error("Initial sync failed: \(error.localizedDescription)")
                        }
                        #endif
                        // Refresh TDEE estimate (uses Apple Health + weight trend + food data)
                        await TDEEEstimator.shared.refresh()
                        // Schedule health nudge notifications (protein, supplements, workouts)
                        await NotificationService.refreshScheduledAlerts()
                        WidgetDataProvider.refreshWidgetData()
                        syncComplete = true
                    }
                }
        }
    }
}
