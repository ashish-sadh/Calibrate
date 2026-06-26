import Foundation

/// Curated catalog of common supplements — global staples plus an Indian-first
/// set — used to recognize a supplement the user names in chat even when it is
/// NOT yet in their stack, so "I took my vitamin D" can auto-add + mark instead
/// of dead-ending with "No supplements found." (#904)
///
/// Recognition is whole-word/phrase matching over a normalization identical to
/// `SupplementService.normalizedForMatch` (lowercase, every non-alphanumeric
/// character → space, whitespace runs collapsed), so "Omega-3" and "omega 3"
/// resolve to the same entry. Aliases are curated and ≥2 characters so ordinary
/// sentences ("I walked the dog") don't false-positive into a supplement.
enum KnownSupplements {

    /// One supplement: the canonical display name we store/show, and every alias
    /// (each already in normalized form) the user might say for it.
    private struct Entry {
        let canonical: String
        let aliases: [String]
    }

    /// Recognize every distinct supplement named anywhere in `phrase`. Returns
    /// canonical display names, de-duplicated by canonical (so "vitamin d and d3"
    /// → ["Vitamin D"] once, since both are aliases of one entry) and ordered by
    /// first appearance in the phrase (so "giloy and tulsi" → ["Giloy", "Tulsi"]).
    static func recognize(in phrase: String) -> [String] {
        let normalized = normalizedForMatch(phrase)
        guard !normalized.isEmpty else { return [] }
        let padded = " \(normalized) "

        // For each entry with at least one alias present, the earliest index any
        // of its aliases starts — used to order results the way the user said them.
        var hits: [(canonical: String, at: String.Index)] = []
        for entry in catalog {
            var earliest: String.Index?
            for alias in entry.aliases {
                guard let range = padded.range(of: " \(alias) ") else { continue }
                if earliest == nil || range.lowerBound < earliest! { earliest = range.lowerBound }
            }
            if let at = earliest { hits.append((entry.canonical, at)) }
        }
        return hits.sorted { $0.at < $1.at }.map(\.canonical)
    }

    /// Lowercase, map every non-alphanumeric character to a space, collapse runs
    /// of whitespace — identical to `SupplementService.normalizedForMatch` so the
    /// catalog and the in-stack matcher agree on word boundaries.
    private static func normalizedForMatch(_ s: String) -> String {
        let spaced = s.lowercased().map { ($0.isLetter || $0.isNumber) ? $0 : " " }
        return String(spaced).split(separator: " ").joined(separator: " ")
    }

    /// Canonical + aliases. Aliases are pre-normalized (lowercase, single-spaced)
    /// so they compare directly against `normalizedForMatch(phrase)`.
    private static let catalog: [Entry] = [
        // — Global staples —
        Entry(canonical: "Vitamin D", aliases: ["vitamin d", "vit d", "d3", "vitamin d3", "cholecalciferol"]),
        Entry(canonical: "Omega 3", aliases: ["omega 3", "omega3", "fish oil"]),
        Entry(canonical: "Creatine", aliases: ["creatine", "creatine monohydrate"]),
        Entry(canonical: "Whey Protein", aliases: ["whey", "whey protein", "whey isolate"]),
        Entry(canonical: "Multivitamin", aliases: ["multivitamin", "multi vitamin", "multivit"]),
        Entry(canonical: "Magnesium", aliases: ["magnesium", "magnesium glycinate", "magnesium citrate", "mag glycinate"]),
        Entry(canonical: "Vitamin B12", aliases: ["b12", "vitamin b12", "vit b12", "methylcobalamin", "cobalamin"]),
        Entry(canonical: "Vitamin C", aliases: ["vitamin c", "vit c", "ascorbic acid"]),
        Entry(canonical: "Vitamin B Complex", aliases: ["b complex", "vitamin b complex"]),
        Entry(canonical: "Zinc", aliases: ["zinc"]),
        Entry(canonical: "Iron", aliases: ["iron", "ferrous"]),
        Entry(canonical: "Calcium", aliases: ["calcium"]),
        Entry(canonical: "Biotin", aliases: ["biotin"]),
        Entry(canonical: "Collagen", aliases: ["collagen"]),
        Entry(canonical: "Probiotic", aliases: ["probiotic", "probiotics"]),
        Entry(canonical: "Melatonin", aliases: ["melatonin"]),
        Entry(canonical: "Folic Acid", aliases: ["folic acid", "folate"]),
        Entry(canonical: "Glutamine", aliases: ["glutamine", "l glutamine"]),
        Entry(canonical: "BCAA", aliases: ["bcaa", "bcaas"]),
        // — Indian-first set (the bar — Indian wellness/Ayurveda staples) —
        Entry(canonical: "Ashwagandha", aliases: ["ashwagandha", "ashwaganda"]),
        Entry(canonical: "Turmeric", aliases: ["turmeric", "curcumin", "haldi"]),
        Entry(canonical: "Triphala", aliases: ["triphala"]),
        Entry(canonical: "Shilajit", aliases: ["shilajit"]),
        Entry(canonical: "Tulsi", aliases: ["tulsi", "holy basil"]),
        Entry(canonical: "Giloy", aliases: ["giloy", "guduchi"]),
        Entry(canonical: "Amla", aliases: ["amla", "indian gooseberry"]),
        Entry(canonical: "Moringa", aliases: ["moringa", "drumstick leaf"]),
        Entry(canonical: "Spirulina", aliases: ["spirulina"]),
        Entry(canonical: "Isabgol", aliases: ["isabgol", "psyllium", "psyllium husk"]),
    ]
}
