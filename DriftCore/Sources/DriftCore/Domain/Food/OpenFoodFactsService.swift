import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import DriftCore

/// Fetches nutrition data from Open Food Facts by barcode.
/// Free, open-source, no API key needed. ~3M products.
/// https://world.openfoodfacts.org
public enum OpenFoodFactsService {

    public struct Product: Sendable {
        public let barcode: String
        public let name: String
        public let brand: String?
        public let servingSize: String?
        public let calories: Double      // per 100g
        public let proteinG: Double
        public let carbsG: Double
        public let fatG: Double
        public let fiberG: Double
        public let servingSizeG: Double?  // parsed serving size in grams (total serving, not per-piece)
        public let piecesPerServing: Int? // e.g. "3 pieces (85g)" → 3; nil if not a multi-piece serving
        public let ingredientsText: String?  // raw ingredients string from OpenFoodFacts
        public let novaGroup: Int?           // NOVA 1-4 processing level
        /// Whole-package size in g/ml from `product_quantity` (fallback: the
        /// `quantity` display string). nil when absent or implausible.
        public let packageSizeG: Double?

        public init(barcode: String, name: String, brand: String?, servingSize: String?,
                    calories: Double, proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double,
                    servingSizeG: Double?, piecesPerServing: Int?, ingredientsText: String?, novaGroup: Int?,
                    packageSizeG: Double? = nil) {
            self.barcode = barcode; self.name = name; self.brand = brand
            self.servingSize = servingSize; self.calories = calories
            self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG; self.fiberG = fiberG
            self.servingSizeG = servingSizeG; self.piecesPerServing = piecesPerServing
            self.ingredientsText = ingredientsText; self.novaGroup = novaGroup
            self.packageSizeG = packageSizeG
        }
    }

    enum LookupError: LocalizedError {
        case notFound
        case networkError(String)
        case noNutrition

        var errorDescription: String? {
            switch self {
            case .notFound: "Product not found"
            case .networkError(let msg): "Network error: \(msg)"
            case .noNutrition: "No nutrition data available"
            }
        }
    }

    /// Look up a product by barcode (EAN/UPC).
    public static func lookup(barcode: String) async throws -> Product {
        let urlString = "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=product_name,brands,serving_size,nutriments,ingredients_text,nova_group,quantity,product_quantity"
        guard let url = URL(string: urlString) else {
            throw LookupError.networkError("Invalid URL")
        }

        Log.foodLog.info("Looking up barcode: \(barcode)")

        let (data, response) = try await DriftPlatform.httpSession.data(for: URLRequest(url: url))

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LookupError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw LookupError.networkError("HTTP \(httpResponse.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? Int, status == 1,
              let product = json["product"] as? [String: Any] else {
            throw LookupError.notFound
        }

        let nutriments = product["nutriments"] as? [String: Any] ?? [:]

        let statedCalories = nutriments["energy-kcal_100g"] as? Double
            ?? nutriments["energy-kcal"] as? Double ?? 0
        let protein = nutriments["proteins_100g"] as? Double
            ?? nutriments["proteins"] as? Double ?? 0
        let carbs = nutriments["carbohydrates_100g"] as? Double
            ?? nutriments["carbohydrates"] as? Double ?? 0
        let fat = nutriments["fat_100g"] as? Double
            ?? nutriments["fat"] as? Double ?? 0
        let fiber = nutriments["fiber_100g"] as? Double
            ?? nutriments["fiber"] as? Double ?? 0

        // Atwater guard: OFF's `energy-kcal` fallback (per-serving) can end up
        // paired with per-100g macros, and crowd-sourced energy fields are
        // sometimes plain wrong. Prefer the macro-implied value when they clash.
        let calories = AtwaterCheck.reconciledCalories(
            stated: statedCalories, proteinG: protein, carbsG: carbs, fatG: fat, fiberG: fiber)
        if calories != statedCalories {
            Log.foodLog.info("Atwater guard (\(barcode)): stated \(Int(statedCalories))cal/100g vs macros \(Int(protein))P \(Int(carbs))C \(Int(fat))F → \(Int(calories))cal/100g")
        }

        let name = product["product_name"] as? String ?? "Unknown Product"
        let brand = product["brands"] as? String
        let servingStr = product["serving_size"] as? String

        guard calories > 0 || protein > 0 || carbs > 0 || fat > 0 else {
            throw LookupError.noNutrition
        }

        let servingG = parseServingSize(servingStr)
        let pieces = parsePieceCount(servingStr)
        let ingredientsText = product["ingredients_text"] as? String
        let novaGroup = product["nova_group"] as? Int
        let packageG = parsePackageSize(productQuantity: product["product_quantity"],
                                        quantityString: product["quantity"] as? String)

        Log.foodLog.info("Found: \(name) (\(brand ?? "")) - \(Int(calories))cal/100g, NOVA \(novaGroup ?? 0)")

        return Product(
            barcode: barcode,
            name: name,
            brand: brand,
            servingSize: servingStr,
            calories: calories,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat,
            fiberG: fiber,
            servingSizeG: servingG,
            piecesPerServing: pieces,
            ingredientsText: ingredientsText,
            novaGroup: novaGroup,
            packageSizeG: packageG
        )
    }

    /// Text search for foods by name. Returns up to `limit` products with nutrition data.
    public static func search(query: String, limit: Int = 10) async throws -> [Product] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://search.openfoodfacts.org/search?q=\(encoded)&page_size=\(limit)&fields=product_name,brands,serving_size,nutriments,code,quantity,product_quantity"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Drift/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await DriftPlatform.httpSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = json["hits"] as? [[String: Any]] else { return [] }

        return products.compactMap { product in
            let nutriments = product["nutriments"] as? [String: Any] ?? [:]
            let statedCalories = nutriments["energy-kcal_100g"] as? Double ?? nutriments["energy-kcal"] as? Double ?? 0
            let protein = nutriments["proteins_100g"] as? Double ?? 0
            let carbs = nutriments["carbohydrates_100g"] as? Double ?? 0
            let fat = nutriments["fat_100g"] as? Double ?? 0
            let fiber = nutriments["fiber_100g"] as? Double ?? 0

            // Atwater guard — see `lookup`. Runs before the `> 0` gate so a row
            // with real macros but a missing/zero energy field still surfaces.
            let calories = AtwaterCheck.reconciledCalories(
                stated: statedCalories, proteinG: protein, carbsG: carbs, fatG: fat, fiberG: fiber)

            guard calories > 0 else { return nil }
            let name = product["product_name"] as? String ?? ""
            guard !name.isEmpty else { return nil }
            // brands can be String or [String] depending on endpoint
            let brand: String?
            if let b = product["brands"] as? String { brand = b }
            else if let arr = product["brands"] as? [String] { brand = arr.first }
            else { brand = nil }
            let barcode = product["code"] as? String ?? ""
            let servingStr = product["serving_size"] as? String

            return Product(barcode: barcode, name: name, brand: brand, servingSize: servingStr,
                           calories: calories, proteinG: protein, carbsG: carbs, fatG: fat,
                           fiberG: fiber, servingSizeG: parseServingSize(servingStr),
                           piecesPerServing: parsePieceCount(servingStr),
                           ingredientsText: product["ingredients_text"] as? String,
                           novaGroup: product["nova_group"] as? Int,
                           packageSizeG: parsePackageSize(productQuantity: product["product_quantity"],
                                                          quantityString: product["quantity"] as? String))
        }
    }

