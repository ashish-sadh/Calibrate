import Foundation

/// OpenFoodFacts-coupled convenience initializer for BarcodeCache.
extension BarcodeCache {
    public init(from product: OpenFoodFactsService.Product) {
        self.init(
            barcode: product.barcode,
            name: product.name,
            brand: product.brand,
            caloriesPer100g: product.calories,
            proteinGPer100g: product.proteinG,
            carbsGPer100g: product.carbsG,
            fatGPer100g: product.fatG,
            fiberGPer100g: product.fiberG,
            servingSizeG: product.servingSizeG,
            servingDescription: product.servingSize,
            packageSizeG: product.packageSizeG,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}
