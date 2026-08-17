package drift.android

import android.net.Uri
import android.util.Base64
import androidx.activity.result.ActivityResultLauncher

/// Document-pick facade for the Swift side (#1175) — the file-in seam.
///
/// An Activity-result is an inherently deferred callback, and Skip's
/// AnyDynamicObject bridge cannot deliver a Kotlin→Swift callback (nor call
/// `suspend`), so the result comes back the same way ImagePickerFacade returns
/// a photo: mutable state on the companion object that the Swift side polls.
/// Swift instantiates a FRESH facade instance per call, so ALL state lives on
/// the companion — instance fields would be lost.
///
/// Uses ActivityResultContracts.OpenDocument (SAF): the returned `content://`
/// Uri carries a transient read grant, so this needs no runtime permission on
/// any API level, no `<queries>`, and no FileProvider. Unlike the image seam
/// there is nothing to decode — the file's own bytes cross the bridge once, as
/// base64.
class DocumentPickerFacade {

    companion object {
        /// Registered by MainActivity.onCreate (Activity-lifecycle-bound contract).
        @JvmField
        var openLauncher: ActivityResultLauncher<Array<String>>? = null

        /// 0 idle · 1 pending (picker up / reading) · 2 done (resultB64 set) ·
        /// 3 cancelled-or-failed. Volatile: written on main + reader thread,
        /// polled from Swift's background facade queue.
        @Volatile private var status = 0
        @Volatile private var resultB64: String? = null

        /// MainActivity's registered callback lands here (main thread).
        fun onPicked(uri: Uri?) {
            if (uri == null) { // user cancelled the picker
                status = 3
                return
            }
            // Read off-main — a multi-MB CSV read on the main thread would ANR
            // the picker dismissal (same rule as the image facade's decode).
            Thread {
                val bytes = try {
                    val ctx = skip.foundation.ProcessInfo.processInfo.androidContext
                    ctx.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                } catch (t: Throwable) {
                    logger.info("DocumentPickerFacade read failed: ${t}")
                    null
                }
                if (bytes == null) {
                    status = 3
                } else {
                    resultB64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
                    status = 2
                }
            }.start()
        }
    }

    /// Fire the picker. MUST be called on the main thread (Swift calls via
    /// MainActor = Android main looper). `mimeCsv` is the comma-joined MIME
    /// filter — a single String because multi-String facade args are proven
    /// across the bridge and Array<String> args are not. Returns false if the
    /// launcher was never registered (Activity not created) — callers treat as
    /// cancel.
    fun launch(mimeCsv: String): Boolean {
        resultB64 = null
        val launcher = openLauncher
        if (launcher == null) {
            status = 3
            return false
        }
        val mimes = mimeCsv.split(",").filter { it.isNotBlank() }.toTypedArray()
        status = 1
        launcher.launch(if (mimes.isEmpty()) arrayOf("*/*") else mimes)
        return true
    }

    /// Poll the pick state — see the status legend on the companion.
    fun poll(): Int = status

    /// One-shot: hand the base64 file bytes to Swift and reset to idle.
    fun takeResult(): String? {
        val r = resultB64
        resultB64 = null
        status = 0
        return r
    }
}
