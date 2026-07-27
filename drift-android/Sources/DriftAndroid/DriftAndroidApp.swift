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
        logger.debug("onInit")
        // Android half of the platform-health seam (HealthKitService on iOS).
        // onInit runs on Android's main thread (Application.onCreate), and the
        // seam must be set synchronously — before the first view reads it.
        MainActor.assumeIsolated {
            DriftPlatform.health = HealthConnectService.shared
        }
    }

    /* SKIP @bridge */public func onLaunch() {
        logger.debug("onLaunch")
        HealthConnectService.bridgeSmokeTest()
        Task { @MainActor in
            await CoreResourcesBootstrap.warmUpDatabase()
            guard let health = DriftPlatform.health, health.isAvailable else { return }
            try? await health.requestAuthorization()
            let synced = (try? await health.syncWeight()) ?? 0
            if synced > 0 { logger.info("HealthConnect: \(synced) weight days synced at launch") }
        }
    }

    /* SKIP @bridge */public func onResume() {
        logger.debug("onResume")
        // Cheap anchored catch-up — picks up weights logged in other apps
        // while Drift was backgrounded (mirrors the iOS foreground sync).
        Task { @MainActor in
            guard let health = DriftPlatform.health, health.isAvailable else { return }
            _ = try? await health.syncWeight()
        }
    }

    /* SKIP @bridge */public func onPause() {
        logger.debug("onPause")
    }

    /* SKIP @bridge */public func onStop() {
        logger.debug("onStop")
        Self.flushDefaults()
    }

    /* SKIP @bridge */public func onDestroy() {
        logger.debug("onDestroy")
    }

    /* SKIP @bridge */public func onLowMemory() {
        logger.debug("onLowMemory")
    }

    // #1108: SkipFoundation's UserDefaults writes via SharedPreferences.apply()
    // (async), and its synchronize() is a no-op — on this build the async
    // flush never durably lands before process reclaim. Force a synchronous
    // commit() when the Activity is hidden. MUST stay synchronous on the
    // onStop thread — dispatching off-main risks not completing before
    // process death, which defeats the purpose.
    #if os(Android)
    private static func flushDefaults() {
        _ = try? AnyDynamicObject(className: "drift.android.AndroidPrefsFacade", arguments: []).flush() as Bool?
    }
    #else
    private static func flushDefaults() {}
    #endif
}
