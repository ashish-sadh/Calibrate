import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Web search via **DuckDuckGo's Instant Answer API** — no API key, no account,
/// privacy-aligned. Lets the coach reach outside knowledge (nutrition facts,
/// recipes, research) it doesn't have on-device. Read-only and an explicit
/// cloud touch-point (the coach surfaces "Searching the web…"). The pure
/// `parse` is Tier-0 tested on canned JSON; the live fetch is the only impure
/// part. #coach-agent-loop.
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
            description: "Search the web for current or external knowledge NOT in the app — nutrition facts for an unknown food, recipes, research, product info. Use only when the answer needs outside information.",
            parameters: [ToolParam("query", "string", "What to search the web for")],
            handler: { params in
                let q = (params.string("query") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !q.isEmpty else { return .error("web_search needs a query.") }
                do {
                    return .text(parse(try await fetch(query: q), query: q))
                } catch {
                    return .error("Web search failed — check your connection.")
                }
            }
        )
    }

    /// Impure: hit the DuckDuckGo Instant Answer endpoint (no key).
    nonisolated static func fetch(query: String) async throws -> Data {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1") else {
            throw URLError(.badURL)
        }
        return try await URLSession.shared.data(from: url).0
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
