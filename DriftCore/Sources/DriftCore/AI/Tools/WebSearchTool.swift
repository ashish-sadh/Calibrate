import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Web search for the coach — **Brave Search API** when a key is configured
/// (real result snippets: restaurant nutrition, menu items, current facts),
/// falling back to DuckDuckGo's Instant Answer API keyless. Lets the coach
/// reach outside knowledge (a Chipotle bowl's published calories, recipes,
/// research) it doesn't have on-device. Read-only and an explicit cloud
/// touch-point (the coach surfaces "Searching the web…"; the settings row
/// documents what's sent). The pure parsers are Tier-0 tested on canned JSON;
/// the live fetches are the only impure parts. #coach-agent-loop.
@MainActor
public enum WebSearchTool {

    nonisolated static let toolName = "web_search"

    static func syncRegistration(registry: ToolRegistry = .shared) {
        registry.register(schema)
    }

    static var schema: ToolSchema {
        ToolSchema(
            id: "web.web_search",
            name: toolName,
            service: "web",
            description: "Search the web for current or external knowledge NOT in the app — restaurant/chain menu nutrition (a Chipotle bowl, a Big Mac), nutrition facts for an unknown food, recipes, research, product info. Use only when the answer needs outside information.",
            parameters: [ToolParam("query", "string", "What to search the web for")],
            handler: { params in
                let q = (params.string("query") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !q.isEmpty else { return .error("web_search needs a query.") }
                do {
                    return .text(try await search(query: q))
                } catch {
                    return .error("Web search failed — check your connection.")
                }
            }
        )
    }

    /// Provider ladder: Google Custom Search (key + engine id) → Brave (key) →
    /// DuckDuckGo (keyless). One entry point so every caller (agent chain,
    /// food_info fallback) gets the same ladder; a failed keyed provider
    /// degrades down a rung instead of failing the turn.
    public static func search(query: String) async throws -> String {
        let googleKey = Preferences.googleSearchApiKey
        let googleCx = Preferences.googleSearchEngineId
        if !googleKey.isEmpty, !googleCx.isEmpty {
            do {
                return parseGoogle(try await fetchGoogle(query: query, key: googleKey, engineId: googleCx), query: query)
            } catch {
                Log.app.error("WebSearchTool: Google CSE failed (\(error)), falling down the ladder")
            }
        }
        let braveKey = Preferences.braveSearchApiKey
        if !braveKey.isEmpty {
            do {
                return parseBrave(try await fetchBrave(query: query, key: braveKey), query: query)
            } catch {
                Log.app.error("WebSearchTool: Brave failed (\(error)), falling back to DDG")
            }
        }
        return parse(try await fetch(query: query), query: query)
    }

    // MARK: - Google Custom Search JSON API

    /// Impure: hit Google's Programmable Search Engine endpoint. `engineId` is
    /// the `cx` of an engine configured to "search the entire web".
    nonisolated static func fetchGoogle(query: String, key: String, engineId: String) async throws -> Data {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://www.googleapis.com/customsearch/v1?key=\(key)&cx=\(engineId)&num=6&q=\(encoded)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        let (data, response) = try await DriftPlatform.httpSession.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// Pure: format Google CSE JSON (`items[].title/snippet/link`) into compact
    /// "title — snippet (url)" lines. Same output shape as `parseBrave` so the
    /// agent loop and the food_info fallback are provider-agnostic.
    nonisolated static func parseGoogle(_ data: Data, query: String, maxChars: Int = 2000) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]], !items.isEmpty else {
            return "No web results for \"\(query)\"."
        }
        var lines: [String] = []
        for item in items.prefix(6) {
            let title = (item["title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let snippet = (item["snippet"] as? String ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            let link = item["link"] as? String ?? ""
            guard !title.isEmpty || !snippet.isEmpty else { continue }
            lines.append("• \(title)\(snippet.isEmpty ? "" : " — \(snippet)")\(link.isEmpty ? "" : " (\(link))")")
        }
        guard !lines.isEmpty else { return "No web results for \"\(query)\"." }
        let joined = lines.joined(separator: "\n")
        return joined.count > maxChars ? String(joined.prefix(maxChars)) + "…" : joined
    }

    // MARK: - Brave Search API

    /// Impure: hit the Brave web-search endpoint with the configured key.
    nonisolated static func fetchBrave(query: String, key: String) async throws -> Data {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://api.search.brave.com/res/v1/web/search?q=\(encoded)&count=6") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(key, forHTTPHeaderField: "X-Subscription-Token")
        req.timeoutInterval = 10
        let (data, response) = try await DriftPlatform.httpSession.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// Pure: format Brave's JSON into compact "title — snippet (url)" lines the
    /// agent loop can reason over. Snippets from real pages carry the calorie
    /// numbers DDG's Instant Answers never had. Capped for context safety.
    nonisolated static func parseBrave(_ data: Data, query: String, maxChars: Int = 2000) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let web = json["web"] as? [String: Any],
              let results = web["results"] as? [[String: Any]], !results.isEmpty else {
            return "No web results for \"\(query)\"."
        }
        var lines: [String] = []
        for r in results.prefix(6) {
            let title = (r["title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let desc = (r["description"] as? String ?? "")
                .replacingOccurrences(of: "<strong>", with: "")
                .replacingOccurrences(of: "</strong>", with: "")
                .trimmingCharacters(in: .whitespaces)
            let url = r["url"] as? String ?? ""
            guard !title.isEmpty || !desc.isEmpty else { continue }
            lines.append("• \(title)\(desc.isEmpty ? "" : " — \(desc)")\(url.isEmpty ? "" : " (\(url))")")
        }
        guard !lines.isEmpty else { return "No web results for \"\(query)\"." }
        let joined = lines.joined(separator: "\n")
        return joined.count > maxChars ? String(joined.prefix(maxChars)) + "…" : joined
    }

    // MARK: - DuckDuckGo fallback (keyless)

    /// Impure: hit the DuckDuckGo Instant Answer endpoint (no key).
    nonisolated static func fetch(query: String) async throws -> Data {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1") else {
            throw URLError(.badURL)
        }
        return try await DriftPlatform.httpSession.data(for: URLRequest(url: url)).0
    }

    /// Pure: format the Instant Answer JSON into a compact summary the agent
    /// loop can reason over. Capped so a big response can't blow the context.
    nonisolated static func parse(_ data: Data, query: String, maxChars: Int = 1500) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "No web results for \"\(query)\"."
        }
        var lines: [String] = []
        if let abstract = json["AbstractText"] as? String, !abstract.isEmpty {
            lines.append(abstract)
            if let src = json["AbstractURL"] as? String, !src.isEmpty { lines.append("Source: \(src)") }
        }
        if let answer = json["Answer"] as? String, !answer.isEmpty { lines.append(answer) }
        if let related = json["RelatedTopics"] as? [[String: Any]] {
            for topic in related.prefix(5) {
                if let text = topic["Text"] as? String, !text.isEmpty {
                    let url = (topic["FirstURL"] as? String).map { " (\($0))" } ?? ""
                    lines.append("• \(text)\(url)")
                }
            }
        }
        guard !lines.isEmpty else { return "No direct web answer for \"\(query)\". Try rephrasing." }
        let joined = lines.joined(separator: "\n")
        return joined.count > maxChars ? String(joined.prefix(maxChars)) + "…" : joined
    }
}
