import Foundation
import DriftCore

/// Parses Lingo CGM CSV exports and imports glucose readings.
enum CGMImportService {
    struct ImportResult: Sendable {
        let imported: Int
        let skipped: Int
        let errors: Int
        let batchId: String
    }

    /// Import a Lingo CSV file. Returns import statistics.
    ///
    /// Supports the real Lingo export format:
    /// ```
    /// Time of Glucose Reading [T=(local time) +/- (time zone offset)], Measurement(mg/dL)
    /// 2026-02-04T20:33-08:00,101
    /// ```
    /// Also supports generic CSV with "timestamp" and "glucose" columns.
    static func importLingoCSV(url: URL, database: AppDatabase) throws -> ImportResult {
        let content = try String(contentsOf: url, encoding: .utf8)
        let batchId = UUID().uuidString

        let lines = content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard let headerLine = lines.first else {
            return ImportResult(imported: 0, skipped: 0, errors: 0, batchId: batchId)
        }

        let headerLower = headerLine.lowercased()
        let isLingoFormat = headerLower.contains("time of glucose reading") || headerLower.contains("measurement")

        var imported = 0
        var skipped = 0
        var errors = 0
        var readings: [GlucoseReading] = []

        if isLingoFormat {
            // Lingo native format: "timestamp,value" with ISO 8601 + timezone offset
            Log.glucose.info("Detected Lingo native CSV format, \(lines.count - 1) data rows")

            for line in lines.dropFirst() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }

                // Split on last comma (timestamp may not contain commas, but be safe)
                guard let lastComma = trimmed.lastIndex(of: ",") else {
                    errors += 1
                    continue
                }

                let timestampStr = String(trimmed[trimmed.startIndex..<lastComma]).trimmingCharacters(in: .whitespaces)
                let glucoseStr = String(trimmed[trimmed.index(after: lastComma)...]).trimmingCharacters(in: .whitespaces)

                guard let glucose = Double(glucoseStr) else {
                    errors += 1
                    continue
                }

                guard glucose >= 40 && glucose <= 400 else {
                    skipped += 1
                    continue
                }

                let normalized = normalizeTimestamp(timestampStr)
                guard !normalized.isEmpty else {
                    errors += 1
                    continue
                }

                readings.append(GlucoseReading(
                    timestamp: normalized,
                    glucoseMgdl: glucose,
                    source: "lingo_csv",
                    importBatch: batchId
                ))
            }
        } else {
            // Generic CSV format with headers
            let result = CSVParser.parse(content: content)
            let headers = result.headers.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            let tsIdx = headers.firstIndex { $0.contains("timestamp") || $0.contains("time") || $0.contains("date") }
            let glIdx = headers.firstIndex { $0.contains("glucose") || $0.contains("mg") || $0.contains("value") }

            let tsKey = tsIdx.map { result.headers[$0].trimmingCharacters(in: .whitespaces) } ?? "timestamp"
            let glKey = glIdx.map { result.headers[$0].trimmingCharacters(in: .whitespaces) } ?? "glucose_mg_dl"

            Log.glucose.info("Detected generic CSV format with keys: \(tsKey), \(glKey)")

            for row in result.rows {
                guard let timestampStr = row[tsKey],
                      let glucoseStr = row[glKey],
                      let glucose = Double(glucoseStr) else {
                    errors += 1
                    continue
                }

                guard glucose >= 40 && glucose <= 400 else {
                    skipped += 1
                    continue
                }

                let normalized = normalizeTimestamp(timestampStr)
                guard !normalized.isEmpty else {
                    errors += 1
                    continue
                }

                readings.append(GlucoseReading(
                    timestamp: normalized,
                    glucoseMgdl: glucose,
                    source: "lingo_csv",
                    importBatch: batchId
                ))
            }
        }

        try database.saveGlucoseReadings(readings)
        imported = readings.count

        Log.glucose.info("Import complete: \(imported) imported, \(skipped) skipped, \(errors) errors")

        return ImportResult(
            imported: imported,
            skipped: skipped,
            errors: errors,
            batchId: batchId
        )
    }

    /// Normalize various timestamp formats to ISO 8601.
    private static func normalizeTimestamp(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        // Try ISO 8601 with timezone offset (Lingo format: "2026-02-04T20:33-08:00")
        let iso8601WithTZ = ISO8601DateFormatter()
        iso8601WithTZ.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        if let date = iso8601WithTZ.date(from: trimmed) {
            return iso8601WithTZ.string(from: date)
        }

        // Try ISO 8601 without seconds but with timezone (e.g., "2026-02-04T20:33-08:00")
        // The standard formatter may not handle missing seconds, so try manually
        let noSecondsTZ = DateFormatter()
        noSecondsTZ.locale = Locale(identifier: "en_US_POSIX")
        noSecondsTZ.dateFormat = "yyyy-MM-dd'T'HH:mmxxx"
        if let date = noSecondsTZ.date(from: trimmed) {
            return ISO8601DateFormatter().string(from: date)
        }

        // Standard formatters
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ssxxx",  // ISO 8601 with TZ
            "yyyy-MM-dd'T'HH:mm:ss",      // ISO 8601 no TZ
            "yyyy-MM-dd HH:mm:ss",         // Space separated
            "MM/dd/yyyy HH:mm:ss",         // US format
        ]

        for fmt in formats {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = fmt
            if let date = f.date(from: trimmed) {
                return ISO8601DateFormatter().string(from: date)
            }
        }

        // Already valid ISO 8601?
        if ISO8601DateFormatter().date(from: trimmed) != nil {
            return trimmed
        }

        return ""
    }
}
