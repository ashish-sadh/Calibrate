import Foundation

/// A durable fact the coach remembers about the user across sessions — a goal,
/// a preference, a correction, or a learned fact. NOT raw conversation turns
/// (those live in `CrossSessionHistory`); this is the distilled "what matters
/// about you" layer. Stays on-device (#coach-agent-loop, local-first; HydraDB
/// was intentionally skipped — a remote DB isn't justified for a single-user,
/// privacy-first coach).
public struct MemoryItem: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case goal          // "wants to hit 90g protein daily"
        case preference    // "vegetarian", "no gym", "prefers Indian food"
        case correction    // "rice portions are usually ~150g, not 200g"
        case fact          // any other durable fact worth recalling
    }

    public let id: String
    public let text: String
    public let kind: Kind
    public let createdAt: Date
    /// Cached sentence embedding for semantic recall (nil when the embedder is
    /// unavailable — recall then falls back to lexical overlap).
    var embedding: [Double]?

    public init(id: String = UUID().uuidString, text: String, kind: Kind, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.kind = kind
        self.createdAt = createdAt
        self.embedding = nil
    }
}

/// The coach's cross-session memory seam — `recall` before a turn (inject what's
/// relevant), `remember` after (write durable facts). Protocol-shaped (the
/// swift-claude-code `APIClientProtocol` pattern) so a different backend — e.g.
/// a cloud memory service — can drop in later without touching the agent. The
/// shipped default is `LocalCoachMemory` (fully on-device).
public protocol CoachMemory: Sendable {
    /// Persist a durable fact. Idempotent on identical `text` (de-dupes).
    func remember(_ item: MemoryItem) async
    /// Return up to `limit` memories most relevant to `query`, most-relevant first.
    func recall(query: String, limit: Int) async -> [MemoryItem]
    /// Everything stored (most-recent first) — for the "what I know about you" surface.
    func all() async -> [MemoryItem]
}
