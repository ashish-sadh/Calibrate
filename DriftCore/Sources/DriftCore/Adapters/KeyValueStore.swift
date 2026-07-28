import Foundation

/// A minimal key–value persistence seam.
///
/// On iOS/macOS the default `UserDefaultsKVStore` forwards every call to
/// `UserDefaults.standard`, so behaviour is byte-identical to before this seam
/// existed — same keys, same native value types, same on-disk representation.
///
/// On Android (Skip Fuse) the SharedPreferences-backed `UserDefaults` never
/// durably flushes to disk: writes update the in-memory map (so reads work
/// within a session) but `defaults.xml` stays frozen at install time, so every
/// setting, the active-workout session, and sync anchors are lost on process
/// death (#1108 / #1102 / #1104). The Android app therefore installs a
/// SQLite-backed store through `DriftPlatform.keyValueStore` (SQLite writes are
/// proven durable on that build).
///
/// Only the subset of `UserDefaults` that `Preferences` (plus the active-workout
/// session and the Health Connect anchor) actually uses is modelled. The
/// `object(forKey:)` escape hatch is split into `hasValue` (presence) and
/// `boolOrNil` (optional bool) so both backends can answer them natively
/// without returning `Any?`.
public protocol KeyValueStore: Sendable {
    func string(forKey key: String) -> String?
    func bool(forKey key: String) -> Bool
    func double(forKey key: String) -> Double
    func integer(forKey key: String) -> Int
    /// Raw bytes. Most durable state (WeightGoal, TDEE config, training/AI
    /// profile, custom exercises, …) is a `Codable` value JSON-encoded to
    /// `Data`; those sites route through here.
    func data(forKey key: String) -> Data?
    /// A `[String]` list (e.g. exercise favorites). Kept as a distinct native
    /// type so the UserDefaults store stays byte-identical on iOS rather than
    /// re-encoding existing users' arrays into `Data`.
    func stringArray(forKey key: String) -> [String]?

    /// True when a value is stored for `key` — the seam's replacement for
    /// `UserDefaults.object(forKey:) != nil` presence checks (used to tell
    /// "unset → use default" apart from an explicit `false`/`0`).
    func hasValue(forKey key: String) -> Bool

    /// The stored bool, or nil when unset — replaces
    /// `UserDefaults.object(forKey:) as? Bool` (default-ON toggles).
    func boolOrNil(forKey key: String) -> Bool?

    func set(_ value: String?, forKey key: String)
    func set(_ value: Bool, forKey key: String)
    func set(_ value: Double, forKey key: String)
    func set(_ value: Int, forKey key: String)
    func set(_ value: Data?, forKey key: String)
    func set(_ value: [String]?, forKey key: String)
    func removeObject(forKey key: String)
}

/// The default, iOS/macOS store: a thin, byte-identical forward to
/// `UserDefaults`. `@unchecked Sendable` because `UserDefaults` is documented
/// thread-safe but is not itself marked `Sendable`.
public struct UserDefaultsKVStore: KeyValueStore, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    public func bool(forKey key: String) -> Bool { defaults.bool(forKey: key) }
    public func double(forKey key: String) -> Double { defaults.double(forKey: key) }
    public func integer(forKey key: String) -> Int { defaults.integer(forKey: key) }
    public func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
    public func stringArray(forKey key: String) -> [String]? { defaults.stringArray(forKey: key) }
    public func hasValue(forKey key: String) -> Bool { defaults.object(forKey: key) != nil }
    public func boolOrNil(forKey key: String) -> Bool? { defaults.object(forKey: key) as? Bool }

    public func set(_ value: String?, forKey key: String) { defaults.set(value, forKey: key) }
    public func set(_ value: Bool, forKey key: String) { defaults.set(value, forKey: key) }
    public func set(_ value: Double, forKey key: String) { defaults.set(value, forKey: key) }
    public func set(_ value: Int, forKey key: String) { defaults.set(value, forKey: key) }
    public func set(_ value: Data?, forKey key: String) { defaults.set(value, forKey: key) }
    public func set(_ value: [String]?, forKey key: String) { defaults.set(value, forKey: key) }
    public func removeObject(forKey key: String) { defaults.removeObject(forKey: key) }
}

/// A `KeyValueStore` that encodes every value to a `String` and keeps them in a
/// lock-guarded in-memory cache. This is the base for the Android SQLite store:
/// all the encoding (bool→`"1"`/`"0"`, Double/Int→`description`, Data→base64,
/// `[String]`→JSON) and the thread-safe cache live here in DriftCore, so the
/// contract is Tier-0 testable by instantiating this class directly (no
/// emulator). Subclasses override `persist(_:forKey:)` to write the encoded
/// string to durable storage; a bare instance is a fine in-memory store.
open class StringEncodedKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: String] = [:]

    public init() {}

    // MARK: Subclass hooks

    /// Persist (or, for nil, delete) the already-encoded string for `key`.
    /// No-op in the base (pure in-memory). Called after the cache is updated.
    open func persist(_ value: String?, forKey key: String) {}

    /// Replace the in-memory cache wholesale — a subclass calls this once it has
    /// loaded the durable rows.
    public final func loadCache(_ values: [String: String]) {
        lock.lock(); cache = values; lock.unlock()
    }

    /// A snapshot of the current cache — a subclass flushes these to durable
    /// storage when it first loads (writes that landed before the durable store
    /// was ready).
    public final func cacheSnapshot() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        return cache
    }

    // MARK: Encoding

    private func raw(_ key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return cache[key]
    }

    private func store(_ value: String?, _ key: String) {
        lock.lock()
        if let value { cache[key] = value } else { cache[key] = nil }
        lock.unlock()
        persist(value, forKey: key)
    }

    public func string(forKey key: String) -> String? { raw(key) }
    public func bool(forKey key: String) -> Bool { raw(key) == "1" }
    public func double(forKey key: String) -> Double { raw(key).flatMap(Double.init) ?? 0 }
    public func integer(forKey key: String) -> Int { raw(key).flatMap { Int($0) } ?? 0 }
    public func data(forKey key: String) -> Data? { raw(key).flatMap { Data(base64Encoded: $0) } }
    public func stringArray(forKey key: String) -> [String]? {
        guard let raw = raw(key), let bytes = raw.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: bytes) else { return nil }
        return array
    }
    public func hasValue(forKey key: String) -> Bool { raw(key) != nil }
    public func boolOrNil(forKey key: String) -> Bool? { raw(key).map { $0 == "1" } }

    public func set(_ value: String?, forKey key: String) { store(value, key) }
    public func set(_ value: Bool, forKey key: String) { store(value ? "1" : "0", key) }
    public func set(_ value: Double, forKey key: String) { store(String(value), key) }
    public func set(_ value: Int, forKey key: String) { store(String(value), key) }
    public func set(_ value: Data?, forKey key: String) { store(value?.base64EncodedString(), key) }
    public func set(_ value: [String]?, forKey key: String) {
        let encoded = value
            .flatMap { try? JSONEncoder().encode($0) }
            .flatMap { String(data: $0, encoding: .utf8) }
        store(encoded, key)
    }
    public func removeObject(forKey key: String) { store(nil, key) }
}
