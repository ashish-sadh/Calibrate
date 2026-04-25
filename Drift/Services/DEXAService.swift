import Foundation
import DriftCore

/// Domain service for DEXA scan operations.
@MainActor
enum DEXAService {

    /// Fetch all DEXA scans, ordered by date descending.
    static func fetchScans() -> [DEXAScan] {
        (try? AppDatabase.shared.fetchDEXAScans()) ?? []
    }

    /// Fetch regional breakdown for a specific scan.
    static func fetchRegions(forScanId id: Int64) -> [DEXARegion] {
        (try? AppDatabase.shared.fetchDEXARegions(forScanId: id)) ?? []
    }

    /// Save a manually entered DEXA scan.
    static func saveScan(_ scan: inout DEXAScan) {
        try? AppDatabase.shared.saveDEXAScan(&scan)
    }

    /// Import scans parsed from a BodySpec PDF. Returns count imported.
    static func importBodySpecScans(_ parsedScans: [BodySpecPDFParser.ParsedScan]) throws -> Int {
        try AppDatabase.shared.importBodySpecScans(parsedScans)
    }

    /// Delete a single DEXA scan.
    static func deleteScan(id: Int64) {
        try? AppDatabase.shared.deleteDEXAScan(id: id)
    }

    /// Delete all DEXA scans.
    static func deleteAllScans() {
        try? AppDatabase.shared.deleteAllDEXAScans()
    }
}
