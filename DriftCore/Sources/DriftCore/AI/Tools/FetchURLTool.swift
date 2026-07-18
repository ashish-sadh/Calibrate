import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetch a web page by URL and return its readable text — for when the coach
/// needs to read a specific page (e.g. one surfaced by `web_search`). Read-only,
/// explicit cloud touch-point. The pure HTML→text `extractText` is Tier-0
/// tested; the live fetch is the only impure part. #coach-agent-loop.
@MainActor
public enum FetchURLTool {

    nonisolated static let toolName = "fetch_url"

    static func syncRegistration(registry: ToolRegistry = .shared) {
        registry.register(schema)
    }

    static var schema: ToolSchema {
        ToolSchema(
            id: "web.fetch_url",
            name: toolName,
            service: "web",
            description: "Fetch a web page by its URL and return the readable text. Use to read a page found via web_search.",
            parameters: [ToolParam("url", "string", "The full http(s) URL to fetch")],
            handler: { params in
                let raw = (params.string("url") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: raw), url.scheme?.hasPrefix("http") == true else {
                    return .error("fetch_url needs a valid http(s) URL.")
                }
                do {
                    let data = try await URLSession.shared.data(from: url).0
                    return .text(extractText(from: String(data: data, encoding: .utf8) ?? ""))
                } catch {
                    return .error("Couldn't fetch that page.")
                }
            }
        )
    }

    /// Pure: strip HTML to readable text, decode common entities, collapse
    /// whitespace, and cap length so a big page can't blow the context window.
    nonisolated static func extractText(from html: String, maxChars: Int = 3000) -> String {
        var s = html
        for tag in ["script", "style", "head", "noscript"] {
            s = s.replacingOccurrences(of: "(?s)<\(tag).*?</\(tag)>", with: " ", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "]
        for (entity, char) in entities { s = s.replacingOccurrences(of: entity, with: char) }
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.count > maxChars ? String(s.prefix(maxChars)) + "…" : s
    }
}
