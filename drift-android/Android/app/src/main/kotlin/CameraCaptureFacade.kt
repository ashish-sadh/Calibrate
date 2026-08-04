package drift.android

import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.util.Base64
import androidx.activity.result.ActivityResultLauncher
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.ByteArrayOutputStream
import java.io.File

/// Camera-capture facade for the Swift side (#1111) — the "Take Photo" half
/// of Snap meal logging. Sibling of `ImagePickerFacade` (gallery pick, #1128)
/// and reuses its exact shape: an Activity-result is an inherently deferred
/// callback, and Skip's AnyDynamicObject bridge can neither call `suspend`
/// functions nor deliver a Kotlin→Swift callback, so the result comes back
/// as mutable state on the companion object that Swift polls. Swift
/// instantiates a FRESH facade instance per call, so ALL state lives on the
/// companion — instance fields would be lost.
///
/// `TakePicture` needs a destination the camera app can WRITE into, unlike
/// `PickVisualMedia` which just hands back a readable content:// Uri — so
/// this facade creates a temp file first and shares it via FileProvider.
class CameraCaptureFacade {

    companion object {
        /// Registered by MainActivity.onCreate (Activity-lifecycle-bound contract).
        @JvmField
        var cameraLauncher: ActivityResultLauncher<Uri>? = null
        @JvmField
        var permissionLauncher: ActivityResultLauncher<String>? = null

        /// 0 idle · 1 pending (camera up / decoding) · 2 done (resultB64 set) ·
        /// 3 cancelled-or-failed. Volatile: written on main + decode thread,
        /// polled from Swift's background facade queue.
        @Volatile private var status = 0
        @Volatile private var resultB64: String? = null
        @Volatile private var pendingUri: Uri? = null
        @Volatile private var maxEdge = 1024
        @Volatile private var quality = 70

        /// 0 undetermined · 1 granted · 2 denied. Set by the permission
        /// launcher's callback (registered in MainActivity).
        @Volatile private var permissionStatus = 0

        private val context: Context
            get() = skip.foundation.ProcessInfo.processInfo.androidContext

        /// MainActivity's registered TakePicture callback lands here (main thread).
        fun onCaptured(success: Boolean) {
            val uri = pendingUri
            if (!success || uri == null) {
                status = 3
                return
            }
            // Decode + downscale + encode off-main — matches ImagePickerFacade.
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

        /// MainActivity's registered RequestPermission callback lands here.
        fun onPermissionResult(granted: Boolean) {
            permissionStatus = if (granted) 1 else 2
        }

        private fun decodeDownscaleJpeg(uri: Uri, maxEdge: Int, q: Int): ByteArray? = try {
            val src = ImageDecoder.createSource(context.contentResolver, uri)
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
            logger.info("CameraCaptureFacade decode failed: ${t}")
            null
        }
    }

    /// True when CAMERA is already granted.
    fun hasPermission(): Boolean =
        ContextCompat.checkSelfPermission(context, android.Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED

    /// Fire the system CAMERA permission prompt. MUST be called on the main
    /// thread. Result recovered via `permissionPoll()`.
    fun requestPermission(): Boolean {
        permissionStatus = 0
        val launcher = permissionLauncher ?: return false
        launcher.launch(android.Manifest.permission.CAMERA)
        return true
    }

    /// 0 pending · 1 granted · 2 denied.
    fun permissionPoll(): Int = permissionStatus

    /// Fire the camera. MUST be called on the main thread (Swift calls via
    /// MainActor = Android main looper). Creates a temp cache file the camera
    /// app writes into, shared via FileProvider. Returns false if the
    /// launcher was never registered or the temp file/Uri couldn't be made —
    /// callers treat as cancel.
    fun launch(maxEdge: Int, q: Int): Boolean {
        Companion.maxEdge = maxEdge
        Companion.quality = q
        resultB64 = null
        val launcher = cameraLauncher
        if (launcher == null) {
            status = 3
            return false
        }
        val uri = try {
            val file = File.createTempFile("capture", ".jpg", context.cacheDir)
            FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        } catch (t: Throwable) {
            logger.info("CameraCaptureFacade temp file failed: ${t}")
            null
        }
        if (uri == null) {
            status = 3
            return false
        }
        pendingUri = uri
        status = 1
        launcher.launch(uri)
        return true
    }

    /// Poll the capture state — see the status legend on the companion.
    fun poll(): Int = status

    /// One-shot: hand the base64 JPEG to Swift and reset to idle.
    fun takeResult(): String? {
        val r = resultB64
        resultB64 = null
        status = 0
        return r
    }
}
