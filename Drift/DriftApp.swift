import SwiftUI
import DriftCore
import WidgetKit

@main
struct DriftApp: App {
    @State private var hasRequestedHealthKit = false
    @State private var syncComplete = false
    @State private var launchStage: LaunchStage = .starting
    @State private var showingFirstLaunchRestore = false
    @State private var showingBackupOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Wire DriftCore adapter seams so cross-platform services can reach
        // HealthKit / WidgetKit through protocols instead of direct singletons.
        DriftPlatform.health = HealthKitService.shared
        DriftPlatform.widget = WidgetCenterRefresher()
        // Stamp the install date once so the 7-day Feedback activation banner
        // has a stable anchor (#759). Idempotent — only writes when unset.
        Preferences.seedInstallDateIfNeeded()
        // Register all AI tools in ToolRegistry. Was previously called from
        // LocalAIService.init(); moved out during DriftCore migration
        // (96e3173) and the caller wiring was lost — every tool call has
        // been returning "unknown tool" since. PhotoLog tool registers
        // separately because it depends on iOS-only Keychain + gating.
        ToolRegistration.registerAll()
        PhotoLogTool.syncRegistration()
        // BGTaskScheduler requires registration before the app finishes
        // launching — i.e. synchronously during init. Submission of the next
        // request happens later from the launch task once setup completes.
        BackupScheduler.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(syncComplete: $syncComplete, launchStage: launchStage)
                // V6 migration 2026-05-19: force light mode app-wide per V6
                // spec ("Light-only, Apple Fitness DNA"). Theme.swift was
                // rewritten in the same commit; this is the trigger so iOS
                // doesn't request light/dark per system setting.
                .preferredColorScheme(.light)
                .onChange(of: scenePhase) { _, newPhase in
                    // Broadcast to any listening AIChatViewModel so it can snapshot state.
                    // Listener-based so the singleton doesn't need a VM reference.
                    if newPhase == .background || newPhase == .inactive {
                        NotificationCenter.default.post(name: .saveConversationState, object: nil)
                    }
                    if newPhase == .active {
                        BackupMonitor.shared.checkOnForeground()
                    }
                }
                .sheet(isPresented: $showingFirstLaunchRestore) {
                    NavigationStack { RestorePickerView() }
                }
                .sheet(isPresented: $showingBackupOnboarding) {
                    BackupOnboardingSheet()
                }
                .task {
                    if !hasRequestedHealthKit {
                        hasRequestedHealthKit = true
                        // First-launch restore: if this device's DB is fresh
                        // AND a backup is sitting in the user's iCloud Drive
                        // container, offer to restore before any other launch
                        // work. The sheet is dismissible — user can choose
                        // "Start Fresh" by canceling.
                        // `iCloudAvailable` is the single signal we need from BackupService here:
                        // - true → there's a usable iCloud Drive container to back up to or restore from
                        // - false → iCloud Drive is off / user signed out; skip both sheets silently
                        let iCloudAvailable = (try? BackupService.shared.containerURL()) != nil
                        if iCloudAvailable, let dbEmpty = try? AppDatabase.shared.isEmpty(), dbEmpty {
                            let available = BackupService.shared.availableBackups()
                            if !available.isEmpty {
                                showingFirstLaunchRestore = true
                            }
                        }
                        // One-time backup-enable nudge. Only fires if the restore sheet
                        // didn't (no point asking to enable backup when we're about to
                        // restore one, or when iCloud Drive is unavailable).
                        if !showingFirstLaunchRestore,
                           BackupOnboardingDecision.shouldShow(iCloudAvailable: iCloudAvailable) {
                            showingBackupOnboarding = true
                        }
                        let launchStart = Date()
#if targetEnvironment(simulator)
                        // 🧪 Uncomment ONE to test on simulator:
                        // DebugSeedData.seedWeightGoalBug()    // reproduces "gain 14.1 kg" bug
                        // DebugSeedData.seedNormalGoal()        // normal losing goal (correct)
                        // DebugSeedData.seedGainingGoal()       // gaining goal scenario
                        #endif
                        // Stage transitions ALWAYS fire (even on simulator where the
                        // HealthKit calls are #if'd out) so the splash shows the same
                        // sequence in dev and prod — otherwise the simulator skips
                        // ".syncingHealth" and we'd never visually rehearse that frame.
                        launchStage = .syncingHealth
                        #if !targetEnvironment(simulator)
                        do {
                            let authStart = Date()
                            try await HealthKitService.shared.requestAuthorization()
                            LaunchTrace.logStep("healthkit_auth", elapsedMs: LaunchTrace.elapsedMs(since: authStart))

                            let weightStart = Date()
                            let count = try await HealthKitService.shared.syncWeight()
                            LaunchTrace.logStep("sync_weight", elapsedMs: LaunchTrace.elapsedMs(since: weightStart))
                            Log.app.info("Initial sync: \(count) weight entries")

                            let bodyCompStart = Date()
                            let bodyComp = try await HealthKitService.shared.syncBodyComposition()
                            LaunchTrace.logStep("sync_body_composition", elapsedMs: LaunchTrace.elapsedMs(since: bodyCompStart))
                            Log.app.info("Initial sync: \(bodyComp) body composition entries")
                        } catch {
                            Log.app.error("Initial sync failed: \(error.localizedDescription)")
                        }
                        #endif
                        // Recalculate weight trend from DB so latestWeightKg + trend are
                        // populated for any view or AI tool (weight_info, etc.) before
                        // the user navigates anywhere. Was previously initialized lazily
                        // by Dashboard's onAppear — non-Dashboard launch paths got stale
                        // values. Must run before TDEEEstimator.refresh() since TDEE
                        // reads WeightTrendService.shared.latestWeightKg.
                        launchStage = .calculatingTrends
                        let trendStart = Date()
                        WeightTrendService.shared.refresh()
                        LaunchTrace.logStep("weight_trend_refresh", elapsedMs: LaunchTrace.elapsedMs(since: trendStart))
                        // Refresh TDEE estimate (uses Apple Health + weight trend + food data)
                        launchStage = .estimatingEnergy
                        let tdeeStart = Date()
                        await TDEEEstimator.shared.refresh()
                        LaunchTrace.logStep("tdee_refresh", elapsedMs: LaunchTrace.elapsedMs(since: tdeeStart))
                        // ".almostThere" sticks on the splash through the 0.25s crossfade
                        // — both state changes commit in one MainActor tick so the user
                        // sees the final stage text fading out with the splash. Don't add
                        // a ".complete" assignment after — it'd race the crossfade.
                        launchStage = .almostThere
                        // Log end-to-end *before* flipping syncComplete so the trace
                        // captures the actual splash-visible duration.
                        LaunchTrace.logTotal(elapsedMs: LaunchTrace.elapsedMs(since: launchStart))
                        syncComplete = true

                        // Notifications + widget — fire-and-forget. iOS has a ~20s
                        // launch-watchdog kill; refreshScheduledAlerts() does ~35 DB
                        // reads (5 alerts × 7-day fetches in BehaviorInsightService
                        // plus medication + GLP-1 slot computation) and was blocking
                        // syncComplete inside that budget. The schedule registers
                        // asynchronously regardless of when this finishes — there is
                        // no UI affordance waiting on it. Same for widget data.
                        // Both services are @MainActor so we use Task (not detached)
                        // — they yield between awaits so UI stays responsive.
                        Task { @MainActor in
                            let notifStart = Date()
                            await NotificationService.refreshScheduledAlerts()
                            LaunchTrace.logStep("notifications_refresh", elapsedMs: LaunchTrace.elapsedMs(since: notifStart))
                        }
                        Task { @MainActor in
                            let widgetStart = Date()
                            WidgetDataProvider.refreshWidgetData()
                            LaunchTrace.logStep("widget_refresh", elapsedMs: LaunchTrace.elapsedMs(since: widgetStart))
                        }
                    }
                }
        }
    }
}
