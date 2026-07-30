import Foundation

/// Gym vernacular → catalog name.
///
/// The catalog is anatomically named ("Hip Abduction Machine"); people say what
/// the machine looks like ("outer thigh machine"). Token matching cannot bridge
/// that — the two names share no words — so the mapping has to be written down.
///
/// This is deliberately a SMALL curated list, not a general thesaurus. Every
/// entry is a phrase a real person used that resolved to nothing (source:
/// operator's colleague's session, 2026-07-29, where 9 of 10 logged exercises
/// found no match). Guessing at synonyms is how a logger silently records the
/// wrong movement, which is worse than finding none.
enum ExerciseAliases {

    /// Lowercased spoken phrase → exact catalog name.
    static let map: [String: String] = [
        // Machines people name by the body part they feel, not the joint action.
        "outer thigh machine": "Hip Abduction Machine",
        "inner thigh machine": "Thigh Adductor",
        "abductor machine": "Hip Abduction Machine",
        "adductor machine": "Thigh Adductor",
        "hip abductor machine": "Hip Abduction Machine",

        // "Barbell hang" is a bar hang done on a loaded bar in a rack — the
        // catalog's own name for it drops the implement.
        "barbell hang": "Bar Hang",
        "dead hang": "Bar Hang",
        "bar hold": "Bar Hang",

        // Plate-loaded rows get called by the plate, cables by the cable.
        "plate row": "Seated Plate Row",
        "plate loaded row": "Seated Plate Row",

        // Common shorthands that share no tokens with the catalog entry.
        "lat pull": "Lat Pulldown",
        "pull down": "Lat Pulldown",
        "leg extension machine": "Machine Leg Extension",
        "hammy curl": "Seated Leg Curl",
        "ham curl": "Seated Leg Curl",
        "tricep pushdown": "Triceps Pushdown",
        "rope pushdown": "Triceps Pushdown",
    ]

    /// The catalog name for `raw`, if the exact phrase is a known alias.
    ///
    /// Exact-phrase only, after normalising whitespace and punctuation: a
    /// substring rule would let "outer thigh machine" hijack "outer thigh
    /// machine warmup set" and beyond, and the matcher's own token logic is
    /// better at partial phrases than a lookup table is.
    static func canonical(for raw: String) -> String? {
        let key = raw.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: " ")
        return map[key]
    }
}
