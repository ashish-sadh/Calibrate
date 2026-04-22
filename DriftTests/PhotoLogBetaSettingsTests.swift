import Foundation
import Testing
@testable import Drift

/// Preferences + Keychain interaction tests for the Photo Log Beta BYOK
/// flow. View-layer behavior is covered manually in the simulator; here we
/// lock in the persistence contract: toggle + provider survive relaunch,
/// switching providers preserves the other provider's key, clearing keys
/// is idempotent. #224 / #266.

private func resetPhotoLogState() {
    Preferences.photoLogEnabled = false
    // Clear the stored raw value entirely so the default-fallback in
    // `Preferences.photoLogProvider.get` is what the next test observes.
    UserDefaults.standard.removeObject(forKey: "drift_photo_log_provider")
    for provider in CloudVisionProvider.allCases {
        try? CloudVisionKey.clear(for: provider)
    }
    CloudVisionKey.dropCache()
}

// MARK: - Preferences persistence

@Test func photoLogEnabledDefaultsFalse() {
    resetPhotoLogState()
    #expect(Preferences.photoLogEnabled == false)
}

@Test func photoLogEnabledPersistsAcrossReads() {
    resetPhotoLogState()
    Preferences.photoLogEnabled = true
    #expect(Preferences.photoLogEnabled == true)
    Preferences.photoLogEnabled = false
    #expect(Preferences.photoLogEnabled == false)
}

@Test func photoLogProviderDefaultsToGemini() {
    // Gemini has a free tier so new users can try Photo Log without billing.
    resetPhotoLogState()
    #expect(Preferences.photoLogProvider == .gemini)
}

@Test func photoLogProviderRoundTripsAcrossProviders() {
    resetPhotoLogState()
    Preferences.photoLogProvider = .openai
    #expect(Preferences.photoLogProvider == .openai)
    Preferences.photoLogProvider = .anthropic
    #expect(Preferences.photoLogProvider == .anthropic)
    Preferences.photoLogProvider = .gemini
    #expect(Preferences.photoLogProvider == .gemini)
}

// MARK: - Provider switching preserves the other key

@Test func switchingProviderPreservesOtherProviderKey() throws {
    resetPhotoLogState()
    try CloudVisionKey.set("anthropic-k", for: .anthropic)
    try CloudVisionKey.set("openai-k", for: .openai)

    Preferences.photoLogProvider = .openai
    #expect(CloudVisionKey.has(provider: .anthropic) == true)
    #expect(CloudVisionKey.has(provider: .openai) == true)

    Preferences.photoLogProvider = .anthropic
    #expect(CloudVisionKey.has(provider: .anthropic) == true)
    #expect(CloudVisionKey.has(provider: .openai) == true)

    try CloudVisionKey.clear(for: .anthropic)
    try CloudVisionKey.clear(for: .openai)
}

// MARK: - Clear behavior

@Test func clearKeyOnlyRemovesActiveProvider() throws {
    resetPhotoLogState()
    try CloudVisionKey.set("a-key", for: .anthropic)
    try CloudVisionKey.set("o-key", for: .openai)

    try CloudVisionKey.clear(for: .anthropic)
    #expect(CloudVisionKey.has(provider: .anthropic) == false)
    #expect(CloudVisionKey.has(provider: .openai) == true)

    try CloudVisionKey.clear(for: .openai)
}
