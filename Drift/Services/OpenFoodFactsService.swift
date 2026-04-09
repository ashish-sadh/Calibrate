import Foundation

/// Fetches nutrition data from Open Food Facts by barcode.
/// Free, open-source, no API key needed. ~3M products.
/// https://world.openfoodfacts.org
enum OpenFoodFactsService {

    struct Product: Sendable {
        let barcode: String
        let name: String
        let brand: String?
        let servingSize: String?
        let calories: Double      // per 100g
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let fiberG: Double
        let servingSizeG: Double?  // parsed serving size in grams
        let ingredientsText: String?  // raw ingredients string from OpenFoodFacts
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
    static func lookup(barcode: String) async throws -> Product {
        let urlString = "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=product_name,brands,serving_size,nutriments,ingredients_text"
        guard let url = URL(string: urlString) else {
            throw LookupError.networkError("Invalid URL")
        }

        Log.foodLog.info("Looking up barcode: \(barcode)")

        let (data, response) = try await URLSession.shared.data(from: url)

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

        let calories = nutriments["energy-kcal_100g"] as? Double
            ?? nutriments["energy-kcal"] as? Double ?? 0
        let protein = nutriments["proteins_100g"] as? Double
            ?? nutriments["proteins"] as? Double ?? 0
        let carbs = nutriments["carbohydrates_100g"] as? Double
            ?? nutriments["carbohydrates"] as? Double ?? 0
        let fat = nutriments["fat_100g"] as? Double
            ?? nutriments["fat"] as? Double ?? 0
        let fiber = nutriments["fiber_100g"] as? Double
            ?? nutriments["fiber"] as? Double ?? 0

        let name = product["product_name"] as? String ?? "Unknown Product"
        let brand = product["brands"] as? String
        let servingStr = product["serving_size"] as? String

        guard calories > 0 || protein > 0 || carbs > 0 || fat > 0 else {
            throw LookupError.noNutrition
        }

        let servingG = parseServingSize(servingStr)
        let ingredientsText = product["ingredients_text"] as? String

        Log.foodLog.info("Found: \(name) (\(brand ?? "")) - \(Int(calories))cal/100g")

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
            ingredientsText: ingredientsText
        )
    }

    /// Text search for foods by name. Returns up to `limit` products with nutrition data.
    static func search(query: String, limit: Int = 10) async throws -> [Product] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://search.openfoodfacts.org/search?q=\(encoded)&page_size=\(limit)&fields=product_name,brands,serving_size,nutriments,code"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Drift/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = json["hits"] as? [[String: Any]] else { return [] }

        return products.compactMap { product in
            let nutriments = product["nutriments"] as? [String: Any] ?? [:]
            let calories = nutriments["energy-kcal_100g"] as? Double ?? nutriments["energy-kcal"] as? Double ?? 0
            let protein = nutriments["proteins_100g"] as? Double ?? 0
            let carbs = nutriments["carbohydrates_100g"] as? Double ?? 0
            let fat = nutriments["fat_100g"] as? Double ?? 0
            let fiber = nutriments["fiber_100g"] as? Double ?? 0

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
                           ingredientsText: product["ingredients_text"] as? String)
        }
    }

    /// Try to parse serving size like "30g", "100 ml", "8 fl oz", "1 cup (240g)" into grams.
    static func parseServingSize(_ str: String?) -> Double? {
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
