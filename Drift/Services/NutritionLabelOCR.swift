import Foundation
import DriftCore
import Vision
import UIKit

/// Extracts nutrition data from a photo of a nutrition label using Apple Vision OCR.
enum NutritionLabelOCR {

    struct ExtractedNutrition: Sendable {
        var name: String = ""
        var calories: Double = 0
        var proteinG: Double = 0
        var carbsG: Double = 0
        var fatG: Double = 0
        var fiberG: Double = 0
        var servingSize: String = ""
    }

    /// Run OCR on an image and extract nutrition facts.
    static func extract(from image: UIImage) async throws -> ExtractedNutrition {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        let recognizedText = try await recognizeText(in: cgImage)
        Log.foodLog.info("OCR recognized \(recognizedText.count) lines")

        return parseNutritionFromText(recognizedText)
    }

    private static func recognizeText(in image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }

                continuation.resume(returning: lines)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Parse nutrition values from OCR text lines.
    /// Looks for patterns like "Calories 200", "Total Fat 5g", "Protein 10g", etc.
    static func parseNutritionFromText(_ lines: [String]) -> ExtractedNutrition {
        var result = ExtractedNutrition()

        let allText = lines.joined(separator: "\n").lowercased()

        // Calories: "calories 200", "calories: 200", "energy 200kcal"
        result.calories = extractValue(from: allText, patterns: [
            #"calories\s*[:.]?\s*(\d+)"#,
            #"energy\s*[:.]?\s*(\d+)\s*kcal"#,
            #"cal\s*[:.]?\s*(\d+)"#,
        ])

        // Protein: "protein 10g", "protein: 10 g"
        result.proteinG = extractValue(from: allText, patterns: [
            #"protein\s*[:.]?\s*(\d+\.?\d*)\s*g"#,
        ])

        // Total Fat: "total fat 5g", "fat 5g"
        result.fatG = extractValue(from: allText, patterns: [
            #"total fat\s*[:.]?\s*(\d+\.?\d*)\s*g"#,
            #"fat\s*[:.]?\s*(\d+\.?\d*)\s*g"#,
        ])

        // Carbs: "total carbohydrate 20g", "carbs 20g"
        result.carbsG = extractValue(from: allText, patterns: [
            #"total carbohydrate\s*[:.]?\s*(\d+\.?\d*)\s*g"#,
            #"carbohydrates?\s*[:.]?\s*(\d+\.?\d*)\s*g"#,
            #"carbs\s*[:.]?\s*(\d+\.?\d*)\s*g"#,
        ])

        // Fiber: "dietary fiber 3g", "fibre 3g", "fiber 3g"
        result.fiberG = extractValue(from: allText, patterns: [
            #"dietary fib[re]+\s*[:.]?\s*(\d+\.?\d*)\s*g"#,
            #"fib[re]+\s*[:.]?\s*(\d+\.?\d*)\s*g"#,
        ])

        // Serving size: "serving size 1 cup (240g)", "serving size: 30g"
        for line in lines {
            let lower = line.lowercased()
            if lower.contains("serving size") || lower.contains("serv. size") {
                result.servingSize = line.replacingOccurrences(of: "(?i)serving size:?\\s*", with: "", options: .regularExpression)
                break
            }
        }

        Log.foodLog.info("OCR extracted: \(Int(result.calories))cal \(Int(result.proteinG))P \(Int(result.carbsG))C \(Int(result.fatG))F \(Int(result.fiberG))fiber")
        return result
    }

    private static func extractValue(from text: String, patterns: [String]) -> Double {
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text),
               let value = Double(String(text[range])) {
                return value
            }
        }
        return 0
    }

    enum OCRError: LocalizedError {
        case invalidImage
        var errorDescription: String? { "Could not process the image" }
    }
}
