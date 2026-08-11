package drift.android

import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.snapshots.Snapshot
import java.util.concurrent.atomic.AtomicBoolean

/// Forces one Compose recomposition on demand (#1180).
///
/// Bridged `@Observable` writes DO bump their Compose `MutableState` slots —
/// even a plain synchronous write from a `Button` action, which skip-fuse-ui
/// dispatches via `assumeMainActorUnchecked { action() }` straight on the Java
/// main thread — but recomposition is never scheduled from a Swift execution
/// context. The UI therefore repaints only on the next composition pass that
/// real window machinery triggers (IME show/hide, focus change, sheet
/// transition). To the user that reads as a dead tap: the Coach's suggestion
/// pills paint nothing, the send button stays disabled while the keyboard is
/// up, and a review sheet that already wrote its rows looks un-tapped — which
/// is how one tap became three duplicate `food_entry` rows.
///
/// `kick()` is that missing poke, made programmatic. From a genuine main-Looper
/// message it pulls two levers:
///   1. `Snapshot.sendApplyNotifications()` flushes pending snapshot applies.
///   2. Bumping `rootTick`, which `Main.kt`'s composition root reads, forcing a
///      root-scope invalidation that re-executes the bridged tree (unstable
///      bridged children can't skip) and so repaints every pending Swift value.
///
/// Lever 2 is the load-bearing one — measured, not assumed. Building with the
/// `rootTick` bump commented out and only the snapshot flush live left the pill
/// tap unpainted even at +2s, identical to no kick at all. So the defect is not
/// a stalled apply-notification pipeline: the composition simply never
/// registered as a reader of the bridged slots, leaving invalidation nothing to
/// target. The flush is kept because it costs nothing and orders the applies
/// before the re-execution.
///
/// The `AtomicBoolean` coalesces bursts — a keystroke run, or a handler that
/// writes ten properties — into one recomposition per Looper drain.
class ComposeKick {
    fun kick() {
        Companion.kick()
    }

    companion object {
        val rootTick = mutableStateOf(0)
        private val pending = AtomicBoolean(false)
        private val handler = Handler(Looper.getMainLooper())

        fun kick() {
            if (pending.compareAndSet(false, true)) {
                handler.post {
                    pending.set(false)
                    Snapshot.sendApplyNotifications()
                    rootTick.value += 1
                }
            }
        }
    }
}
