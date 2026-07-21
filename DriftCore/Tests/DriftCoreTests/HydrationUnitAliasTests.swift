import Testing
@testable import DriftCore

/// Tier 0 — deterministic alias normalization for hydration unit conversion.
@Suite struct HydrationUnitAliasTests {

    @Test func milliliterSpellingsAreEquivalent() {
        let aliases = ["ml", "milliliter", "millilitre", "milliliters", "millilitres"]

        for unit in aliases {
            #expect(HydrationService.parseMl(amount: 375, unit: unit) == 375)
        }
    }

    @Test func literSpellingsAreEquivalent() {
        let aliases = ["l", "liter", "litre", "liters", "litres"]

        for unit in aliases {
            #expect(HydrationService.parseMl(amount: 1.25, unit: unit) == 1_250)
        }
    }

    @Test func fluidOunceSpellingsUseTheSameConversionFactor() {
        let aliases = ["oz", "fl oz", "fluid oz", "fluid ounce", "fluid ounces", "ounce", "ounces"]

        for unit in aliases {
            #expect(HydrationService.parseMl(amount: 2, unit: unit) == 59.147)
        }
    }

    @Test func unitMatchingIgnoresOuterWhitespaceAndLetterCase() {
        #expect(HydrationService.parseMl(amount: 2, unit: "  CUPS  ") == 480)
        #expect(HydrationService.parseMl(amount: 3, unit: " Fluid Ounces ") == 88.7205)
        #expect(HydrationService.parseMl(amount: 0.5, unit: " LITRE ") == 500)
    }
}
