import Foundation
import NaturalLanguage

/// On-device `CoachMemory` — durable user facts/goals with **local** semantic
/// recall via Apple's `NLEmbedding` (no cloud, no key, no network). Falls back
/// to lexical token overlap when the embedding model isn't available, so recall
/// always works. Persisted as JSON on disk; an `actor` so store access is
/// serialized off the main thread.
///
/// This is the local answer to "remember the user across sessions" — chosen over
/// a remote memory DB because nothing here needs to leave the device.
public actor LocalCoachMemory: CoachMemory {

    private let storeURL: URL
    private let maxItems: Int
    /// Minimum cosine similarity for a semantic hit — below this, a memory is
    /// considered irrelevant to the query (avoids injecting noise).
    private let relevanceFloor: Double
    private var items: [MemoryItem]
    private let embedder = NLEmbedding.sentenceEmbedding(for: .english)

    public init(storeURL: URL? = nil, maxItems: Int = 500, relevanceFloor: Double = 0.30) {
        self.storeURL = storeURL ?? Self.defaultStoreURL()
        self.maxItems = maxItems
        self.relevanceFloor = relevanceFloor
        self.items = Self.load(from: self.storeURL)
    }

    // MARK: - CoachMemory

    public func remember(_ item: MemoryItem) async {
        var stored = item
        stored.embedding = embed(item.text)
        // De-dupe on identical text — re-stating a fact refreshes it, not duplicates.
        items.removeAll { $0.text.caseInsensitiveCompare(item.text) == .orderedSame }
        items.append(stored)
        if items.count > maxItems { items.removeFirst(items.count - maxItems) }
        persist()
    }

    public func recall(query: String, limit: Int) async -> [MemoryItem] {
        guard !items.isEmpty, limit > 0 else { return [] }
        if let qv = embed(query) {
            let scored = items.compactMap { item -> (MemoryItem, Double)? in
                guard let v = item.embedding else { return nil }
                return (item, Self.cosine(qv, v))
            }
            let semantic = scored.filter { $0.1 >= relevanceFloor }
                .sorted { $0.1 > $1.1 }
                .prefix(limit)
                .map { $0.0 }
            if !semantic.isEmpty { return Array(semantic) }
            // Embeddings present but nothing cleared the floor → fall through to lexical.
        }
        return lexicalRecall(query: query, limit: limit)
    }

    public func all() async -> [MemoryItem] {
        items.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Lexical fallback (no embeddings)

    private func lexicalRecall(query: String, limit: Int) -> [MemoryItem] {
        let q = Self.tokens(query)
        guard !q.isEmpty else { return [] }
        return items
            .map { ($0, Self.overlap(q, Self.tokens($0.text))) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    // MARK: - Embedding

    private func embed(_ text: String) -> [Double]? {
        embedder?.vector(for: text.lowercased())
    }

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom == 0 ? 0 : dot / denom
    }

    static func tokens(_ s: String) -> Set<String> {
        Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 })
    }

    static func overlap(_ a: Set<String>, _ b: Set<String>) -> Int {
        a.intersection(b).count
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private static func load(from url: URL) -> [MemoryItem] {
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([MemoryItem].self, from: data) else { return [] }
        return items
    }

    private static func defaultStoreURL() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("drift_coach_memory.json")
    }
}
