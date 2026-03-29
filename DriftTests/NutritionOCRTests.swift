import Foundation
import Testing
@testable import Drift

// MARK: - Nutrition Label OCR Parsing (15 tests)

@Test func ocrExtractsCalories() async throws {
    let lines = ["Nutrition Facts", "Serving Size 1 cup (240g)", "Calories 200", "Total Fat 5g"]
    let r = NutritionLabelOCR.parseNutritionFromText(lines)
    #expect(r.calories == 200)
}

@Test func ocrExtractsProtein() async throws {
    let lines = ["Protein 25g"]
    let r = NutritionLabelOCR.parseNutritionFromText(lines)
    #expect(r.proteinG == 25)
}

@Test func ocrExtractsFat() async throws {
    let lines = ["Total Fat 12g", "Saturated Fat 3g"]
    let r = NutritionLabelOCR.parseNutritionFromText(lines)
    #expect(r.fatG == 12) // total fat, not saturated
}

@Test func ocrExtractsCarbs() async throws {
    let lines = ["Total Carbohydrate 30g", "Dietary Fiber 4g", "Total Sugars 10g"]
    let r = NutritionLabelOCR.parseNutritionFromText(lines)
    #expect(r.carbsG == 30)
}

@Test func ocrExtractsFiber() async throws {
    let lines = ["Dietary Fiber 4g"]
    let r = NutritionLabelOCR.parseNutritionFromText(lines)
    #expect(r.fiberG == 4)
}

@Test func ocrExtractsFibreSpelling() async throws {
    let lines = ["Fibre 3g"] // UK spelling
    let r = NutritionLabelOCR.parseNutritionFromText(lines)
    #expect(r.fiberG == 3)
}

@Test func ocrFullNutritionLabel() async throws {
    let lines = [
        "Nutrition Facts",
        "Serving Size 2/3 cup (55g)",
        "Calories 230",
        "Total Fat 8g",
        "Total Carbohydrate 37g",
        "Dietary Fiber 4g",
        "Protein 3g",
    ]
    let r = NutritionLabelOCR.parseNutritionFromText(lines)
    #expect(r.calories == 230)
    #expect(r.fatG == 8)
    #expect(r.carbsG == 37)
    #expect(r.fiberG == 4)
    #expect(r.proteinG == 3)
}

@Test func ocrServingSize() async throws {
    let lines = ["Serving Size 1 cup (240g)", "Calories 200"]
    let r = NutritionLabelOCR.parseNutritionFromText(lines)
    #expect(r.servingSize.contains("240"))
}

@Test func ocrCaloriesWithColon() async throws {
    let lines = ["Calories: 150"]
    let r = NutritionLabelOCR.parseNutritionFromText(lines)
    #expect(r.calories == 150)
}

@Test func ocrDecimalValues() async throws {
    let lines = ["Protein 10.5g", "Total Fat 3.2g"]
    let r = NutritionLabelOCR.parseNutritionFromText(lines)
    #expect(abs(r.proteinG - 10.5) < 0.01)
    #expect(abs(r.fatG - 3.2) < 0.01)
}

@Test func ocrEmptyInput() async throws {
    let r = NutritionLabelOCR.parseNutritionFromText([])
    #expect(r.calories == 0 && r.proteinG == 0 && r.carbsG == 0 && r.fatG == 0)
}

@Test func ocrGarbageInput() async throws {
    let lines = ["Hello world", "Random text", "Not nutrition data"]
    let r = NutritionLabelOCR.parseNutritionFromText(lines)
    #expect(r.calories == 0)
}

@Test func ocrIndianStyleLabel() async throws {
    // Some Indian labels use "Energy 250kcal"
    let lines = ["Energy 250kcal", "Protein 8g", "Carbohydrates 40g", "Fat 6g", "Fibre 2g"]
    let r = NutritionLabelOCR.parseNutritionFromText(lines)
    #expect(r.calories == 250)
    #expect(r.proteinG == 8)
    #expect(r.carbsG == 40)
    #expect(r.fatG == 6)
    #expect(r.fiberG == 2)
}

@Test func ocrCaseInsensitive() async throws {
    let lines = ["CALORIES 300", "PROTEIN 20G", "TOTAL FAT 10G"]
    let r = NutritionLabelOCR.parseNutritionFromText(lines)
    #expect(r.calories == 300)
    #expect(r.proteinG == 20)
    #expect(r.fatG == 10)
}

@Test func ocrHandlesExtraSpaces() async throws {
    let lines = ["Calories   180", "Protein   15  g", "Total Fat   7  g"]
    let r = NutritionLabelOCR.parseNutritionFromText(lines)
    #expect(r.calories == 180)
    #expect(r.proteinG == 15)
    #expect(r.fatG == 7)
}
