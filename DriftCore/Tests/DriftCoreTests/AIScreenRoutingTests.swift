import Testing
@testable import DriftCore

@Suite struct AIScreenRoutingTests {
    @Test func serviceNamesMapDomainOwnedScreens() {
        #expect(AIScreen.food.serviceName == "food")
        #expect(AIScreen.weight.serviceName == "weight")
        #expect(AIScreen.goal.serviceName == "weight")
        #expect(AIScreen.exercise.serviceName == "exercise")
        #expect(AIScreen.bodyRhythm.serviceName == "sleep")
        #expect(AIScreen.supplements.serviceName == "supplement")
        #expect(AIScreen.glucose.serviceName == "glucose")
        #expect(AIScreen.biomarkers.serviceName == "biomarker")
        #expect(AIScreen.bodyComposition.serviceName == "body_comp")
    }

    @Test func serviceNamesAreNilForUnownedScreens() {
        #expect(AIScreen.dashboard.serviceName == nil)
        #expect(AIScreen.cycle.serviceName == nil)
        #expect(AIScreen.settings.serviceName == nil)
        #expect(AIScreen.algorithm.serviceName == nil)
    }

    @Test func defaultToolsMapDomainScreens() {
        #expect(AIScreen.food.defaultTools == ["log_food", "food_info"])
        #expect(AIScreen.weight.defaultTools == ["weight_info", "log_weight"])
        #expect(AIScreen.goal.defaultTools == ["weight_info", "log_weight"])
        #expect(AIScreen.exercise.defaultTools == ["start_workout", "exercise_info"])
        #expect(AIScreen.bodyRhythm.defaultTools == ["sleep_recovery"])
        #expect(AIScreen.supplements.defaultTools == ["supplements", "mark_supplement"])
        #expect(AIScreen.glucose.defaultTools == ["glucose"])
        #expect(AIScreen.biomarkers.defaultTools == ["biomarkers"])
        #expect(AIScreen.bodyComposition.defaultTools == ["body_comp"])
    }

    @Test func defaultToolsUseGeneralFallbackForUnownedScreens() {
        let fallback = ["food_info", "weight_info"]

        #expect(AIScreen.dashboard.defaultTools == fallback)
        #expect(AIScreen.cycle.defaultTools == fallback)
        #expect(AIScreen.settings.defaultTools == fallback)
        #expect(AIScreen.algorithm.defaultTools == fallback)
    }
}
