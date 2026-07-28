package drift.android

import android.util.Base64
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/// Blocking OkHttp facade over HTTP for the Swift side (#1136).
///
/// swift-corelibs-foundation's URLSession.data(for:) parks non-cancellably on
/// the Skip/Android runtime — its completion handler never fires, so every
/// RemoteLLMBackend call (Coach chat, meal/photo parse, workout scan) hangs
/// forever. OkHttpClient's blocking execute() is bounded by callTimeout: it
/// always returns or throws within the deadline, so the Swift continuation
/// dispatching it always resumes. Callers MUST invoke this off the main
/// thread (mirrors HealthConnectFacade's runBlocking rule).
class HttpFacade {

    private val client = OkHttpClient()

    /// Smoke test for the Swift↔Kotlin reflective bridge.
    fun ping(): String = "ok"

    /// Blocking POST. Returns {"status":Int,"bodyBase64":String} for any
    /// completed HTTP exchange (including non-2xx responses), or
    /// {"status":-1,"error":...} for any exception (timeout, unreachable
    /// host, TLS failure, …). NEVER throws across the bridge, matching every
    /// HealthConnectFacade method.
    fun post(urlString: String, headersJson: String, bodyBase64: String, timeoutMillis: Long): String {
        return try {
            val headers = JSONObject(headersJson)
            val contentType = if (headers.has("Content-Type")) headers.getString("Content-Type") else "application/json"
            val bodyBytes = Base64.decode(bodyBase64, Base64.NO_WRAP)
            val body = bodyBytes.toRequestBody(contentType.toMediaType())

            val requestBuilder = Request.Builder().url(urlString).post(body)
            val keys = headers.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                requestBuilder.header(key, headers.getString(key))
            }

            val call = client.newBuilder()
                .callTimeout(timeoutMillis, TimeUnit.MILLISECONDS)
                .build()
                .newCall(requestBuilder.build())

            call.execute().use { response ->
                val responseBytes = response.body?.bytes() ?: ByteArray(0)
                JSONObject()
                    .put("status", response.code)
                    .put("bodyBase64", Base64.encodeToString(responseBytes, Base64.NO_WRAP))
                    .toString()
            }
        } catch (e: Exception) {
            JSONObject().put("status", -1).put("error", (e.message ?: e.toString())).toString()
        }
    }
}
