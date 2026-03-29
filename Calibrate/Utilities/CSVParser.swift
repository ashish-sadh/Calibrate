import Foundation

/// Simple CSV parser for importing Lingo CGM data.
enum CSVParser {
    struct ParseResult: Sendable {
        let headers: [String]
        let rows: [[String: String]]
    }

    /// Parse a CSV file at the given URL.
    static func parse(url: URL) throws -> ParseResult {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parse(content: content)
    }

    /// Parse CSV content string.
    static func parse(content: String) -> ParseResult {
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let headerLine = lines.first else {
            return ParseResult(headers: [], rows: [])
        }

        let headers = parseLine(headerLine)
        var rows: [[String: String]] = []

        for line in lines.dropFirst() {
            let values = parseLine(line)
            var row: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                if index < values.count {
                    row[header.trimmingCharacters(in: .whitespaces)] = values[index].trimmingCharacters(in: .whitespaces)
                }
            }
            rows.append(row)
        }

        return ParseResult(headers: headers, rows: rows)
    }

    private static func parseLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }
}
