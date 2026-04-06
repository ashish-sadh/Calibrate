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
        text = text.replacingOccurrences(of: "* ", with: "\u{2022} ") // bullet points → proper bullet
        text = text.replacingOccurrences(of: "- ", with: "\u{2022} ") // dash lists → proper bullet

        // Clean up numbered lists: "1. " → "1) " (more conversational)
        let numberedPattern = #"(\d+)\.\s"#
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

        return false
    }
}
