import Testing
@testable import DriftCore

/// Tier 0 — deterministic indexes derived from the bundled biomarker catalog.
@Suite struct BiomarkerKnowledgeBaseCatalogTests {
    @Test func bundledCatalogLoadsEveryDefinition() {
        let definitions = BiomarkerKnowledgeBase.all

        #expect(definitions.count == 80)
        #expect(definitions.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
        #expect(Set(definitions.map(\.id)).count == definitions.count)
    }

    @Test func idIndexExactlyMirrorsCatalog() {
        let definitions = BiomarkerKnowledgeBase.all
        let index = BiomarkerKnowledgeBase.byId

        #expect(Set(index.keys) == Set(definitions.map(\.id)))
        for definition in definitions {
            #expect(index[definition.id]?.name == definition.name)
            #expect(index[definition.id]?.unit == definition.unit)
        }
    }

    @Test func categoriesUseStableDisplayOrder() {
        #expect(BiomarkerKnowledgeBase.categories == [
            "Heart Health",
            "Metabolic Health",
            "Hormones",
            "Thyroid",
            "Vitamins & Minerals",
            "Inflammation",
            "Blood Cells",
            "Liver",
            "Kidney",
        ])
    }

    @Test func categoryIndexPartitionsWholeCatalog() {
        let grouped = BiomarkerKnowledgeBase.byCategory
        let groupedDefinitions = grouped.values.flatMap { $0 }

        #expect(Set(grouped.keys) == Set(BiomarkerKnowledgeBase.categories))
        #expect(groupedDefinitions.count == BiomarkerKnowledgeBase.all.count)
        #expect(Set(groupedDefinitions.map(\.id)) == Set(BiomarkerKnowledgeBase.all.map(\.id)))
        for (category, definitions) in grouped {
            #expect(definitions.allSatisfy { $0.category == category })
        }
    }

    @Test func impactCategoriesAreUniqueInFirstSeenOrder() {
        #expect(BiomarkerKnowledgeBase.impactCategories == [
            "Heart Health",
            "Fitness",
            "Healthspan",
            "Metabolic Health",
            "Cognitive Performance",
            "Hormones",
            "Sleep",
            "Strain",
            "Thyroid",
            "Vitamins & Minerals",
            "Inflammation",
            "Blood Cells",
            "Liver",
            "Kidney",
            "Longevity",
        ])
    }
}
