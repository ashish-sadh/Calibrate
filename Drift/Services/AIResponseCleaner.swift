import Foundation

/// Cleans LLM output before displaying to the user.
/// Removes artifacts, deduplicates sentences, strips disclaimers, and truncates.
enum AIResponseCleaner {

    static func clean(_ response: String) -> String {
        var text = response

        // Remove ChatML artifacts
        for artifact in ["<|im_start|>", "<|im_end|>", "<|endoftext|>", "<|assistant|>", "<|user|>", "<|system|>"] {
            text = text.replacingOccurrences(of: artifact, with: "")
        }

        // Remove "As an AI..." disclaimers
        let disclaimers = ["as an ai", "as a language model", "i'm just an ai", "i cannot provide medical", "i'm not a doctor"]
        let sentences = text.components(separatedBy: ". ")
        let filtered = sentences.filter { s in
            !disclaimers.contains(where: { s.lowercased().contains($0) })
        }
        text = filtered.joined(separator: ". ")

        // Remove duplicate sentences
        let parts = text.components(separatedBy: ". ")
        var seen = Set<String>()
        var deduped: [String] = []
        for part in parts {
            let normalized = part.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                deduped.append(part)
            }
        }
        text = deduped.joined(separator: ". ")

        // Truncate to reasonable length
        if text.count > 500 {
            let truncated = String(text.prefix(497))
            if let lastPeriod = truncated.lastIndex(of: ".") {
                text = String(truncated[...lastPeriod])
            } else {
                text = truncated + "..."
            }
        }

        // Remove trailing incomplete sentence (ends without period)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !trimmed.hasSuffix(".") && !trimmed.hasSuffix("!") && !trimmed.hasSuffix("?") {
            if let lastPeriod = trimmed.lastIndex(of: ".") {
                return String(trimmed[...lastPeriod])
            }
        }

        return trimmed
    }
}
