import Foundation
import GRDB

// MARK: - DEXA Scan + Lab Report Operations

public extension AppDatabase {
    func saveDEXAScan(_ scan: inout DEXAScan) throws {
        try writer.write { [scan] db in
            // Upsert by scan_date
            if let existing = try DEXAScan.filter(Column("scan_date") == scan.scanDate).fetchOne(db) {
                var updated = scan
                updated.id = existing.id
                try updated.update(db)
            } else {
                var mutable = scan
                try mutable.insert(db)
            }
        }
        scan = try reader.read { db in
            try DEXAScan.filter(Column("scan_date") == scan.scanDate).fetchOne(db)
        } ?? scan
    }

    func saveDEXARegions(_ regions: [DEXARegion], forScanId scanId: Int64) throws {
        try writer.write { db in
            // Delete existing regions for this scan
            try DEXARegion.filter(Column("scan_id") == scanId).deleteAll(db)
            // Insert new ones
            for var region in regions {
                region.scanId = scanId
                try region.insert(db)
            }
        }
    }

    func fetchDEXAScans() throws -> [DEXAScan] {
        try reader.read { db in
            try DEXAScan.order(Column("scan_date").desc).fetchAll(db)
        }
    }

    func deleteDEXAScan(id: Int64) throws {
        try writer.write { db in
            // Regions cascade-delete via foreign key
            _ = try DEXAScan.deleteOne(db, id: id)
        }
    }

    func deleteAllDEXAScans() throws {
        try writer.write { db in
            _ = try DEXARegion.deleteAll(db)
            _ = try DEXAScan.deleteAll(db)
        }
    }

    func fetchDEXARegions(forScanId scanId: Int64) throws -> [DEXARegion] {
        try reader.read { db in
            try DEXARegion.filter(Column("scan_id") == scanId).fetchAll(db)
        }
    }

    /// Import parsed BodySpec scans (from PDF).
    func importBodySpecScans(_ parsedScans: [BodySpecParsedScan]) throws -> Int {
        var count = 0
        for parsed in parsedScans {
            var scan = DEXAScan(
                scanDate: parsed.scanDate,
                location: "BodySpec",
                totalMassKg: parsed.totalMassLbs.map { $0 / 2.20462 },
                fatMassKg: parsed.fatMassLbs.map { $0 / 2.20462 },
                leanMassKg: parsed.leanMassLbs.map { $0 / 2.20462 },
                boneMassKg: parsed.bmcLbs.map { $0 / 2.20462 },
                bodyFatPct: parsed.bodyFatPct,
                visceralFatKg: parsed.vatMassLbs.map { $0 / 2.20462 },
                boneDensityTotal: parsed.boneDensityTotal,
                rmrCalories: parsed.rmrCalories,
                vatVolumeIn3: parsed.vatVolumeIn3,
                agRatio: parsed.agRatio
            )
            try saveDEXAScan(&scan)

            if let scanId = scan.id, !parsed.regions.isEmpty {
                let regions = parsed.regions.map { r in
                    DEXARegion(
                        scanId: scanId,
                        region: r.name,
                        fatPct: r.fatPct,
                        totalMassLbs: r.totalMassLbs,
                        fatMassLbs: r.fatMassLbs,
                        leanMassLbs: r.leanMassLbs,
                        bmcLbs: r.bmcLbs
                    )
                }
                try saveDEXARegions(regions, forScanId: scanId)
            }
            count += 1
        }
        Log.bodyComp.info("Imported \(count) DEXA scans")
        return count
    }
}



public extension AppDatabase {
    func saveLabReport(_ report: inout LabReport) throws {
        try writer.write { [report] db in
            var mutable = report
            try mutable.insert(db)
        }
        report = try reader.read { db in
            try LabReport.order(Column("id").desc).fetchOne(db)
        } ?? report
    }

    func fetchLabReports() throws -> [LabReport] {
        try reader.read { db in
            try LabReport.order(Column("report_date").desc).fetchAll(db)
        }
    }

    func deleteLabReport(id: Int64) throws {
        try writer.write { db in
            // biomarker_results cascade-delete via foreign key
            _ = try LabReport.deleteOne(db, id: id)
        }
    }

    func saveBiomarkerResults(_ results: [BiomarkerResult]) throws {
        try writer.write { db in
            for var result in results {
                try result.insert(db)
            }
        }
    }

    func fetchBiomarkerResults(forReportId reportId: Int64) throws -> [BiomarkerResult] {
        try reader.read { db in
            try BiomarkerResult
                .filter(Column("report_id") == reportId)
                .order(Column("biomarker_id"))
                .fetchAll(db)
        }
    }

    func fetchBiomarkerResults(forBiomarkerId biomarkerId: String) throws -> [BiomarkerResult] {
        try reader.read { db in
            try BiomarkerResult
                .filter(Column("biomarker_id") == biomarkerId)
                .order(sql: """
                    (SELECT report_date FROM lab_report WHERE lab_report.id = biomarker_result.report_id) ASC
                """)
                .fetchAll(db)
        }
    }

    /// Fetch the latest result for each biomarker across all reports.
    func fetchLatestBiomarkerResults() throws -> [BiomarkerResult] {
        try reader.read { db in
            try BiomarkerResult.fetchAll(db, sql: """
                SELECT br.* FROM biomarker_result br
                INNER JOIN (
                    SELECT biomarker_id, MAX(lr.report_date) as max_date
                    FROM biomarker_result br2
                    INNER JOIN lab_report lr ON lr.id = br2.report_id
                    GROUP BY biomarker_id
                ) latest ON br.biomarker_id = latest.biomarker_id
                INNER JOIN lab_report lr2 ON lr2.id = br.report_id AND lr2.report_date = latest.max_date
                ORDER BY br.biomarker_id
            """)
        }
    }

    /// Fetch the report date for a given report ID.
    func fetchReportDate(forId reportId: Int64) throws -> String? {
        try reader.read { db in
            try String.fetchOne(db, sql: "SELECT report_date FROM lab_report WHERE id = ?", arguments: [reportId])
        }
    }
}


