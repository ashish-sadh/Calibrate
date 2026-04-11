import Foundation

/// Fetches nutrition data from USDA FoodData Central.
/// Free API, no key required for basic access (~300K foods).
/// https://fdc.nal.usda.gov/api-guide.html
enum USDAFoodService {

    struct FoodItem: Sendable {
        let name: String
        let calories: Double      // per 100g
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let fiberG: Double
        let servingSizeG: Double
    }

    static func search(query: String, limit: Int = 8) async throws -> [FoodItem] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://api.nal.usda.gov/fdc/v1/foods/search?query=\(encoded)&pageSize=\(limit)&dataType=Foundation,SR%20Legacy&api_key=DEMO_KEY"
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

            let cal = nutrientValue(1008)    // Energy (kcal)
            let protein = nutrientValue(1003) // Protein
            let carbs = nutrientValue(1005)   // Carbohydrates
            let fat = nutrientValue(1004)     // Total fat
            let fiber = nutrientValue(1079)   // Fiber

            guard cal > 0 else { return nil }

            // USDA gives per 100g; use 100g as serving
            return FoodItem(
                name: name.capitalized,
                calories: cal,
                proteinG: protein,
                carbsG: carbs,
                fatG: fat,
                fiberG: fiber,
                servingSizeG: 100
            )
        }
    }
}
