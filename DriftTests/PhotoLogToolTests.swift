import Foundation
@testable import DriftCore
import Testing
import UIKit
@testable import Drift

// MARK: - Fakes

private actor FakeVisionClientForTool: CloudVisionClient {
    let response: PhotoLogResponse
    let error: CloudVisionError?

    init(response: PhotoLogResponse = .stub, error: CloudVisionError? = nil) {
        self.response = response
        self.error = error
    }

    func analyze(image: Data, prompt: String) async throws -> PhotoLogResponse {
        if let error { throw error }
        return response
    }
}

private struct OnlineReachability: ReachabilityChecking {
    let isOnline: Bool = true
}

@MainActor
private func resetState() {
    Preferences.photoLogProvider = .anthropic
    for provider in CloudVisionProvider.allCases {
        try? CloudVisionKey.clear(for: provider)
    }
    CloudVisionKey.dropCache()
    ToolRegistry.shared.unregister(name: PhotoLogTool.toolName)
}

private func makeImage() -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format)
        .image { ctx in
            UIColor.systemGreen.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
}

// MARK: - Conditional registration

@Test @MainActor func photoLogToolNotRegisteredWhenNoKey() {
    resetState()

    #expect(PhotoLogTool.isAvailable == false)
    PhotoLogTool.syncRegistration()
    #expect(ToolRegistry.shared.tool(named: PhotoLogTool.toolName) == nil)

    resetState()
}

@Test @MainActor func photoLogToolRegisteredWhenKeyPresent() throws {
    resetState()
    try CloudVisionKey.set("fake-key", for: .anthropic)

    #expect(PhotoLogTool.isAvailable == true)
    PhotoLogTool.syncRegistration()
    #expect(ToolRegistry.shared.tool(named: PhotoLogTool.toolName) != nil)

    resetState()
}

@Test @MainActor func syncRegistrationRemovesToolWhenKeyCleared() throws {
    resetState()
    try CloudVisionKey.set("fake-key", for: .anthropic)
    PhotoLogTool.syncRegistration()
    #expect(ToolRegistry.shared.tool(named: PhotoLogTool.toolName) != nil)

    try CloudVisionKey.clear(for: .anthropic)
    CloudVisionKey.dropCache()
    PhotoLogTool.syncRegistration()
    #expect(ToolRegistry.shared.tool(named: PhotoLogTool.toolName) == nil)

    resetState()
}

@Test @MainActor func registerAllIncludesPhotoLogWhenAvailable() throws {
    resetState()
    try CloudVisionKey.set("fake-key", for: .anthropic)

    ToolRegistration.registerAll()
    PhotoLogTool.syncRegistration(registry: ToolRegistry.shared)  // iOS-side conditional tool
    #expect(ToolRegistry.shared.tool(named: PhotoLogTool.toolName) != nil)

    resetState()
}

@Test @MainActor func registerAllOmitsPhotoLogWhenUnavailable() {
    resetState()
    ToolRegistration.registerAll()
    #expect(ToolRegistry.shared.tool(named: PhotoLogTool.toolName) == nil)
    // Text-only tools must still be present — the conditional gate must not
    // take out the rest of the registry.
    #expect(ToolRegistry.shared.tool(named: "log_food") != nil)
    #expect(ToolRegistry.shared.tool(named: "food_info") != nil)
}

// MARK: - Direct invocation

@Test @MainActor func runReturnsSummaryFromInjectedService() async throws {
    resetState()
    try CloudVisionKey.set("fake-key", for: .anthropic)

    let client = FakeVisionClientForTool(response: .stub)
    let service = PhotoLogService(client: client, reachability: OnlineReachability())
    let output = await PhotoLogTool.run(image: makeImage(), prompt: "what is this", service: service)

    #expect(output.toolsCalled == [PhotoLogTool.toolName])
    #expect(output.text.lowercased().contains("apple"))
    #expect(output.text.contains("cal"))

    resetState()
}

@Test @MainActor func runShortCircuitsWhenUnavailable() async {
    resetState()
    let output = await PhotoLogTool.run(image: makeImage())
    #expect(output.text.contains("Photo Log is off"))
    #expect(output.toolsCalled == [PhotoLogTool.toolName])
}

@Test @MainActor func runMapsUnauthorizedToFriendlyText() async throws {
    resetState()
    try CloudVisionKey.set("fake-key", for: .anthropic)

    let client = FakeVisionClientForTool(error: .unauthorized)
    let service = PhotoLogService(client: client, reachability: OnlineReachability())
    let output = await PhotoLogTool.run(image: makeImage(), service: service)
    #expect(output.text.contains("rejected"))

    resetState()
}

@Test @MainActor func runMapsRateLimitedToFriendlyText() async throws {
    resetState()
    try CloudVisionKey.set("fake-key", for: .anthropic)

    let client = FakeVisionClientForTool(error: .rateLimited)
    let service = PhotoLogService(client: client, reachability: OnlineReachability())
    let output = await PhotoLogTool.run(image: makeImage(), service: service)
    #expect(output.text.contains("throttling"))

    resetState()
}

// MARK: - Summary shaping

@Test func summaryHandlesEmptyItems() {
    let response = PhotoLogResponse(items: [], overallConfidence: .low, notes: nil)
    let text = PhotoLogTool.summarize(response: response)
    #expect(text.contains("Couldn't identify"))
}

@Test func summaryListsFirstThreeAndCountsExtras() {
    let mk: (String) -> PhotoLogItem = { name in
        PhotoLogItem(name: name, grams: 100, calories: 100,
                      proteinG: 10, carbsG: 10, fatG: 5, confidence: .high)
    }
    let response = PhotoLogResponse(
        items: [mk("dal"), mk("rice"), mk("sabzi"), mk("roti"), mk("raita")],
        overallConfidence: .high, notes: nil
    )
    let text = PhotoLogTool.summarize(response: response)
    #expect(text.contains("dal, rice, sabzi"))
    #expect(text.contains("+2 more"))
    #expect(text.contains("high confidence"))
}

@Test func summaryIncludesCalAndProteinTotals() {
    let items = [
        PhotoLogItem(name: "egg", grams: 50, calories: 70, proteinG: 6, carbsG: 0, fatG: 5, confidence: .high),
        PhotoLogItem(name: "toast", grams: 40, calories: 130, proteinG: 4, carbsG: 25, fatG: 1, confidence: .medium)
    ]
    let response = PhotoLogResponse(items: items, overallConfidence: .medium, notes: nil)
    let text = PhotoLogTool.summarize(response: response)
    #expect(text.contains("200 cal"))
    #expect(text.contains("10g protein"))
    #expect(text.contains("medium confidence"))
}
