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

        // Remove format echoes from small models
        if text.lowercased().hasPrefix("a: ") { text = String(text.dropFirst(3)) }
        if text.lowercased().hasPrefix("assistant: ") { text = String(text.dropFirst(11)) }

        // Strip markdown formatting (looks awkward in plain text chat)
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "## ", with: "")
        text = text.replacingOccurrences(of: "# ", with: "")
        // Replace markdown bullets only at line start (avoid mid-sentence "-300kcal")
        let bulletPattern = #"(?m)^[*\-]\s"#
        if let bulletRegex = try? NSRegularExpression(pattern: bulletPattern) {
            text = bulletRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "\u{2022} ")
        }

        // Clean up numbered lists at line start: "1. " → "1) " (more conversational)
        let numberedPattern = #"(?m)^(\d+)\.\s"#
        if let regex = try? NSRegularExpression(pattern: numberedPattern) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1) ")
        }

        // Remove mechanical preambles and question echoes
        let preambles = ["based on your data, ", "based on the context, ", "according to the data, ",
                         "according to your information, ", "based on the information provided, ",
                         "looking at your data, ", "from what i can see, ",
                         "great question! ", "good question! ", "that's a great question! ",
                         "sure! ", "of course! ", "absolutely! "]
        for p in preambles {
            if text.lowercased().hasPrefix(p) {
                text = String(text.dropFirst(p.count))
                // Capitalize first letter
                if let first = text.first {
                    text = first.uppercased() + text.dropFirst()
                }
            }
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

    /// Check if a response is too generic/unhelpful and should be replaced.
    static func isLowQuality(_ response: String) -> Bool {
        let lower = response.lowercased()
        let trimmed = lower.trimmingCharacters(in: .whitespacesAndNewlines)

        // Too short — but allow short factual answers like "4" or "Yes!"
        if trimmed.count < 5 { return true }

        // Generic fillers
        let genericPhrases = [
            "i'm here to help",
            "how can i assist you",
            "what would you like to know",
            "feel free to ask",
            "let me know if you",
            "i'd be happy to help",
        ]
        if genericPhrases.contains(where: { trimmed.contains($0) }) && trimmed.count < 80 { return true }

        // Pure repetition
        let words = trimmed.components(separatedBy: .whitespaces).filter { $0.count > 2 }
        if words.count > 5 {
            let unique = Set(words).count
            if Double(unique) / Double(words.count) < 0.3 { return true }
        }

        // Garbage detection: mostly non-alpha characters
        let alphaCount = trimmed.filter(\.isLetter).count
        if trimmed.count > 20 && Double(alphaCount) / Double(trimmed.count) < 0.5 { return true }

        // Context regurgitation: response is just the raw data format
        if trimmed.contains("|") && trimmed.filter({ $0 == "|" }).count > 3 { return true }
        if trimmed.hasPrefix("eaten:") || trimmed.hasPrefix("weight:") || trimmed.hasPrefix("goal:") { return true }
        if trimmed.hasPrefix("screen:") || trimmed.hasPrefix("actions:") || trimmed.hasPrefix("context:") { return true }

        // Model echoing the system prompt or instructions
        if trimmed.contains("action tag") || trimmed.contains("[log_food") || trimmed.contains("[create_workout") { return true }
        if trimmed.contains("\"tool\"") && trimmed.contains("\"params\"") && !trimmed.contains("{") { return true } // Mangled JSON

        // Model refusing to answer or being overly cautious
        if trimmed.hasPrefix("i cannot") || trimmed.hasPrefix("i can't answer") || trimmed.hasPrefix("i don't have") { return true }

        // Model just repeating the question
        if trimmed.count < 100 && trimmed.contains("?") && !trimmed.contains(where: \.isNumber) { return true }

        return false
    }

    /// Check if response contains hallucinated numbers (not from context).
    /// Returns true if suspicious numbers found.
    static func hasHallucinatedNumbers(_ response: String, context: String) -> Bool {
        // Extract all numbers from response
        let responseNums = extractNumbers(response)
        guard !responseNums.isEmpty else { return false }  // No numbers = can't hallucinate

        // Extract numbers from context (these are "allowed")
        let contextNums = Set(extractNumbers(context))
        guard !contextNums.isEmpty else { return false }  // No context numbers = can't verify

        // Check: are response numbers a subset of context numbers?
        let hallucinated = responseNums.filter { !contextNums.contains($0) }

        // Allow small numbers (1-10) and common numbers (100, 1000) — these are often phrasing
        let suspicious = hallucinated.filter { $0 > 10 && $0 != 100 && $0 != 1000 }
        return suspicious.count > 2  // More than 2 unknown numbers = likely hallucination
    }

    private static func extractNumbers(_ text: String) -> [Int] {
        let pattern = #"\b(\d{2,5})\b"#  // 2-5 digit numbers (skip single digits)
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) }
        }
    }
}
