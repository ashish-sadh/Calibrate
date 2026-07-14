import Testing
@testable import DriftCore

/// Tier 0 — the FM camelCase → catalog snake_case ID map. This map is what
/// stops the Apple Foundation Models extractor from writing un-nameable,
/// un-range-checkable, duplicate biomarker rows (the pre-2026-07-14 bug where
/// FM's `ldl` never collided with regex's `ldl_cholesterol`).
struct BiomarkerCatalogMapTests {

    @Test func camelCaseFMIDsResolveToCatalog() {
        let cases: [(String, String)] = [
            ("ldl", "ldl_cholesterol"),
            ("hdl", "hdl_cholesterol"),
            ("totalCholesterol", "total_cholesterol"),
            ("tsh", "thyroid_tsh"),
            ("vitaminD", "vitamin_d"),
            ("vitaminB12", "vitamin_b12"),
            ("freeT4", "free_t4"),
            ("hemoglobin", "hemoglobin"),
            ("hba1c", "hba1c"),
            ("sgpt", "alt"),
            ("sgot", "ast"),
            ("uricAcid", "uric_acid"),
            ("apoB", "apolipoprotein_b"),
        ]
        for (raw, expected) in cases {
            #expect(BiomarkerCatalogMap.canonicalID(raw) == expected, "\(raw) → \(String(describing: BiomarkerCatalogMap.canonicalID(raw))), wanted \(expected)")
        }
    }

    @Test func alreadyCanonicalIDsPassThrough() {
        for id in ["ldl_cholesterol", "vitamin_d", "thyroid_tsh", "hba1c", "esr", "vldl_cholesterol"] {
            #expect(BiomarkerCatalogMap.canonicalID(id) == id)
        }
    }

    @Test func unknownIDsReturnNil() {
        for junk in ["Final", "H", "L", "notABiomarker", "status", ""] {
            #expect(BiomarkerCatalogMap.canonicalID(junk) == nil, "'\(junk)' should not resolve")
        }
    }

    @Test func everyResolvedIDExistsInKnowledgeBase() {
        // Every override target must be a real catalog biomarker, else the map
        // routes FM output to a phantom ID.
        for raw in ["ldl", "hdl", "vldl", "totalCholesterol", "nonHdl", "tsh", "vitaminD",
                    "vitaminB12", "sgpt", "sgot", "totalProtein", "directBilirubin", "crp",
                    "totalT3", "totalT4", "freeT3", "freeT4", "agRatio", "lpA"] {
            if let canon = BiomarkerCatalogMap.canonicalID(raw) {
                #expect(BiomarkerKnowledgeBase.byId[canon] != nil, "\(raw) → \(canon) not in catalog")
            }
        }
    }

    // MARK: - shouldFallBackToFM (the trigger the ID bug used to break)

    @Test func fmFallbackTriggersWhenPriorityMissing() {
        // Regex found 6 markers but no LDL → still fall back to FM.
        let ids = ["glucose", "hba1c", "ferritin", "vitamin_d", "thyroid_tsh", "hemoglobin"]
        #expect(LabExtractionPriority.shouldFallBackToFM(regexBiomarkerIDs: ids))
    }

    @Test func fmFallbackSkippedWhenAllPriorityPresent() {
        // The regression: with canonical IDs this subset check can now actually
        // be satisfied, so a complete regex result skips the FM call.
        let ids = ["glucose", "hba1c", "ldl_cholesterol", "ferritin", "vitamin_d", "thyroid_tsh"]
        #expect(!LabExtractionPriority.shouldFallBackToFM(regexBiomarkerIDs: ids))
    }

    @Test func fmFallbackTriggersUnderFiveResults() {
        #expect(LabExtractionPriority.shouldFallBackToFM(regexBiomarkerIDs: ["glucose", "ldl_cholesterol"]))
    }
}