    /// Whole-package size in g/ml. `product_quantity` is OFF's normalized
    /// numeric (arrives as a Number or a String depending on the product);
    /// fall back to parsing the `quantity` display string ("14 fl oz",
    /// "414 ml"). Sizes outside 10–5000 g/ml are database junk (a "4" pack
    /// count, a 0, a barcode pasted in the field) — treat as absent.
    public static func parsePackageSize(productQuantity: Any?, quantityString: String?) -> Double? {
        let numeric: Double? = {
            if let d = productQuantity as? Double, d > 0 { return d }
            if let s = productQuantity as? String, let d = Double(s), d > 0 { return d }
            return nil
        }()
        let fromString: Double? = parseServingSize(quantityString) ?? {
            // Liters only appear at package scale ("1 L", "1.5l"), never as a
            // serving — parsed here, not in parseServingSize.
            guard let s = quantityString?.lowercased(),
                  let regex = try? NSRegularExpression(pattern: #"(\d+\.?\d*)\s*l\b"#),
                  let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let range = Range(match.range(at: 1), in: s),
                  let liters = Double(String(s[range])) else { return nil }
            return liters * 1000
        }()
        guard let size = numeric ?? fromString else { return nil }
        return (10...5000).contains(size) ? size : nil
    }

    /// Parse piece/unit count from serving strings like "3 pieces (85g)" → 3, "2 bars (60g)" → 2.
    /// Returns nil if no multi-piece pattern found or count is 1.
    public static func parsePieceCount(_ str: String?) -> Int? {
        guard let str else { return nil }
        let cleaned = str.lowercased()
        let pattern = #"(\d+)\s*(?:pieces?|pcs?|bars?|pastries|cookies?|crackers?|sticks?|slices?|wafers?|biscuits?|rolls?|tablets?|capsules?|scoops?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
              let range = Range(match.range(at: 1), in: cleaned),
              let count = Int(String(cleaned[range])),
              count > 1 else { return nil }
        return count
    }

    /// Try to parse serving size like "30g", "100 ml", "8 fl oz", "1 cup (240g)" into grams.
    public static func parseServingSize(_ str: String?) -> Double? {
        guard let str else { return nil }
        let cleaned = str.lowercased()
        // Look for number followed by 'g'
        let gPattern = #"(\d+\.?\d*)\s*g\b"#
        if let regex = try? NSRegularExpression(pattern: gPattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           let range = Range(match.range(at: 1), in: cleaned) {
            return Double(String(cleaned[range]))
        }
        // Number followed by 'ml' (treat 1 ml ≈ 1 g for liquids)
        let mlPattern = #"(\d+\.?\d*)\s*ml"#
        if let regex = try? NSRegularExpression(pattern: mlPattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           let range = Range(match.range(at: 1), in: cleaned) {
            return Double(String(cleaned[range]))
        }
        // Number followed by 'fl oz' or 'fl. oz' (1 fl oz = 29.5735 ml ≈ g)
        let flOzPattern = #"(\d+\.?\d*)\s*fl\.?\s*oz"#
        if let regex = try? NSRegularExpression(pattern: flOzPattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           let range = Range(match.range(at: 1), in: cleaned),
           let flOz = Double(String(cleaned[range])) {
            return flOz * 29.5735
        }
        // Number followed by 'oz' alone (assume fl oz for beverages, weight oz for solids — default to weight)
        let ozPattern = #"(\d+\.?\d*)\s*oz\b"#
        if let regex = try? NSRegularExpression(pattern: ozPattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           let range = Range(match.range(at: 1), in: cleaned),
           let oz = Double(String(cleaned[range])) {
            return oz * 28.3495 // 1 oz = 28.35g
        }
        return nil
    }
}
