import Foundation

/// Lightweight user preference profile for cross-session AI context.
/// Stored on-device in UserDefaults as JSON. Nothing leaves the device.
public struct UserAIProfile: Codable, Sendable {

    /// Dietary/lifestyle tags stated explicitly by the user in chat
    /// (e.g. "vegetarian", "keto", "GLP-1").
    public var explicitPreferences: [String]
    public var updatedAt: Date

    private static let key = "drift_user_ai_profile"

    public init(explicitPreferences: [String] = [], updatedAt: Date = Date()) {
        self.explicitPreferences = explicitPreferences
        self.updatedAt = updatedAt
    }

    public static func load() -> UserAIProfile {
        guard let data = DriftPlatform.keyValueStore.data(forKey: key),
              let profile = try? JSONDecoder().decode(UserAIProfile.self, from: data)
        else { return UserAIProfile() }
        return profile
    }

    public static func save(_ profile: UserAIProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        DriftPlatform.keyValueStore.set(data, forKey: key)
    }

    public static func clear() {
        DriftPlatform.keyValueStore.removeObject(forKey: key)
    }
}
