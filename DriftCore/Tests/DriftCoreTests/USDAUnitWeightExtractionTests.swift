import Testing
@testable import DriftCore

/// Tier 0 — USDA portion metadata is converted to per-unit gram weights locally.
@Suite struct USDAUnitWeightExtractionTests {
    @Test func extractsCommonPieceCupAndTablespoonModifiers() {
        let portions: [[String: Any]] = [
            ["amount": 1.0, "modifier": "medium (1-1/4\" dia)", "gramWeight": 12.0],
            ["amount": 1.0, "modifier": "cup, sliced", "gramWeight": 166.0],
            ["amount": 1.0, "modifier": "Tablespoon", "gramWeight": 9.5],
        ]

        let (piece, cup, tablespoon) = USDAFoodService.extractUnitWeights(from: portions)

        #expect(piece == 12)
        #expect(cup == 166)
        #expect(tablespoon == 9.5)
    }

    @Test func normalizesMultiUnitPortionsToOneUnit() {
        let portions: [[String: Any]] = [
            ["amount": 3.0, "modifier": "3 each", "gramWeight": 90.0],
            ["amount": 0.5, "modifier": "cup, chopped", "gramWeight": 80.0],
            ["amount": 2.0, "modifier": "2 tbsp", "gramWeight": 30.0],
        ]

        let (piece, cup, tablespoon) = USDAFoodService.extractUnitWeights(from: portions)

        #expect(piece == 30)
        #expect(cup == 160)
        #expect(tablespoon == 15)
    }

    @Test func skipsInvalidCandidatesBeforeUsingTheFirstSensibleMatch() {
        let portions: [[String: Any]] = [
            ["amount": 0.0, "modifier": "medium", "gramWeight": 40.0],
            ["amount": 1.0, "modifier": "each", "gramWeight": -5.0],
            ["amount": 1.0, "modifier": "whole fruit", "gramWeight": 125.0],
            ["amount": 1.0, "modifier": "berry", "gramWeight": 130.0],
        ]

        let (piece, _, _) = USDAFoodService.extractUnitWeights(from: portions)

        #expect(piece == 125)
    }

    @Test func returnsNilForMissingMalformedOrUnrecognizedPortions() {
        let portions: [[String: Any]] = [
            ["amount": 1.0, "gramWeight": 28.0],
            ["amount": 1.0, "modifier": "slice"],
            ["amount": 1.0, "modifier": "package", "gramWeight": 250.0],
        ]

        let (piece, cup, tablespoon) = USDAFoodService.extractUnitWeights(from: portions)

        #expect(piece == nil)
        #expect(cup == nil)
        #expect(tablespoon == nil)
    }
}
