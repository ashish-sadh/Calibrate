import Foundation
import GRDB

struct BarcodeCache: Codable, Sendable, FetchableRecord, PersistableRecord {
    var barcode: String
    var name: String
    var brand: String?
    var caloriesPer100g: Double
    var proteinGPer100g: Double
    var carbsGPer100g: Double
    var fatGPer100g: Double
    var fiberGPer100g: Double
    var servingSizeG: Double?
    var servingDescription: String?
    var createdAt: String

    static let databaseTableName = "barcode_cache"

    enum CodingKeys: String, CodingKey {
        case barcode, name, brand
        case caloriesPer100g = "calories_per_100g"
        case proteinGPer100g = "protein_g_per_100g"
        case carbsGPer100g = "carbs_g_per_100g"
        case fatGPer100g = "fat_g_per_100g"
        case fiberGPer100g = "fiber_g_per_100g"
        case servingSizeG = "serving_size_g"
        case servingDescription = "serving_description"
        case createdAt = "created_at"
    }

    init(from product: OpenFoodFactsService.Product) {
        self.barcode = product.barcode
        self.name = product.name
        self.brand = product.brand
        self.caloriesPer100g = product.calories
        self.proteinGPer100g = product.proteinG
        self.carbsGPer100g = product.carbsG
        self.fatGPer100g = product.fatG
        self.fiberGPer100g = product.fiberG
        self.servingSizeG = product.servingSizeG
        self.servingDescription = product.servingSize
        self.createdAt = ISO8601DateFormatter().string(from: Date())
    }

    /// Convert to a display-friendly format matching OpenFoodFactsService.Product
    var displayName: String {
        [name, brand].compactMap { $0 }.joined(separator: " - ")
    }

    var macroSummary: String {
        "\(Int(caloriesPer100g))cal \(Int(proteinGPer100g))P \(Int(carbsGPer100g))C \(Int(fatGPer100g))F per 100g"
    }
}
