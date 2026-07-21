import Testing
@testable import DriftCore

/// Tier 0 — deterministic lab-parser alias contracts. These protect the
/// catalog link and the absolute-vs-percentage WBC differential distinction.
@Suite struct LabAliasesTests {

    @Test func everyAliasTargetExistsInBiomarkerCatalog() {
        for id in LabAliases.byBiomarkerId.keys {
            #expect(BiomarkerKnowledgeBase.byId[id] != nil, "Alias target '\(id)' is missing from the catalog")
        }
    }

    @Test func indianLabConventionsMapToExpectedMarkers() {
        let cases: [(id: String, alias: String)] = [
            ("alt", "sgpt"),
            ("ast", "sgot"),
            ("glucose", "fbs"),
            ("glucose", "ppbs"),
            ("ag_ratio", "a/g ratio"),
            ("esr", "esr"),
        ]

        for item in cases {
            #expect(LabAliases.byBiomarkerId[item.id]?.contains(item.alias) == true)
        }
    }

    @Test func differentialIdentifierSetsAreCompleteAndDisjoint() {
        #expect(LabAliases.pctBiomarkerIds == [
            "neutrophil_pct", "lymphocyte_pct", "monocyte_pct", "eosinophil_pct", "basophil_pct",
        ])
        #expect(LabAliases.absBiomarkerIds == [
            "neutrophils", "lymphocytes", "monocytes", "eosinophils", "basophils",
        ])
        #expect(LabAliases.pctBiomarkerIds.isDisjoint(with: LabAliases.absBiomarkerIds))
    }

    @Test func absoluteDifferentialAliasesRequireAbsoluteMarker() {
        for id in LabAliases.absBiomarkerIds {
            let aliases = LabAliases.byBiomarkerId[id] ?? []
            #expect(!aliases.isEmpty)
            #expect(aliases.allSatisfy { $0.contains("abs") }, "Absolute marker '\(id)' has an ambiguous alias")
        }
    }

    @Test func percentageDifferentialAliasesExcludeAbsoluteMarker() {
        for id in LabAliases.pctBiomarkerIds {
            let aliases = LabAliases.byBiomarkerId[id] ?? []
            #expect(!aliases.isEmpty)
            #expect(aliases.allSatisfy { !$0.contains("abs") }, "Percentage marker '\(id)' has an absolute-count alias")
        }
    }
}
