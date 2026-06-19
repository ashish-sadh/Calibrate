import Foundation
@testable import DriftCore
import Testing

// MARK: - web_search (DuckDuckGo Instant Answer parser)

@Test func webSearchParsesAbstractAndRelated() {
    let json = #"""
    {"AbstractText":"Paneer is a fresh cheese common in Indian cuisine.","AbstractURL":"https://en.wikipedia.org/wiki/Paneer","RelatedTopics":[{"Text":"High in protein","FirstURL":"https://example.com/protein"},{"Text":"Used in palak paneer"}]}
    """#.data(using: .utf8)!
    let out = WebSearchTool.parse(json, query: "paneer")
    #expect(out.contains("fresh cheese"))
    #expect(out.contains("High in protein"))
    #expect(out.contains("wikipedia.org/wiki/Paneer"))
}

@Test func webSearchHandlesEmptyResults() {
    let out = WebSearchTool.parse("{}".data(using: .utf8)!, query: "xyzzy")
    #expect(out.contains("No direct web answer"))
}

@Test func webSearchHandlesGarbage() {
    let out = WebSearchTool.parse(Data("not json".utf8), query: "q")
    #expect(out.contains("No web results"))
}

@Test func webSearchTruncatesLongOutput() {
    let big = String(repeating: "a", count: 5000)
    let json = Data(#"{"AbstractText":"\#(big)"}"#.utf8)
    let out = WebSearchTool.parse(json, query: "q", maxChars: 100)
    #expect(out.count <= 101)   // 100 + ellipsis
}

// MARK: - fetch_url (HTML → readable text)

@Test func fetchURLExtractsReadableText() {
    let html = "<html><head><title>T</title><style>.x{}</style></head><body><h1>Protein</h1><p>Eat more &amp; train.</p><script>bad()</script></body></html>"
    let out = FetchURLTool.extractText(from: html)
    #expect(out.contains("Protein"))
    #expect(out.contains("Eat more & train"))
    #expect(!out.contains("bad()"))   // script stripped
    #expect(!out.contains("<"))        // tags stripped
}

@Test func fetchURLTruncatesLongPages() {
    let html = "<p>" + String(repeating: "x", count: 5000) + "</p>"
    let out = FetchURLTool.extractText(from: html, maxChars: 50)
    #expect(out.count <= 51)
}
