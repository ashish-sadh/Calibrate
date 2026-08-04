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
    /// The caller already has as many connections as Drift supports. A stated
    /// ceiling with a clear message, chosen over letting the social surfaces
    /// degrade quietly past the point they were designed for.
    case tooManyConnections(limit: Int)
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
                session: any HTTPDataSession = DriftPlatform.httpSession,
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
        let data = try await send(method: "GET", url: try restURL(path), token: token, body: nil,
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
        let data = try await send(method: "POST", url: try restURL(table), token: token,
                                  body: body, prefer: prefer)
        return try decode([T].self, from: data)
    }

    /// POST rows and DISCARD the response. Used by telemetry, whose tables grant
    /// the client INSERT and nothing else — asking PostgREST for
    /// `return=representation` there would be a read and come back 403.
    /// Takes pre-encoded JSON so a batch doesn't get re-serialized.
    public func restInsertRaw(path: String, body: Data, token: String? = nil) async throws {
        guard isConfigured else { throw SharingError.notConfigured }
        var req = URLRequest(url: try restURL(path), timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token ?? anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = body

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw SharingError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw SharingError.network("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SharingError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
    }

    /// Upload bytes to a Supabase Storage bucket. Used for support-report
    /// screenshots, which are usually what makes a bug reproducible. The bucket
    /// is private — clients upload, only the service role reads back — so this
    /// returns nothing but the path the caller already knows.
    public func storageUpload(bucket: String, path: String, data: Data,
                              contentType: String, token: String? = nil) async throws {
        guard isConfigured else { throw SharingError.notConfigured }
        guard let url = URL(string: "\(baseURL)/storage/v1/object/\(bucket)/\(path)") else {
            throw SharingError.network("could not form storage URL")
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token ?? anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = data

        let respData: Data, response: URLResponse
        do {
            (respData, response) = try await session.data(for: req)
        } catch {
            throw SharingError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw SharingError.network("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SharingError.http(http.statusCode, String(decoding: respData, as: UTF8.self))
        }
    }

    /// PATCH rows matched by `query` (`friendships?id=eq.<uuid>`), returning the
    /// updated representation.
    @discardableResult
    public func restUpdate<T: Decodable>(_ query: String, body: Any, token: String?) async throws -> [T] {
        let data = try await send(method: "PATCH", url: try restURL(query), token: token,
                                  body: body, prefer: "return=representation")
        return try decode([T].self, from: data)
    }

    /// GET rows as untyped dictionaries. For tables whose columns are `jsonb`
    /// of a shape Codable can't express cleanly (the client briefing's `notes`
    /// and `metrics`) — decoding those through a struct would mean a second
    /// nested-JSON hop for no benefit.
    public func restGetRaw(_ path: String, token: String?) async throws -> [[String: Any]] {
        let data = try await send(method: "GET", url: try restURL(path), token: token,
                                  body: nil, prefer: nil)
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
    }

    /// POST rows, discarding the response. Same shape as `restInsert` but for
    /// callers that don't need the row back — asking for a representation costs
    /// a read the caller then throws away.
    public func restUpsertDiscard(_ table: String, body: Any, token: String?) async throws {
        _ = try await send(method: "POST", url: try restURL(table), token: token,
                           body: body, prefer: "return=minimal,resolution=merge-duplicates")
    }

    /// DELETE rows matched by `query` (`profiles?id=eq.<uuid>`). No body/return.
    public func restDelete(_ query: String, token: String?) async throws {
        _ = try await send(method: "DELETE", url: try restURL(query), token: token,
                           body: nil, prefer: nil)
    }

    // MARK: - Auth (GoTrue)

    /// Raw auth POST → decoded JSON object (e.g. token bundle). `path` is under
    /// `/auth/v1/` (`otp`, `verify`, `token?grant_type=refresh_token`). Auth
    /// endpoints authenticate with the anon key only — no bearer.
    public func authPost(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        let data = try await send(method: "POST", url: try authURL(path), token: nil,
                                  body: body, prefer: nil)
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SharingError.decoding("auth response not a JSON object")
        }
        return obj
    }

    // MARK: - Core request

    private func restURL(_ path: String) throws -> URL { try makeURL("rest/v1/\(path)") }
    private func authURL(_ path: String) throws -> URL { try makeURL("auth/v1/\(path)") }

    /// Build a URL, percent-encoding the query if the raw string won't parse
    /// (PostgREST queries carry `(` `)` `*` `,` which some URL parsers reject).
    /// Never force-unwraps — a bad URL surfaces as a `.network` error, not a crash.
    private func makeURL(_ suffix: String) throws -> URL {
        let raw = "\(baseURL)/\(suffix)"
        if let u = URL(string: raw) { return u }
        if let q = suffix.firstIndex(of: "?") {
            let base = String(suffix[..<q])
            let query = String(suffix[suffix.index(after: q)...])
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            if let u = URL(string: "\(baseURL)/\(base)?\(encoded)") { return u }
        }
        throw SharingError.network("could not form request URL")
    }

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
