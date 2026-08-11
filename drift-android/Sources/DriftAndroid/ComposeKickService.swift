import Foundation
import SkipFuse

/// Swift half of the `DriftPlatform.uiRefreshKick` seam (#1180), bridging to
/// `ComposeKick.kt` through Skip's reflection bridge.
///
/// Bridged `@Observable` writes bump their Compose state slots but never
/// schedule a recomposition, so the UI repaints only when unrelated window
/// machinery (IME, focus change, a sheet transition) happens to trigger the
/// next composition pass. `ComposeKick.kick()` posts that poke programmatically
/// from a genuine main-Looper message; this is the reflective call into it.
///
/// Fire-and-forget and synchronous on the Swift side — the deferral happens
/// Kotlin-side in `Handler.post`, so the `suspend`-interop blocker that shaped
/// `HealthConnectFacade`/`HttpFacade` doesn't apply here. Bursts coalesce in
/// Kotlin, so a per-keystroke call costs one JNI hop, not one recomposition.
///
/// Every bridge call is `#if os(Android)`-gated, exactly like
/// `AndroidLocalNotifier`: this file also compiles in Skip's DARWIN bridging
/// pass, where `SkipBridge.AnyDynamicObject` isn't linked, and an ungated
/// reference fails at link time with "Undefined symbols … AnyDynamicObject"
/// rather than anything that points at the real cause.
enum ComposeKickService {

    private static let facadeClass = "drift.android.ComposeKick"

    static func kick() {
        #if os(Android)
        // `let _: Void?` is load-bearing, not style: without the annotation the
        // reflective call is an ambiguous `dynamicallyCall(withArguments:)`.
        // The facade is constructed per call rather than cached — a cached
        // `AnyDynamicObject` is non-Sendable and can't live in a `static let`
        // — which is what every other facade in this directory does too.
        let _: Void? = try? AnyDynamicObject(className: facadeClass, arguments: [])
            .kick()
        #endif
    }
}
