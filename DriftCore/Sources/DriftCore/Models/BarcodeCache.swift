import Foundation
import GRDB

public struct BarcodeCache: Codable, Sendable, FetchableRecord, PersistableRecord {
    public var barcode: String
    public var name: String
    public var brand: String?
    public var caloriesPer100g: Double
    public var proteinGPer100g: Double
    public var carbsGPer100g: Double
    public var fatGPer100g: Double
    public var fiberGPer100g: Double
    public var servingSizeG: Double?
    public var servingDescription: String?
    /// Whole-package size in g/ml (OpenFoodFacts product_quantity). nil when
    /// the product data doesn't state it.
    public var packageSizeG: Double?
    public var createdAt: String

    public static let databaseTableName = "barcode_cache"

    enum CodingKeys: String, CodingKey {
        case barcode, name, brand
        case caloriesPer100g = "calories_per_100g"
        case proteinGPer100g = "protein_g_per_100g"
        case carbsGPer100g = "carbs_g_per_100g"
        case fatGPer100g = "fat_g_per_100g"
        case fiberGPer100g = "fiber_g_per_100g"
        case servingSizeG = "serving_size_g"
        case servingDescription = "serving_description"
        case packageSizeG = "package_size_g"
        case createdAt = "created_at"
    }

    public init(
        barcode: String,
        name: String,
        brand: String? = nil,
        caloriesPer100g: Double,
        proteinGPer100g: Double = 0,
        carbsGPer100g: Double = 0,
        fatGPer100g: Double = 0,
        fiberGPer100g: Double = 0,
        servingSizeG: Double? = nil,
        servingDescription: String? = nil,
        packageSizeG: Double? = nil,
        createdAt: String
    ) {
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.caloriesPer100g = caloriesPer100g
        self.proteinGPer100g = proteinGPer100g
        self.carbsGPer100g = carbsGPer100g
        self.fatGPer100g = fatGPer100g
        self.fiberGPer100g = fiberGPer100g
        self.servingSizeG = servingSizeG
        self.servingDescription = servingDescription
        self.packageSizeG = packageSizeG
        self.createdAt = createdAt
    }

    /// Convert to a display-friendly format matching OpenFoodFactsService.Product
    public var displayName: String {
        [name, brand].compactMap { $0 }.joined(separator: " - ")
    }

    public var macroSummary: String {
        "\(Int(caloriesPer100g))cal \(Int(proteinGPer100g))P \(Int(carbsGPer100g))C \(Int(fatGPer100g))F per 100g"
    }
}
