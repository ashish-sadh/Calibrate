import Foundation

/// Parses a meal PHOTO (JPEG) into structured food items using the same cloud
/// vision model that reads workout photos (Nebius `Qwen2.5-VL` when
/// provisioned). The image sibling of `NebiusMealLogger` (text): both produce
/// the identical `PhotoLogResponse` wire shape, so they share ONE decoder —
/// a photo reply and a typed-description reply resolve through the same
/// review rows. Feeds Android's Snap capture flow (#1111).
@MainActor
public enum NebiusMealPhotoLogger {

    static let systemPrompt = """
    You read a photo of a plate of food and convert it into structured nutrition data.
    Return ONLY a JSON object — no prose, no markdown fences — in exactly this shape:
    {"items":[{"name":"string","grams":number,"calories":number,"protein_g":number,"carbs_g":number,"fat_g":number,"fiber_g":number,"serving_unit":"g|piece|slice|cup|bowl|tbsp|plate","serving_amount":number,"confidence":"high|medium|low"}],"overall_confidence":"high|medium|low","notes":null}
    Rules:
    - One entry per distinct food visible on the plate/tray — identify each dish separately, never lump a thali into one item.
    - Estimate grams + macros for the portion AS DEPICTED, not a generic serving. Indian food is the default cuisine — recognize dals, sabzis, rotis, rice, curries by appearance; assume typical home-cooked portions when the exact dish is ambiguous.
    - When a count is visually obvious ("3 idli", "2 rotis"), set serving_unit + serving_amount to that count, and grams to the TOTAL weight of every piece combined (not per-piece).
    - Never invent foods that aren't visible. If the photo shows no food at all, return {"items":[],"overall_confidence":"low","notes":null}.
    """

    /// Progress milestones surfaced to the capture UI — mirrors
    /// `NebiusWorkoutPhotoParser.ScanStage`. `.reading` fires on the first
    /// streamed token; `.retrying` fires when the automatic retry kicks in.
    public enum ScanStage: Sendable, Equatable {
        case sending
        case reading
        case retrying
    }

    /// Parse a meal photo (JPEG `imageData`) via the coach cloud vision model.
    /// `userNote` is an optional rider typed alongside the photo, forwarded as
    /// authoritative context. Returns nil when the cloud isn't configured,
    /// both attempts fail, or nothing decodes (caller shows an error+retry —
    /// there is no on-device vision fallback for photos, unlike text).
    public static func parse(imageData: Data, visionModelID: String,
                             userNote: String? = nil,
                             onStage: (@Sendable (ScanStage) -> Void)? = nil) async -> PhotoLogResponse? {
        guard !imageData.isEmpty else { return nil }
        guard CoachCloud.isConfigured else { return nil }
        CoachCloud.install()

        return await CloudExtractionPolicy.withRetry(onRetry: { onStage?(.retrying) }) {
            onStage?(.sending)
            let firstToken = FirstTokenFlag()
            let raw = await LocalAIService.shared.respondDirectWithPhoto(
                systemPrompt: systemPrompt,
                message: requestMessage(userNote: userNote),
                imageData: imageData,
                visionModelID: visionModelID,
                maxTokens: scanMaxTokens,
                timeout: scanTimeout,
                temperature: CloudExtractionPolicy.temperature,
                onToken: { _ in
                    if firstToken.markFired() { onStage?(.reading) }
                }
            )
            return decode(raw)
        }
    }

    /// Thread-safe once-flag so the streaming callback fires `.reading`
    /// exactly once per attempt (onToken arrives on a background executor).
    private final class FirstTokenFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false
        func markFired() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if fired { return false }
            fired = true
            return true
        }
    }

    /// A multi-item thali can emit well past the 512-token chat ceiling.
    public static let scanMaxTokens = 4096
    /// A plate is simpler than a handwritten workout page, but keep the same
    /// headroom as the workout scanner — vision reads are a deliberate wait.
    public static let scanTimeout: TimeInterval = 240

    /// Pure so the note plumbing is Tier-0 testable.
    nonisolated static func requestMessage(userNote: String?) -> String {
        var message = "Identify each distinct food on this plate and estimate grams + macros for the portion shown."
        if let note = userNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            message += "\nUser note about this photo: \(note)"
        }
        return message
    }

    /// Reuses `NebiusMealLogger`'s decoder — both loggers emit the identical
    /// `PhotoLogResponse` wire shape, so there is exactly one JSON→model
    /// mapping for text AND photo meal parses. Do not fork this.
    nonisolated static func decode(_ raw: String) -> PhotoLogResponse? {
        NebiusMealLogger.decode(raw)
    }
}
