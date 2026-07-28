import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Categorized failures from the sharing backend, so the UI can tell a
/// transient hiccup (retry) from something the user must act on (re-auth,
/// username taken, not connected).
public enum SharingError: Error, Equatable, Sendable {
    case notConfigured          // no backend URL/key compiled in
    case notSignedIn            // an authed call with no session
    case network(String)        // transport failure — offline, timeout
    case http(Int, String)      // non-2xx with server message
    case conflict(String)       // 409 — e.g. username already taken
    case forbidden              // 401/403 — RLS denied / token expired
    case decoding(String)
}

/// Thin HTTP transport for Supabase (PostgREST + GoTrue auth). Buffered,
/// non-streaming HTTPS — the same class of client as `RemoteLLMBackend`, reusing
/// its `HTTPDataSession` seam so one code path serves iOS + Android (Skip Fuse
/// has no async streaming, but plain request/response works everywhere).
///
/// Stateless w.r.t. identity: every authed call takes an access token from the
/// caller (`SharingService` owns the session + refresh). The anon key rides on
/// every request as `apikey`; RLS decides what the bearer token may see.
public struct SyncClient: Sendable {

    private let baseURL: String
    private let anonKey: String
    private let session: any HTTPDataSession
    private let timeout: TimeInterval

    public init(baseURL: String = AppConfig.syncBaseURL,
                anonKey: String = AppConfig.syncAnonKey,
                session: any HTTPDataSession = URLSession.shared,
                timeout: TimeInterval = 20) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.session = session
        self.timeout = timeout
    }

    public var isConfigured: Bool { !baseURL.isEmpty && !anonKey.isEmpty }

    // MARK: - REST (PostgREST)

    /// GET `<base>/rest/v1/<path>` and decode `[T]`. `path` includes the table
    /// and any PostgREST query (`profiles?username=ilike.*ash*&select=...`).
    public func restGet<T: Decodable>(_ path: String, token: String?) async throws -> [T] {
        let data = try await send(method: "GET", url: restURL(path), token: token, body: nil,
                                  prefer: nil)
        return try decode([T].self, from: data)
    }

    /// POST a row (or rows) and return the inserted representation decoded as
    /// `[T]` (PostgREST `Prefer: return=representation`).
    @discardableResult
    public func restInsert<T: Decodable>(_ table: String, body: Any, token: String?,
                                         upsert: Bool = false) async throws -> [T] {
        var prefer = "return=representation"
        if upsert { prefer += ",resolution=merge-duplicates" }
        let data = try await send(method: "POST", url: restURL(table), token: token,
                                  body: body, prefer: prefer)
        return try decode([T].self, from: data)
    }

    /// PATCH rows matched by `query` (`friendships?id=eq.<uuid>`), returning the
    /// updated representation.
    @discardableResult
    public func restUpdate<T: Decodable>(_ query: String, body: Any, token: String?) async throws -> [T] {
        let data = try await send(method: "PATCH", url: restURL(query), token: token,
                                  body: body, prefer: "return=representation")
        return try decode([T].self, from: data)
    }

    // MARK: - Auth (GoTrue)

    /// Raw auth POST → decoded JSON object (e.g. token bundle). `path` is under
    /// `/auth/v1/` (`otp`, `verify`, `token?grant_type=refresh_token`). Auth
    /// endpoints authenticate with the anon key only — no bearer.
    public func authPost(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        let data = try await send(method: "POST", url: authURL(path), token: nil,
                                  body: body, prefer: nil)
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SharingError.decoding("auth response not a JSON object")
        }
        return obj
    }

    // MARK: - Core request

    private func restURL(_ path: String) -> URL { URL(string: "\(baseURL)/rest/v1/\(path)")! }
    private func authURL(_ path: String) -> URL { URL(string: "\(baseURL)/auth/v1/\(path)")! }

    private func send(method: String, url: URL, token: String?, body: Any?,
                      prefer: String?) async throws -> Data {
        guard isConfigured else { throw SharingError.notConfigured }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token ?? anonKey)", forHTTPHeaderField: "Authorization")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw SharingError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw SharingError.network("non-HTTP response")
        }
        switch http.statusCode {
        case 200...299:
            return data
        case 401, 403:
            throw SharingError.forbidden
        case 409:
            throw SharingError.conflict(Self.serverMessage(data))
        default:
            throw SharingError.http(http.statusCode, Self.serverMessage(data))
        }
    }

    /// Pull a human-readable message out of a PostgREST/GoTrue error body.
    private static func serverMessage(_ data: Data) -> String {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return String(decoding: data, as: UTF8.self) }
        return (obj["message"] as? String)
            ?? (obj["msg"] as? String)
            ?? (obj["error_description"] as? String)
            ?? (obj["error"] as? String)
            ?? String(decoding: data, as: UTF8.self)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try SharingJSON.decoder.decode(type, from: data)
        } catch {
            throw SharingError.decoding(error.localizedDescription)
        }
    }
}
