import Foundation
import Testing
@testable import Drift

// NOTE: These tests hit the actual Simulator Keychain. We pre-clear both
// providers in each test. Face ID is not enforced on the simulator, so the
// biometric gate is verified via the access-control flag being present, not
// a live prompt.

private func resetKeychain() {
    for provider in CloudVisionProvider.allCases {
        try? CloudVisionKey.clear(for: provider)
    }
    CloudVisionKey.dropCache()
}

// MARK: - Existence gate

@Test func hasReturnsFalseWhenNoKeyStored() async {
    resetKeychain()
    #expect(CloudVisionKey.has(provider: .anthropic) == false)
    #expect(CloudVisionKey.has(provider: .openai) == false)
}

@Test func hasReturnsTrueAfterSet() async throws {
    resetKeychain()
    try CloudVisionKey.set("sk-test-123", for: .anthropic)
    #expect(CloudVisionKey.has(provider: .anthropic) == true)
    #expect(CloudVisionKey.has(provider: .openai) == false)
    try CloudVisionKey.clear(for: .anthropic)
}

/// Regression for #275: `has()` must stay cheap/non-prompting so UI gates
/// (`.disabled(!has(...))`) can be computed on every body re-render without
/// stacking Face-ID / passcode popups. We can't assert the prompt
/// suppression directly on simulator, but we can assert that hundreds of
/// back-to-back calls stay consistent — exercising the
/// `kSecUseAuthenticationContext(interactionNotAllowed: true)` path.
@Test func hasIsCheapToCallRepeatedly() async throws {
    resetKeychain()
    try CloudVisionKey.set("sk-repeat", for: .anthropic)
    for _ in 0..<50 {
        #expect(CloudVisionKey.has(provider: .anthropic) == true)
        #expect(CloudVisionKey.has(provider: .openai) == false)
    }
    try CloudVisionKey.clear(for: .anthropic)
    for _ in 0..<10 {
        #expect(CloudVisionKey.has(provider: .anthropic) == false)
    }
}

// MARK: - Round trip

@Test func setThenGetRoundTrips() async throws {
    resetKeychain()
    try CloudVisionKey.set("sk-roundtrip-abc", for: .anthropic)
    let value = try await CloudVisionKey.get(for: .anthropic)
    #expect(value == "sk-roundtrip-abc")
    try CloudVisionKey.clear(for: .anthropic)
}

@Test func getReturnsNilWhenNotFound() async throws {
    resetKeychain()
    let value = try await CloudVisionKey.get(for: .openai)
    #expect(value == nil)
}

// MARK: - Clear

@Test func clearRemovesKey() async throws {
    resetKeychain()
    try CloudVisionKey.set("sk-gone", for: .openai)
    #expect(CloudVisionKey.has(provider: .openai) == true)
    try CloudVisionKey.clear(for: .openai)
    #expect(CloudVisionKey.has(provider: .openai) == false)
    let afterClear = try await CloudVisionKey.get(for: .openai)
    #expect(afterClear == nil)
}

@Test func clearIsIdempotent() async throws {
    resetKeychain()
    // Clearing nothing should not throw.
    try CloudVisionKey.clear(for: .anthropic)
    try CloudVisionKey.clear(for: .anthropic)
    #expect(CloudVisionKey.has(provider: .anthropic) == false)
}

// MARK: - Isolation between providers

@Test func twoProvidersCoexistIndependently() async throws {
    resetKeychain()
    try CloudVisionKey.set("anthropic-key", for: .anthropic)
    try CloudVisionKey.set("openai-key", for: .openai)

    let a = try await CloudVisionKey.get(for: .anthropic)
    let o = try await CloudVisionKey.get(for: .openai)
    #expect(a == "anthropic-key")
    #expect(o == "openai-key")

    try CloudVisionKey.clear(for: .anthropic)
    #expect(CloudVisionKey.has(provider: .anthropic) == false)
    #expect(CloudVisionKey.has(provider: .openai) == true)

    try CloudVisionKey.clear(for: .openai)
}

// MARK: - Overwrite

@Test func setOverwritesExistingKey() async throws {
    resetKeychain()
    try CloudVisionKey.set("first", for: .anthropic)
    try CloudVisionKey.set("second", for: .anthropic)
    let value = try await CloudVisionKey.get(for: .anthropic)
    #expect(value == "second")
    try CloudVisionKey.clear(for: .anthropic)
}

// MARK: - Cache

@Test func dropCacheForcesRecheckFromKeychain() async throws {
    resetKeychain()
    try CloudVisionKey.set("cached-value", for: .anthropic)
    // First read warms the cache.
    _ = try await CloudVisionKey.get(for: .anthropic)
    // Drop cache, underlying keychain still has the key, get returns it.
    CloudVisionKey.dropCache()
    let value = try await CloudVisionKey.get(for: .anthropic)
    #expect(value == "cached-value")
    try CloudVisionKey.clear(for: .anthropic)
}

// MARK: - Provider enum

@Test func providerDisplayNames() {
    #expect(CloudVisionProvider.anthropic.displayName.contains("Claude"))
    #expect(CloudVisionProvider.openai.displayName.contains("GPT"))
}
