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

// MARK: - web_search (Google Custom Search parser)

@Test func googleParserFormatsItems() {
    let json = #"""
    {"items":[
      {"title":"Chipotle Nutrition Calculator","snippet":"Chicken Bowl: 625-905 calories depending on toppings.","link":"https://www.chipotle.com/nutrition-calculator"},
      {"title":"Chipotle Chicken Bowl Calories","snippet":"A typical chicken burrito bowl has about 800 calories,\n52g protein.","link":"https://example.com/cal"}
    ]}
    """#.data(using: .utf8)!
    let out = WebSearchTool.parseGoogle(json, query: "chipotle chicken bowl calories")
    #expect(out.contains("625-905 calories"))
    #expect(out.contains("chipotle.com/nutrition-calculator"))
    #expect(out.contains("800 calories, 52g protein"))   // newline flattened
}

@Test func googleParserHandlesEmptyAndGarbage() {
    #expect(WebSearchTool.parseGoogle("{}".data(using: .utf8)!, query: "q").contains("No web results"))
    #expect(WebSearchTool.parseGoogle(Data("nope".utf8), query: "q").contains("No web results"))
}

@Test func googleParserTruncates() {
    let big = String(repeating: "b", count: 5000)
    let json = Data(#"{"items":[{"title":"T","snippet":"\#(big)","link":"https://x.com"}]}"#.utf8)
    let out = WebSearchTool.parseGoogle(json, query: "q", maxChars: 120)
    #expect(out.count <= 121)
}

// MARK: - web_search (Brave parser)

@Test func braveParserFormatsResultsAndStripsMarkup() {
    let json = #"""
    {"web":{"results":[
      {"title":"Chipotle Chicken Bowl","description":"About <strong>800 calories</strong> with rice and beans.","url":"https://example.com/bowl"},
      {"title":"Menu Nutrition","description":"Full macros listed.","url":"https://chipotle.com"}
    ]}}
    """#.data(using: .utf8)!
    let out = WebSearchTool.parseBrave(json, query: "chipotle bowl calories")
    #expect(out.contains("About 800 calories"))      // <strong> stripped
    #expect(!out.contains("<strong>"))
    #expect(out.contains("example.com/bowl"))
}

@Test func braveParserHandlesEmptyAndGarbage() {
    #expect(WebSearchTool.parseBrave("{}".data(using: .utf8)!, query: "q").contains("No web results"))
    #expect(WebSearchTool.parseBrave(Data("nope".utf8), query: "q").contains("No web results"))
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
