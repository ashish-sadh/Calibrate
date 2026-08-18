import Foundation
import SkipFuse
import SwiftUI
import DriftCore

/// A logger for the DriftAndroid module.
let logger: Logger = Logger(subsystem: "com.drift.health", category: "DriftAndroid")

/// The shared top-level view for the app, loaded from the platform-specific App delegates below.
///
/// The default implementation merely loads the `ContentView` for the app and logs a message.
/* SKIP @bridge */public struct DriftAndroidRootView : View {
    /* SKIP @bridge */public init() {
    }

    public var body: some View {
        ContentView()
            .task {
                logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
            }
    }
}

/// Global application delegate functions.
///
/// These functions can update a shared observable object to communicate app state changes to interested views.
/* SKIP @bridge */public final class DriftAndroidAppDelegate : Sendable {
    /* SKIP @bridge */public static let shared = DriftAndroidAppDelegate()

    private init() {
    }

    /* SKIP @bridge */public func onInit() {
        lineBufferStandardOutput()
        Log.app.info("Drift Android launched")
        logger.debug("onInit")
        // Android half of the platform-health seam (HealthKitService on iOS).
        // onInit runs on Android's main thread (Application.onCreate), and the
        // seam must be set synchronously — before the first view reads it.
        MainActor.assumeIsolated {
            DriftPlatform.health = HealthConnectService.shared
            // Durable key-value seam (#1108): Skip's UserDefaults never flushes
            // to disk, so route settings + the active workout + sync anchors
            // through SQLite. Installed here (before views); its cache is primed
            // off-main during warm-up (CoreResourcesBootstrap) so it never
            // touches AppDatabase.shared on this main thread.
            DriftPlatform.keyValueStore = DbKeyValueStore()
            // HTTP transport seam (#1136): swift-corelibs-foundation's
            // URLSession parks non-cancellably on Skip, so RemoteLLMBackend
            // (Coach/meal/photo/scan) routes through the OkHttp facade instead.
            DriftPlatform.httpSession = AndroidHTTPSession()
            // IMMEDIATE-notify seam only (#1162). Nothing on Android mirrors
            // iOS's NotificationService.refreshScheduledAlerts() — SCHEDULED
            // reminders need a portable planner + a delivery seam, which is
            // #1146's scope, not this wiring's (#1214).
            DriftPlatform.notifier = AndroidLocalNotifier()
            // Image-in seam (#1128): system Photo Picker → downscaled JPEG Data
            // via the polled ImagePickerFacade Activity-result bridge.
            DriftPlatform.imagePicker = ImagePickerService()
            // File-in seam (#1175): SAF OpenDocument → raw file Data via the
            // polled DocumentPickerFacade bridge. iOS leaves this nil because
            // SwiftUI's .fileImporter is native there.
            DriftPlatform.documentImporter = DocumentImporterService()
            // UI-refresh kick (#1180): bridged @Observable writes never schedule
            // a Compose recomposition, so without this the screen repaints only
            // when unrelated window machinery pokes it — taps look dead even
            // after they've already written their rows.
            DriftPlatform.uiRefreshKick = { ComposeKickService.kick() }
            // Register all AI tools in ToolRegistry — the same call
            // DriftApp.init() makes on iOS. Without it the registry is empty,
            // every Coach turn resolves to "unknown tool", and
            // `ToolRegistry.toolsJSONString` returns nil so cloud requests
            // carry no function schemas at all (#1209). Pure closure capture,
            // so it is safe to run synchronously here; PhotoLogTool is
            // iOS-only (Keychain + CloudVision) and intentionally absent.
            ToolRegistration.registerAll()
            // #1240: start the off-main DB open NOW. `warmTask` is a lazy
            // static, so until this line the open didn't even begin until the
            // first awaiter was scheduled — leaving a window in which a
            // MainActor lifecycle task could be the first toucher of
            // AppDatabase.shared and eat openAndSeed() on the main thread.
            // Last line in this block on purpose: the warm task consumes
            // DriftPlatform.keyValueStore (prime()), installed above.
            CoreResourcesBootstrap.beginWarmUp()
        }
    }

    /* SKIP @bridge */public func onLaunch() {
        logger.debug("onLaunch")
        HealthConnectService.bridgeSmokeTest()
        Task { @MainActor in
            await CoreResourcesBootstrap.warmUpDatabase()
            // Two more DriftApp.init() mirrors (#1214 — same class as #1209 /
            // #1212). Both ride `Preferences`, which on Android reaches
            // AppDatabase through DbKeyValueStore, so they belong HERE, after
            // warm-up — never in onInit (see that method's own comment).
            //
            // Stamp the install date once so the 7-day Feedback activation
            // banner (#759) has a stable anchor. The anchor is "first launch",
            // which happens exactly once — a later port cannot backfill it.
            // Idempotent: only writes when unset. (DriftApp.swift:26)
            Preferences.seedInstallDateIfNeeded()
            // One-time coach-voice pref migrations (#968). A native Android
            // install is unlikely to carry the poisoned pre-#937 value, but a
            // restored cross-platform backup (#1094) can — this is the heal.
            // Idempotent. (DriftApp.swift:32)
            Preferences.migrateCoachVoiceIfNeeded()
            // Ship whatever the last session queued. After warm-up so the
            // flusher never races the DB open (#1112 lesson).
            TelemetryService.shared.event(TelemetryEvent.appOpen)
            TelemetryService.shared.flush()
            // Health Connect catch-up first, so the trend below sees weights
            // logged in other apps. Scoped with `if` rather than the previous
            // `guard ... else { return }`: an unavailable Health Connect must
            // not skip the launch refresh that follows it.
            if let health = DriftPlatform.health, health.isAvailable {
                try? await health.requestAuthorization()
                let synced = (try? await health.syncWeight()) ?? 0
                if synced > 0 { logger.info("HealthConnect: \(synced) weight days synced at launch") }
            }
            // The rest of DriftApp.init()'s launch sequence (#1212 — same class
            // as #1209). Without these, the weight trend is populated only as a
            // side effect of the Today tab and `TDEEEstimator.current` stays nil
            // forever, so FoodService (:374, :794) and AIRuleEngine (:182) fall
            // back to a flat 2000 kcal on every entry path that doesn't visit
            // Today first — Coach opened from another tab, a deep link, a cold
            // start restored onto another tab.
            //
            // Order is a contract, not a preference: TDEEEstimator.refresh()
            // reads WeightTrendService.shared.latestWeightKg. iOS runs them in
            // this order for the same reason (DriftApp.swift:228 then :233).
            WeightTrendService.shared.refresh()
            await TDEEEstimator.shared.refresh()
        }
    }

    /* SKIP @bridge */public func onResume() {
        logger.debug("onResume")
        // Cheap anchored catch-up — picks up weights logged in other apps
        // while Drift was backgrounded (mirrors the iOS foreground sync).
        Task { @MainActor in
            // #1240: warm-up FIRST. syncWeight() writes through
            // AppDatabase.shared, so on a cold start this task races
            // onLaunch's warm-up and the winner pays the open+seed on main.
            await CoreResourcesBootstrap.warmUpDatabase()
            guard let health = DriftPlatform.health, health.isAvailable else { return }
            _ = try? await health.syncWeight()
        }
        // Social alerts + leaderboard publish — the same shared entry point the
        // iOS foreground runs, so the sync policy can't diverge between
        // platforms (SocialSync).
        Task { @MainActor in
            // #1240 (the proven ANR): SocialAlertPoll.run()'s first statement is
            // `SharingService.shared`, whose `db: AppDatabase = .shared` default
            // argument forces the lazy open — openAndSeed() -> seedFoodsFromJSON()
            // -> COUNT(*) -> pread64, all inside nested swift_once on main.
            await CoreResourcesBootstrap.warmUpDatabase()
            await SocialSync.onForeground()
        }
    }

    /* SKIP @bridge */public func onPause() {
        logger.debug("onPause")
        // Snapshot the in-flight Coach conversation (#1214, mirror of
        // DriftApp.swift:64). AIChatViewModel (SharedUI, live on Android)
        // listens for this and writes convState to conversation_state.json, so
        // an Android process death mid-flow resumes instead of forgetting.
        // Android kills backgrounded apps routinely — iOS gets this for free
        // from its scenePhase handler and Android had nothing.
        //
        // Posted from onPause ONLY: onPause always precedes onStop, and iOS
        // posts once per backgrounding — double-posting would just re-encode
        // the same snapshot. Deliberately ahead of the isWarm gate below: the
        // listener touches no database, only in-memory state and a JSON file,
        // so a backgrounding during a cold start must not lose the snapshot.
        NotificationCenter.default.post(name: .saveConversationState, object: nil)
        // Drain the telemetry outbox on the way out (mirror of the iOS
        // scenePhase flush in DriftApp) — a session's events ship together.
        //
        // #1240: `TelemetryService.shared` is built as
        // `TelemetryService(db: AppDatabase.shared, …)`, so merely TOUCHING the
        // lazy static before warm-up force-opens the DB on main — and Android
        // backgrounds within ~1s of a cold start (also on every Skip
        // permission-relaunch). Skipping pre-warm is lossless: no event of THIS
        // session can exist yet (onLaunch's `event(appOpen)` runs after its own
        // await), and flush() swallows errors by design, so a previous
        // session's leftovers simply ride the next onLaunch flush.
        MainActor.assumeIsolated {
            guard CoreResourcesBootstrap.isWarm else { return }
            TelemetryService.shared.flush()
        }
    }

    /* SKIP @bridge */public func onStop() {
        logger.debug("onStop")
        // #1240 — same pre-warm gate as onPause above.
        MainActor.assumeIsolated {
            guard CoreResourcesBootstrap.isWarm else { return }
            TelemetryService.shared.flush()
        }
    }

    /* SKIP @bridge */public func onDestroy() {
        logger.debug("onDestroy")
    }

    /* SKIP @bridge */public func onLowMemory() {
        logger.debug("onLowMemory")
    }
}
