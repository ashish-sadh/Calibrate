package drift.android

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/// Blocking facade over Android notifications for the Swift side (#1162).
///
/// Mirrors `AppleLocalNotifier` on iOS so the POLICY (who may be interrupted by
/// what) stays in shared DriftCore and only the delivery differs. Everything
/// here is synchronous — Skip's `AnyDynamicObject` reflection bridge cannot call
/// `suspend` functions, so nothing in this file may be a coroutine.
///
/// PERMISSION NOTE: on API 33+ posting requires the `POST_NOTIFICATIONS`
/// runtime grant. Asking for it relaunches the activity (#1096) and looks like
/// a crash-to-Today, so `requestPermission()` is only ever called from a
/// deliberate user action — never lazily while rendering.
class NotificationFacade {

    private val context: Context
        get() = skip.foundation.ProcessInfo.processInfo.androidContext

    private val channelID = "drift_social_alerts"

    /// Created lazily and idempotently: re-creating an existing channel is a
    /// no-op, and doing it here means no launch-time ordering requirement.
    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(channelID) != null) return
        val channel = NotificationChannel(
            channelID,
            "Coaching & messages",
            // DEFAULT, not HIGH: these are worth a glance, not a full-screen
            // interruption. The policy already decided that only coaching
            // relationships get here at all.
            NotificationManager.IMPORTANCE_DEFAULT
        )
        channel.description = "Messages from your coach or clients, and connection requests"
        manager.createNotificationChannel(channel)
    }

    /// True when we may post. On API < 33 this is always true (no runtime
    /// grant existed), so the Swift side needs no version branching.
    fun isAuthorized(): Boolean {
        if (Build.VERSION.SDK_INT >= 33) {
            val granted = ContextCompat.checkSelfPermission(
                context, "android.permission.POST_NOTIFICATIONS"
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) return false
        }
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    /// Hand the ask to MainActivity, which owns the ActivityResult plumbing —
    /// the same Activity-lifecycle-bound contract HealthConnectFacade uses for
    /// its permission launcher.
    fun requestPermission() {
        if (Build.VERSION.SDK_INT < 33) return
        permissionRequester?.invoke()
    }

    /// `id` de-duplicates: posting the same tag replaces rather than stacks, so
    /// a poll that runs twice over one unread message notifies once.
    /// `deepLink` empty means "no link": the Swift bridge passes a concrete
    /// String rather than a nullable one, so emptiness is the absent signal.
    fun notify(id: String, title: String, body: String, deepLink: String?) {
        if (!isAuthorized()) return
        ensureChannel()

        val builder = NotificationCompat.Builder(context, channelID)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)

        if (!deepLink.isNullOrEmpty()) {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(deepLink)).apply {
                setPackage(context.packageName)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            builder.setContentIntent(
                PendingIntent.getActivity(context, id.hashCode(), intent, flags)
            )
        }

        // Tag = our stable id, so replacement works; the numeric id is derived
        // from it rather than incrementing, which would stack duplicates.
        NotificationManagerCompat.from(context)
            .notify(id, id.hashCode(), builder.build())
    }

    companion object {
        /// Registered by MainActivity so the runtime permission ask goes
        /// through the Activity that owns the result callback.
        @JvmField
        var permissionRequester: (() -> Unit)? = null
    }
}
