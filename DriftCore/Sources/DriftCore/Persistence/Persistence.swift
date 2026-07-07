import Foundation
import GRDB

extension AppDatabase {
    /// The shared database for the application (production).
    public static let shared = makeShared()

    /// Location of the live SQLite file. Exposed so backup/restore can swap
    /// it atomically without re-deriving the path in three places.
    public static func databaseFileURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("Drift", isDirectory: true)
            .appendingPathComponent("drift.sqlite")
    }

    private static func makeShared() -> AppDatabase {
        do {
            return try openAndSeed()
        } catch {
            // Only a genuinely corrupt file justifies DELETING the user's data.
            // A transient disk-full / IO / permission error must NOT wipe the DB
            // and must NOT fatalError (which would crash-loop the launch and
            // trap the user out of the app). (#958)
            if isCorruptionError(error) {
                Log.database.fault("Database corrupt (\(error.localizedDescription)). Deleting and recreating…")
                do {
                    try deleteDatabaseFiles()
                    let database = try openAndSeed()
                    Log.database.info("Database recovered after corruption")
                    return database
                } catch {
                    Log.database.fault("Corruption recovery failed: \(error). Falling back to in-memory DB.")
                    return inMemoryFallback()
                }
            } else {
                Log.database.fault("Database open failed, non-corruption (\(error.localizedDescription)). Retrying without delete…")
                do {
                    return try openAndSeed()
                } catch {
                    Log.database.fault("Retry failed: \(error). Falling back to in-memory DB; on-disk file preserved.")
                    return inMemoryFallback()
                }
            }
        }
    }

    /// Open the live database pool and refresh the bundled food seed.
    ///
    /// Seed + refresh foods from bundled JSON on every launch. New rows get
    /// inserted; existing DB-sourced rows get calories, macros, and ingredients
    /// re-synced from the JSON (so stale values from older installs don't stick
    /// around — see "Coffee (with milk) 0 cal" complaint 2026-04-21). User-scanned
    /// foods (barcode / recipe / photo_log / custom) are never touched.
    private static func openAndSeed() throws -> AppDatabase {
        let databaseURL = try databaseFileURL()
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        Log.database.info("Opening database at \(databaseURL.path)")
        let dbPool = try DatabasePool(path: databaseURL.path, configuration: makeConfiguration())
        let database = try AppDatabase(dbPool)
        try database.seedFoodsFromJSON()
        Log.database.info("Database ready")
        return database
    }

    private static func deleteDatabaseFiles() throws {
        let fm = FileManager.default
        let dbURL = try databaseFileURL()
        try? fm.removeItem(at: dbURL)
        try? fm.removeItem(at: URL(fileURLWithPath: dbURL.path + "-wal"))
        try? fm.removeItem(at: URL(fileURLWithPath: dbURL.path + "-shm"))
        try fm.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    /// Last-resort DB so the app still launches (degraded) instead of
    /// crash-looping. This session's writes won't persist, but the on-disk file
    /// is left untouched so a later launch (after the user frees disk space,
    /// fixes permissions, etc.) can recover the real data. (#958)
    private static func inMemoryFallback() -> AppDatabase {
        do {
            let database = try empty()
            try? database.seedFoodsFromJSON()
            return database
        } catch {
            // empty() only fails on catastrophic allocation failure; nothing
            // useful remains to do but crash honestly.
            fatalError("In-memory fallback DB failed: \(error)")
        }
    }

    /// True only for errors that mean the on-disk file itself is unusable and
    /// safe to delete. Disk-full / IO / permission errors return false so the
    /// recovery path never wipes recoverable user data. (#958)
    static func isCorruptionError(_ error: Error) -> Bool {
        let msg = "\(error)".lowercased()
        return msg.contains("malformed")
            || msg.contains("not a database")
            || msg.contains("file is encrypted")
    }

    /// An empty in-memory database for testing and previews.
    public static func empty() throws -> AppDatabase {
        let dbQueue = try DatabaseQueue(configuration: makeConfiguration())
        return try AppDatabase(dbQueue)
    }

    private static func makeConfiguration() -> Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        return config
    }
}
