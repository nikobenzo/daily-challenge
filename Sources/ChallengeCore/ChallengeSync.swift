import Foundation

public enum ChallengeSyncError: LocalizedError {
    case conflictingChallenge, invalidRecord, wrongOwner
    public var errorDescription: String? {
        switch self {
        case .conflictingChallenge: "Different challenges were found for this account. Sync stopped; both histories are preserved."
        case .invalidRecord: "A challenge sync record is invalid or conflicts with saved history. Nothing was replaced."
        case .wrongOwner: "The sync session or record belongs to another account. Nothing was merged."
        }
    }
}

/// Immutable account challenge settings. Appearance remains device-local.
public struct ChallengeRecord: Codable, Equatable, Sendable {
    public let id: UUID
    public let ownerID: UUID
    public let startTime: Double
    public var startDate: Date { Date(timeIntervalSince1970: startTime) }
    public init(id: UUID = UUID(), ownerID: UUID, startDate: Date) {
        self.id = id; self.ownerID = ownerID; startTime = startDate.timeIntervalSince1970
    }
    enum CodingKeys: String, CodingKey { case id; case ownerID = "owner_id"; case startTime = "start_time" }
}

public struct ChallengeEvent: Codable, Sendable {
    public let id: UUID
    public let ownerID: UUID
    public let challengeID: UUID
    public let activity: Challenge.Activity
    public let receivedAt: String?
    public init(ownerID: UUID, challengeID: UUID, activity: Challenge.Activity, receivedAt: String? = nil) {
        id = activity.id; self.ownerID = ownerID; self.challengeID = challengeID
        self.activity = activity; self.receivedAt = receivedAt
    }
    enum CodingKeys: String, CodingKey {
        case id, activity
        case ownerID = "owner_id", challengeID = "challenge_id", receivedAt = "received_at"
    }
    var receiptDate: Date? {
        guard let receivedAt else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var receipt = parser.date(from: receivedAt)
        if receipt == nil { parser.formatOptions = [.withInternetDateTime]; receipt = parser.date(from: receivedAt) }
        return receipt
    }
    public var hasClockWarning: Bool {
        guard let receiptDate else { return false }
        return abs(receiptDate.timeIntervalSince(activity.recordedAt)) > 300
    }
}

/// Transport seam shared by the SDK adapter and deterministic offline fixtures.
@MainActor public protocol ChallengeTransport {
    func fetchChallenge(ownerID: UUID) async throws -> ChallengeRecord?
    func insertChallenge(_ record: ChallengeRecord) async throws
    func upload(_ events: [ChallengeEvent], ownerID: UUID) async throws
    func fetchEvents(ownerID: UUID, challengeID: UUID) async throws -> [ChallengeEvent]
}
