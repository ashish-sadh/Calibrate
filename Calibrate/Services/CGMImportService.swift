import Foundation

/// Parses Lingo CGM CSV exports and imports glucose readings.
enum CGMImportService {
    struct ImportResult: Sendable {
        let imported: Int
        let skipped: Int
        let errors: Int
        let batchId: String
    }

    /// Import a Lingo CSV file. Returns import statistics.
    static func importLingoCSV(url: URL, database: AppDatabase) throws -> ImportResult {
        let result = try CSVParser.parse(url: url)
        let batchId = UUID().uuidString

        // Find the timestamp and glucose columns (flexible matching)
        let headers = result.headers.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let timestampIdx = headers.firstIndex { $0.contains("timestamp") || $0.contains("time") || $0.contains("date") }
        let glucoseIdx = headers.firstIndex { $0.contains("glucose") || $0.contains("mg") || $0.contains("value") }

        let timestampKey = timestampIdx.map { result.headers[$0].trimmingCharacters(in: .whitespaces) } ?? "timestamp"
        let glucoseKey = glucoseIdx.map { result.headers[$0].trimmingCharacters(in: .whitespaces) } ?? "glucose_mg_dl"

        var imported = 0
        var skipped = 0
        var errors = 0
        var readings: [GlucoseReading] = []

        for row in result.rows {
            guard let timestampStr = row[timestampKey],
                  let glucoseStr = row[glucoseKey],
                  let glucose = Double(glucoseStr) else {
                errors += 1
                continue
            }

            // Normalize timestamp to ISO 8601
            let normalizedTimestamp = normalizeTimestamp(timestampStr)
            guard !normalizedTimestamp.isEmpty else {
                errors += 1
                continue
            }

            // Skip "out of range" values
            guard glucose >= 40 && glucose <= 400 else {
                skipped += 1
                continue
            }

            readings.append(GlucoseReading(
                timestamp: normalizedTimestamp,
                glucoseMgdl: glucose,
                source: "lingo_csv",
                importBatch: batchId
            ))
        }

        // Batch insert (skip duplicates by timestamp)
        try database.saveGlucoseReadings(readings)
        imported = readings.count

        return ImportResult(
            imported: imported,
            skipped: skipped,
            errors: errors,
            batchId: batchId
        )
    }

    /// Try multiple date formats to normalize a timestamp string.
    private static func normalizeTimestamp(_ input: String) -> String {
        let formatters: [DateFormatter] = [
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "MM/dd/yyyy HH:mm:ss"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }(),
        ]

        for formatter in formatters {
            if let date = formatter.date(from: input) {
                return ISO8601DateFormatter().string(from: date)
            }
        }

        // Already ISO 8601?
        if ISO8601DateFormatter().date(from: input) != nil {
            return input
        }

        return ""
    }
}
