import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import DriftCore

/// Fetches nutrition data from USDA FoodData Central.
/// Free API, no key required for basic access (~300K foods).
/// Rate limited: max 1 request/sec, max 50 per session.
/// https://fdc.nal.usda.gov/api-guide.html
@MainActor
public enum USDAFoodService {

    public struct FoodItem: Sendable {
        public let name: String
        public let calories: Double      // per 100g
        public let proteinG: Double
        public let carbsG: Double
        public let fatG: Double
        public let fiberG: Double
        public let servingSizeG: Double
        /// Per-unit gram weights extracted from USDA's `foodPortions` array.
        /// Drops the 100g-synthesised defaults that caused the strawberry bug
        /// (audit 2026-04-24): when USDA returns `1 medium = 12g`, we honour
        /// that instead of forcing `ServingUnit` to invent `piece = 100g`.
        public let pieceSizeG: Double?
        public let cupSizeG: Double?
        public let tbspSizeG: Double?

        init(name: String, calories: Double, proteinG: Double, carbsG: Double,
             fatG: Double, fiberG: Double, servingSizeG: Double,
             pieceSizeG: Double? = nil, cupSizeG: Double? = nil, tbspSizeG: Double? = nil) {
            self.name = name
            self.calories = calories
            self.proteinG = proteinG
            self.carbsG = carbsG
            self.fatG = fatG
            self.fiberG = fiberG
            self.servingSizeG = servingSizeG
            self.pieceSizeG = pieceSizeG
            self.cupSizeG = cupSizeG
            self.tbspSizeG = tbspSizeG
        }
    }

    // Register a free key at https://fdc.nal.usda.gov/api-guide.html to raise
    // the rate limit from 1,000 req/day to 3,600 req/hour. Set via
    // Preferences.usdaApiKey — falls back to DEMO_KEY only when unset.
    private static let demoKey = "DEMO_KEY"
    private static var resolvedApiKey: String {
        let key = Preferences.usdaApiKey
        return key.isEmpty ? demoKey : key
    }

    private static let maxRequestsPerSession = 50
    private static var sessionRequestCount = 0
    private static var lastRequestTime: Date?

    public static func search(query: String, limit: Int = 8) async throws -> [FoodItem] {
        // Rate limiting: max 50 requests per session
        guard sessionRequestCount < maxRequestsPerSession else { return [] }

        // Throttle: minimum 1 second between requests
        if let last = lastRequestTime {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < 1.0 {
                try await Task.sleep(for: .milliseconds(Int((1.0 - elapsed) * 1000)))
            }
        }
        sessionRequestCount += 1
        lastRequestTime = Date()
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://api.nal.usda.gov/fdc/v1/foods/search?query=\(encoded)&pageSize=\(limit)&dataType=Foundation,SR%20Legacy&api_key=\(resolvedApiKey)"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let foods = json["foods"] as? [[String: Any]] else { return [] }

        return foods.compactMap { food in
            guard let name = food["description"] as? String else { return nil }
            let nutrients = (food["foodNutrients"] as? [[String: Any]]) ?? []

            func nutrientValue(_ id: Int) -> Double {
                nutrients.first { ($0["nutrientId"] as? Int) == id }?["value"] as? Double ?? 0
            }

            let statedCal = nutrientValue(1008) // Energy (kcal)
            let protein = nutrientValue(1003)   // Protein
            let carbs = nutrientValue(1005)     // Carbohydrates
            let fat = nutrientValue(1004)       // Total fat
            let fiber = nutrientValue(1079)     // Fiber

            // Atwater guard — USDA rows are normally self-consistent, but the
            // same energy/macro sanity check applies uniformly across sources.
            let cal = AtwaterCheck.reconciledCalories(
                stated: statedCal, proteinG: protein, carbsG: carbs, fatG: fat, fiberG: fiber)

            guard cal > 0 else { return nil }

            let portions = (food["foodPortions"] as? [[String: Any]]) ?? []
            let (piece, cup, tbsp) = extractUnitWeights(from: portions)

            // USDA nutrients are per 100g; use 100g as the normalised serving.
            return FoodItem(
                name: name.capitalized,
                calories: cal,
                proteinG: protein,
                carbsG: carbs,
                fatG: fat,
                fiberG: fiber,
                servingSizeG: 100,
                pieceSizeG: piece,
                cupSizeG: cup,
                tbspSizeG: tbsp
            )
        }
    }

    /// Pull per-unit gram weights out of USDA's `foodPortions` array.
    /// Example for strawberries:
    ///   [{"amount":1,"modifier":"cup, sliced","gramWeight":166},
    ///    {"amount":1,"modifier":"medium (1-1/4\" dia)","gramWeight":12}, ...]
    /// Returns `(pieceG, cupG, tbspG)` as nil when no sensible portion matches.
    public nonisolated static func extractUnitWeights(from portions: [[String: Any]]) -> (Double?, Double?, Double?) {
        func weight(for predicate: (String) -> Bool) -> Double? {
            for p in portions {
                guard let mod = (p["modifier"] as? String)?.lowercased() else { continue }
                let amount = (p["amount"] as? Double) ?? 1
                let g = (p["gramWeight"] as? Double) ?? 0
                guard amount > 0, g > 0, predicate(mod) else { continue }
                return g / amount
            }
            return nil
        }

        let piece = weight(for: { mod in
            mod.contains("medium") || mod == "each" || mod.contains(" each") ||
            mod.hasPrefix("1 ") || mod.contains("whole") || mod.contains("berry")
        })
        let cup = weight(for: { mod in
            // Prefer "cup, sliced" / "cup, chopped" over "1 cup" to avoid
            // duplicate matches; the simpler "cup" comparator still works.
            mod.contains("cup")
        })
        let tbsp = weight(for: { mod in
            mod.contains("tbsp") || mod.contains("tablespoon")
        })
        return (piece, cup, tbsp)
    }
}
