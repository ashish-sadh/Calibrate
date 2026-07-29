import Foundation

// MARK: - Wire models

public enum SupportKind: String, Codable, Sendable, CaseIterable {
    case bug, suggestion, question

    public var displayName: String {
        switch self {
        case .bug: "Bug"
        case .suggestion: "Suggestion"
        case .question: "Question"
        }
    }
}

public enum SupportStatus: String, Codable, Sendable {
    case open, inProgress = "in_progress", fixed, wontFix = "wont_fix", released

    /// What the REPORTER should read. Deliberately plain: "we're on it" beats
    /// "in_progress", and a fix nobody can install yet is not "fixed".
    public var displayName: String {
        switch self {
        case .open: "Received"
        case .inProgress: "We're on it"
        case .fixed: "Fixed — shipping soon"
        case .wontFix: "Not planned"
        case .released: "Released"
        }
    }
}

public struct SupportTicketDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var kind: SupportKind
    public var subject: String
    public var body: String
    public var status: SupportStatus
    public var releasedIn: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, subject, body, status
        case releasedIn = "released_in"
        case createdAt = "created_at"
    }
}

public struct SupportMessageDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let ticketId: String
    public var body: String
    public var fromStaff: Bool
    public var attachment: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, body, attachment
        case ticketId = "ticket_id"
        case fromStaff = "from_staff"
        case createdAt = "created_at"
    }
}

// MARK: - Service

/// In-app bug reports and suggestions, with a reply thread so a report is a
/// conversation rather than a void (operator ask 2026-07-28).
///
/// **No account required.** Tickets are keyed by the anonymous telemetry install
/// id, not `auth.uid()` — forcing a sign-in to report a bug would lose exactly
/// the reports worth having. When the user happens to have a sharing profile we
/// attach it so a reply can also reach them by @username.
///
/// Unlike `TelemetryService` this is NOT fire-and-forget: the user is waiting
/// and must be told whether their report was filed, so calls throw.
@MainActor
public enum SupportService {

    private static var client: SyncClient { SyncClient() }

    /// File a ticket. Returns the created row so the UI can push straight into
    /// its thread.
    @discardableResult
    public static func fileTicket(kind: SupportKind, subject: String, body: String) async throws -> SupportTicketDTO {
        var row: [String: Any] = [
            "install_id": Preferences.telemetryInstallID,
            "kind": kind.rawValue,
            "subject": String(subject.prefix(200)),
            "body": String(body.prefix(5000)),
            "platform": TelemetryService.platform,
        ]
        if let version = TelemetryService.appVersion { row["app_version"] = version }
        // Best-effort link to the sharing identity — absent for signed-out users.
        if let profileID = SharingService.shared.currentSession?.userID { row["profile_id"] = profileID }

        let created: [SupportTicketDTO] = try await client.restInsert(
            "support_tickets", body: [row], token: nil)
        guard let ticket = created.first else {
            throw SharingError.decoding("support ticket was not returned")
        }
        return ticket
    }

    /// This install's tickets, newest first. The install id is the capability —
    /// it is an unguessable UUID, so a caller without it sees nothing useful.
    public static func myTickets() async throws -> [SupportTicketDTO] {
        try await client.restGet(
            "support_tickets?install_id=eq.\(Preferences.telemetryInstallID)&select=*&order=created_at.desc&limit=100",
            token: nil)
    }

    public static func messages(ticketID: String) async throws -> [SupportMessageDTO] {
        try await client.restGet(
            "support_messages?ticket_id=eq.\(ticketID)&select=*&order=created_at.asc&limit=200",
            token: nil)
    }

    /// Follow-up from the reporter. `from_staff` is omitted deliberately — the
    /// RLS policy rejects a client row that claims to be staff.
    public static func reply(ticketID: String, body: String, attachment: String? = nil) async throws {
        var row: [String: Any] = [
            "ticket_id": ticketID,
            "install_id": Preferences.telemetryInstallID,
            "body": String(body.prefix(5000)),
            "from_staff": false,
        ]
        if let attachment { row["attachment"] = attachment }
        let _: [SupportMessageDTO] = try await client.restInsert(
            "support_messages", body: [row], token: nil)
    }

    /// Upload a screenshot to the private `support-attachments` bucket and
    /// return its storage path (what goes in `support_messages.attachment`).
    /// A screenshot is usually what makes a bug reproducible, so this is worth
    /// the extra round trip.
    public static func uploadAttachment(_ jpeg: Data, ticketID: String) async throws -> String {
        let path = "\(Preferences.telemetryInstallID)/\(ticketID)/\(UUID().uuidString).jpg"
        try await client.storageUpload(bucket: "support-attachments", path: path,
                                       data: jpeg, contentType: "image/jpeg")
        return path
    }
}
