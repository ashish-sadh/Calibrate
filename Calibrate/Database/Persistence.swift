import Foundation
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
            let directoryURL = appSupportURL.appendingPathComponent("Calibrate", isDirectory: true)
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            let databaseURL = directoryURL.appendingPathComponent("calibrate.sqlite")
            let dbPool = try DatabasePool(path: databaseURL.path, configuration: makeConfiguration())
            let database = try AppDatabase(dbPool)

            // Seed foods from bundled JSON on first launch
            try database.seedFoodsFromJSON()

            return database
        } catch {
            fatalError("Database setup failed: \(error)")
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
        config.prepareDatabase { db in
            db.trace { print("SQL: \($0)") }
        }
        return config
    }
}
