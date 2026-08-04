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

    /// Blocking request for any HTTP method. Returns
    /// {"status":Int,"bodyBase64":String,"headersJson":String} for any
    /// completed HTTP exchange (including non-2xx responses), or
    /// {"status":-1,"error":...} for any exception (timeout, unreachable
    /// host, TLS failure, …). NEVER throws across the bridge, matching every
    /// HealthConnectFacade method.
    ///
    /// `method` matters beyond correctness: PostgREST reads it (GET reads,
    /// PATCH/DELETE writes) and OkHttp throws IllegalArgumentException on the
    /// wrong method/body pairing, so the body rule below is exact — GET/HEAD
    /// never carry one, DELETE carries one only when there are bytes to send,
    /// and POST/PUT/PATCH always do (OkHttp requires non-null there even for
    /// an empty body).
    fun request(urlString: String, method: String, headersJson: String, bodyBase64: String, timeoutMillis: Long): String {
        return try {
            val headers = JSONObject(headersJson)
            val contentType = if (headers.has("Content-Type")) headers.getString("Content-Type") else "application/json"
            val bodyBytes = Base64.decode(bodyBase64, Base64.NO_WRAP)
            val verb = method.uppercase()
            val body = when {
                verb == "GET" || verb == "HEAD" -> null
                verb == "DELETE" && bodyBytes.isEmpty() -> null
                else -> bodyBytes.toRequestBody(contentType.toMediaType())
            }

            val requestBuilder = Request.Builder().url(urlString).method(verb, body)
            val keys = headers.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                requestBuilder.header(key, headers.getString(key))
            }

            // callTimeout alone leaves OkHttp's 10s default readTimeout in
            // place — an inactivity gap timeout, shorter than and independent
            // of callTimeout. Long, quiet-then-answers calls (workout scan's
            // vision reads run 40-240s with byte-silent gaps, matching the
            // exact field failure RemoteLLMBackend.swift documents for the
            // Darwin streaming path) would fail at ~10s otherwise (#1136 QA).
            val call = client.newBuilder()
                .callTimeout(timeoutMillis, TimeUnit.MILLISECONDS)
                .readTimeout(timeoutMillis, TimeUnit.MILLISECONDS)
                .writeTimeout(timeoutMillis, TimeUnit.MILLISECONDS)
                .build()
                .newCall(requestBuilder.build())

            call.execute().use { response ->
                val responseBytes = response.body?.bytes() ?: ByteArray(0)
                // Response headers matter to consumers past RemoteLLMBackend:
                // PostgREST returns the row count in Content-Range, and the
                // GoTrue/PostgREST error path is often header-only. Repeated
                // names collapse comma-joined, matching HTTPURLResponse.
                val responseHeaders = JSONObject()
                for (name in response.headers.names()) {
                    responseHeaders.put(name, response.headers(name).joinToString(", "))
                }
                JSONObject()
                    .put("status", response.code)
                    .put("bodyBase64", Base64.encodeToString(responseBytes, Base64.NO_WRAP))
                    .put("headersJson", responseHeaders.toString())
                    .toString()
            }
        } catch (e: Exception) {
            JSONObject().put("status", -1).put("error", (e.message ?: e.toString())).toString()
        }
    }
}
