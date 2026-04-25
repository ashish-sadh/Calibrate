import Foundation
import DriftCore
import GRDB

extension AppDatabase {
    /// The shared database for the application (production).
    static let shared = makeShared()

    private static func makeShared() -> AppDatabase {
        do {
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directoryURL = appSupportURL.appendingPathComponent("Drift", isDirectory: true)
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            let databaseURL = directoryURL.appendingPathComponent("drift.sqlite")
            Log.database.info("Opening database at \(databaseURL.path)")
            let dbPool = try DatabasePool(path: databaseURL.path, configuration: makeConfiguration())
            let database = try AppDatabase(dbPool)

            // Seed + refresh foods from bundled JSON on every launch. New
            // rows get inserted; existing DB-sourced rows get calories,
            // macros, and ingredients re-synced from the JSON (so stale
            // values from older installs don't stick around — see
            // "Coffee (with milk) 0 cal" complaint 2026-04-21). User-scanned
            // foods (barcode / recipe / photo_log / custom) are never touched.
            try database.seedFoodsFromJSON()
            Log.database.info("Database ready")

            return database
        } catch {
            Log.database.fault("Database setup failed: \(error.localizedDescription). Attempting recovery...")
            // Recovery: delete corrupt database and try again
            do {
                let fileManager = FileManager.default
                let appSupportURL = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                let dbURL = appSupportURL.appendingPathComponent("Drift/drift.sqlite")
                try? fileManager.removeItem(at: dbURL)
                try? fileManager.removeItem(at: URL(fileURLWithPath: dbURL.path + "-wal"))
                try? fileManager.removeItem(at: URL(fileURLWithPath: dbURL.path + "-shm"))
                Log.database.info("Deleted corrupt database, recreating...")
                let directoryURL = appSupportURL.appendingPathComponent("Drift", isDirectory: true)
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                let dbPool = try DatabasePool(path: dbURL.path, configuration: makeConfiguration())
                let database = try AppDatabase(dbPool)
                try database.seedFoodsFromJSON()
                Log.database.info("Database recovered successfully")
                return database
            } catch {
                fatalError("Database setup failed and recovery failed: \(error)")
            }
        }
    }

    /// An empty in-memory database for testing and previews.
    static func empty() throws -> AppDatabase {
        let dbQueue = try DatabaseQueue(configuration: makeConfiguration())
        return try AppDatabase(dbQueue)
    }

    private static func makeConfiguration() -> Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        return config
    }
}
