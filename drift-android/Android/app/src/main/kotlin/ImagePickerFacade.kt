package drift.android

import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.util.Base64
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import java.io.ByteArrayOutputStream

/// Photo-library pick facade for the Swift side (#1128) — the image-in seam.
///
/// An Activity-result is an inherently deferred callback, and Skip's
/// AnyDynamicObject bridge cannot deliver a Kotlin→Swift callback (nor call
/// `suspend`), so the result comes back the same way HealthConnectFacade
/// recovers permission state: mutable state on the companion object that the
/// Swift side polls. Swift instantiates a FRESH facade instance per call, so
/// ALL state lives on the companion — instance fields would be lost.
///
/// Uses ActivityResultContracts.PickVisualMedia (the modern Photo Picker):
/// no runtime storage permission on ANY API level, which also sidesteps the
/// duplicate-MainActivity permission-relaunch quirk entirely (nothing to ask).
/// Decode + downscale + JPEG-encode live HERE because Swift-on-Android has no
/// image APIs; the picked photo crosses the bridge exactly once, as base64.
class ImagePickerFacade {

    companion object {
        /// Registered by MainActivity.onCreate (Activity-lifecycle-bound contract).
        @JvmField
        var pickLauncher: ActivityResultLauncher<PickVisualMediaRequest>? = null

        /// 0 idle · 1 pending (picker up / decoding) · 2 done (resultB64 set) ·
        /// 3 cancelled-or-failed. Volatile: written on main + decode thread,
        /// polled from Swift's background facade queue.
        @Volatile private var status = 0
        @Volatile private var resultB64: String? = null
        @Volatile private var maxEdge = 2048
        @Volatile private var quality = 70 // Bitmap.compress scale, 0..100

        /// MainActivity's registered callback lands here (main thread).
        fun onPicked(uri: Uri?) {
            if (uri == null) { // user cancelled the picker
                status = 3
                return
            }
            // Decode + downscale + encode off-main — a full-res camera-roll
            // photo decode on the main thread would ANR the picker dismissal.
            Thread {
                val bytes = decodeDownscaleJpeg(uri, maxEdge, quality)
                if (bytes == null) {
                    status = 3
                } else {
                    resultB64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
                    status = 2
                }
            }.start()
        }

        /// ImageDecoder (API 28+) rather than BitmapFactory: it auto-applies
        /// EXIF orientation (portrait photos come out right-side-up) and has
        /// built-in downscale via setTargetSize — no exifinterface dependency.
        private fun decodeDownscaleJpeg(uri: Uri, maxEdge: Int, q: Int): ByteArray? = try {
            val ctx = skip.foundation.ProcessInfo.processInfo.androidContext
            val src = ImageDecoder.createSource(ctx.contentResolver, uri)
            val bmp = ImageDecoder.decodeBitmap(src) { decoder, info, _ ->
                val w = info.size.width
                val h = info.size.height
                val longEdge = maxOf(w, h)
                if (longEdge > maxEdge) {
                    val scale = maxEdge.toDouble() / longEdge.toDouble()
                    decoder.setTargetSize(
                        (w * scale).toInt().coerceAtLeast(1),
                        (h * scale).toInt().coerceAtLeast(1)
                    )
                }
                // Hardware bitmaps can't be compress()ed — force software.
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
            val out = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, q, out)
            out.toByteArray()
        } catch (t: Throwable) {
            logger.info("ImagePickerFacade decode failed: ${t}")
            null
        }
    }

    /// Fire the picker. MUST be called on the main thread (Swift calls via
    /// MainActor = Android main looper). Returns false if the launcher was
    /// never registered (Activity not created) — callers treat as cancel.
    fun launch(maxEdge: Int, q: Int): Boolean {
        Companion.maxEdge = maxEdge
        Companion.quality = q
        resultB64 = null
        val launcher = pickLauncher
        if (launcher == null) {
            status = 3
            return false
        }
        status = 1
        launcher.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
        return true
    }

    /// Poll the pick state — see the status legend on the companion.
    fun poll(): Int = status

    /// One-shot: hand the base64 JPEG to Swift and reset to idle.
    fun takeResult(): String? {
        val r = resultB64
        resultB64 = null
        status = 0
        return r
    }
}
