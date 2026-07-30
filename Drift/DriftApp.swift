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
        DriftPlatform.nutritionWriter = HealthNutritionSyncService.shared
        DriftPlatform.secureStore = SecureTokenStoreKeychain()
        DriftPlatform.notifier = AppleLocalNotifier()
        // Stamp the install date once so the 7-day Feedback activation banner
        // has a stable anchor (#759). Idempotent — only writes when unset.
        Preferences.seedInstallDateIfNeeded()
        // #1035: numeric fields select-all on focus so editing a pre-filled value replaces it.
        NumericFieldSelectAll.install()
        // One-time reset: pre-#937 bug persisted coachVoiceEnabled=true on
        // every talk-mode toggle. Clear poisoned value so voice is off by
        // default for all existing users. (#968)
        Preferences.migrateCoachVoiceIfNeeded()
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
                // Invite links (#1162): park the handle for the Friends hub to
                // pick up. Parsing lives in DriftCore so both platforms accept
                // exactly the same links.
                .onOpenURL { url in
                    SharingDeepLink.handle(url.absoluteString)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // Broadcast to any listening AIChatViewModel so it can snapshot state.
                    // Listener-based so the singleton doesn't need a VM reference.
                    if newPhase == .background || newPhase == .inactive {
                        NotificationCenter.default.post(name: .saveConversationState, object: nil)
                        // Flush any debounced widget refresh before suspension
                        // so a just-logged meal always reaches the widget.
                        WidgetDataProvider.refreshWidgetDataNow()
                        // Drain the telemetry outbox on the way out — a
                        // session's events ship together rather than one
                        // request per tap.
                        TelemetryService.shared.flush()
                    }
                    if newPhase == .active {
                        BackupMonitor.shared.checkOnForeground()
                        TelemetryService.shared.event(TelemetryEvent.appOpen)
                        TelemetryService.shared.flush()
                        // Social alerts (#1162): the common case is simply
                        // opening the app, which needs no background execution
                        // at all. Local notifications only — see LocalNotifier.
                        Task { await SocialAlertPoll.run() }
                    }
                }
                .sheet(isPresented: $showingFirstLaunchRestore) {
                    NavigationStack { RestorePickerView() }
                }
                .sheet(isPresented: $showingBackupOnboarding) {
                    BackupOnboardingSheet()
                }
                .task {
                    // Idempotent (#941): upgrades template custom exercises
                    // registered by older builds with their muscle slugs +
                    // pose assets. Ran in DriftApp.init until 2026-07-15 —
                    // that decoded the 1MB exercises.json catalog on the main
                    // thread before the first frame; here it's behind the
                    // splash and warms the same catalog cache the workout tab
                    // needs anyway.
                    DefaultTemplates.registerCustomExercises()
                    WorkoutService.pruneLegacyUtteranceCustomExercisesOnce()
                    if !hasRequestedHealthKit {
                        hasRequestedHealthKit = true
                        // #872 FM NO-GO migration. The 2026-05-19 cutover made
                        // Apple Foundation Models the global default and silently
                        // force-migrated existing `.llamaCpp` users onto it. FM
                        // later measured below the parity bar on the showstopper
                        // chat surface (80.5% vs the 92.7% Gemma baseline), so the
                        // NO-GO reverts the default to on-device Gemma/llama.cpp.
                        // Move existing users off the reverted FM default exactly
                        // once: reset any persisted `.foundationModels` preference
                        // so they land on the AIChooser "download on-device AI"
                        // CTA rather than a dead chat or a silently sub-bar
                        // backend. FM stays user-selectable from that chooser;
                        // re-promotion to default is gated on #874.
                        if !Preferences.didRunFMNoGoMigration {
                            Preferences.didRunFMNoGoMigration = true
                            if Preferences.preferredAIBackend == .foundationModels {
                                Preferences.preferredAIBackend = .llamaCpp
                                Log.app.info("FM NO-GO migration (#872): reset preferredAIBackend .foundationModels → .llamaCpp; user lands on the on-device download chooser")
                                // Only install the local backend when cloud is NOT
                                // configured. With a Nebius team key present, the
                                // cloud-default flip just below installs the remote
                                // backend, so loading the multi-GB GGUF here would
                                // burn CPU/battery on a model we immediately discard. (#948)
                                if !AppConfig.coachCloudConfigured {
                                    await AIBackendCoordinator.applyPreferredBackend()
                                }
                            }
                        }
                        // Drift Coach is cloud-first. On the first launch carrying a
                        // provisioned Nebius team key, default the chat backend to the
                        // cloud brain — even if a local model was previously downloaded
                        // (on-device is the fallback, not the default; it's slow on A19
                        // Pro where Metal degrades to CPU). One-time, so a user who later
                        // explicitly picks on-device keeps that choice. Users already on
                        // Apple Intelligence are untouched (only `.llamaCpp` flips).
                        if AppConfig.coachCloudConfigured, !Preferences.didDefaultCoachToCloud {
                            Preferences.didDefaultCoachToCloud = true
                            if Preferences.preferredAIBackend == .llamaCpp {
                                Preferences.preferredAIBackend = .remote
                                AIBackendCoordinator.installCoachBackend()
                                Log.app.info("Drift Coach: defaulted chat backend to cloud (Nebius team key)")
                            }
                        }
                        // First-launch restore: if this device's DB is fresh
                        // AND a backup is sitting in the user's iCloud Drive
                        // container, offer to restore before any other launch
                        // work. The sheet is dismissible — user can choose
                        // "Start Fresh" by canceling.
                        // `iCloudAvailable` is the single signal we need from BackupService here:
                        // - true → there's a usable iCloud Drive container to back up to or restore from
                        // - false → iCloud Drive is off / user signed out; skip both sheets silently
                        //
                        // Probe on a background thread first (per Apple's
                        // docs — main-thread calls to
                        // `forUbiquityContainerIdentifier:` early in
                        // launch return nil while the iCloud daemon is
                        // still initializing). Without this, devices
                        // with iCloud Drive ON were getting the
                        // misfiring "iCloud Drive is off" alert (#7 in
                        // the 2026-05-20 UI review).
                        await BackupService.shared.probeContainerURL()
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

                        // V7 rich-seed: once per simulator install, populate
                        // 60 days of weight + 14 days of food so the Today
                        // dashboard renders with real numbers (rings + meal
                        // timeline + body tile trend) instead of "no data".
                        // Gated by a UserDefaults flag so it doesn't re-seed
                        // on every launch. Bump the flag suffix to force
                        // a re-seed.
                        if !UserDefaults.standard.bool(forKey: "drift_debug_seeded_v1") {
                            DebugSeedData.seedRichTestData()
                            UserDefaults.standard.set(true, forKey: "drift_debug_seeded_v1")
                        }
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
