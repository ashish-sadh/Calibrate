import Foundation
import SkipFuse
import DriftCore

/// Android side of the `LocalNotifier` seam (#1162), bridging to
/// `NotificationFacade.kt` through Skip's reflection bridge.
///
/// Everything on the Kotlin side is synchronous on purpose: `AnyDynamicObject`
/// cannot call `suspend` functions (no Continuation support), the same
/// constraint that shaped `HealthConnectFacade` and `HttpFacade`.
///
/// Every bridge call is `#if os(Android)`-gated, exactly like
/// `HealthConnectService`: this file also compiles in Skip's DARWIN bridging
/// pass, where `SkipBridge.AnyDynamicObject` isn't linked, and an ungated
/// reference fails at link time with "Undefined symbols … AnyDynamicObject"
/// rather than anything that points at the real cause.
struct AndroidLocalNotifier: LocalNotifier {

    private static let facadeClass = "drift.android.NotificationFacade"

    func requestAuthorization() async -> Bool {
        #if os(Android)
        // The ask itself is fire-and-forget: it relaunches the activity
        // (#1096), so the answer arrives on the NEXT authorization check
        // rather than from this call.
        let _: Void? = try? AnyDynamicObject(className: Self.facadeClass, arguments: [])
            .requestPermission()
        return await isAuthorized()
        #else
        return false
        #endif
    }

    func isAuthorized() async -> Bool {
        #if os(Android)
        return (try? AnyDynamicObject(className: Self.facadeClass, arguments: [])
            .isAuthorized() as Bool?) ?? false
        #else
        return false
        #endif
    }

    func notify(id: String, title: String, body: String, deepLink: String?) async {
        #if os(Android)
        // Kotlin's parameter is nullable, but the bridge is happier with a
        // concrete String — empty means "no link" on the Kotlin side.
        let _: Void? = try? AnyDynamicObject(className: Self.facadeClass, arguments: [])
            .notify(id, title, body, deepLink ?? "")
        #endif
    }
}
