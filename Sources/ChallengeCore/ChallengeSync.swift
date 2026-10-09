import Foundation

public enum ChallengeSyncError: LocalizedError {
    case conflictingChallenge, invalidRecord, wrongOwner, serverNeedsTimeZoneUpdate
    public var errorDescription: String? {
        switch self {
        case .serverNeedsTimeZoneUpdate:
            "The server needs the timezone update before this challenge can sync (see docs/production-sync.md). Your entries are safe on this Mac."
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
    /// IANA identifier of the zone whose midnights bound every challenge day.
    public let timeZone: String
    public var startDate: Date { Date(timeIntervalSince1970: startTime) }
    public init(id: UUID = UUID(), ownerID: UUID, startDate: Date, timeZone: TimeZone) {
        self.id = id; self.ownerID = ownerID; startTime = startDate.timeIntervalSince1970
        self.timeZone = timeZone.identifier
    }
    enum CodingKeys: String, CodingKey {
        case id; case ownerID = "owner_id"; case startTime = "start_time"; case timeZone = "time_zone"
    }
    /// A server that has not been migrated, an older snapshot or an older export
    /// has no zone: those challenges were all Jersey days.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        ownerID = try values.decode(UUID.self, forKey: .ownerID)
        startTime = try values.decode(Double.self, forKey: .startTime)
        timeZone = try values.decodeIfPresent(String.self, forKey: .timeZone) ?? Challenge.legacyTimeZoneIdentifier
    }
    /// The challenge these settings describe, or nil for an impossible start or zone.
    public var emptyChallenge: Challenge? {
        guard startTime.isFinite, let zone = Challenge.canonicalTimeZone(timeZone) else { return nil }
        let challenge = Challenge(ownerID: ownerID, startDate: startDate, timeZone: zone)
        return challenge.startDate == startDate ? challenge : nil
    }
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
    /// True when the entry was recorded more than five minutes after the server
    /// received it, so the recording clock must be ahead of the server's. Late
    /// delivery (a sleeping or offline Mac, an unreachable server, a sync that runs
    /// a while after the edit) puts recordedAt *behind* receipt and is expected, so
    /// it is not flagged. A slow clock looks the same as late delivery from these
    /// two timestamps and cannot be detected here.
    public var hasClockWarning: Bool {
        guard let receiptDate else { return false }
        return activity.recordedAt.timeIntervalSince(receiptDate) > 300
    }
}

/// An account's fetched event history. Server rows the app could not read are
/// counted and left out rather than failing the whole fetch.
public struct RemoteEvents: Sendable {
    public var events: [ChallengeEvent]
    public var skipped: Int
    public init(events: [ChallengeEvent], skipped: Int = 0) { self.events = events; self.skipped = skipped }
}

/// Transport seam shared by the SDK adapter and deterministic offline fixtures.
@MainActor public protocol ChallengeTransport {
    func fetchChallenge(ownerID: UUID) async throws -> ChallengeRecord?
    func insertChallenge(_ record: ChallengeRecord) async throws
    func upload(_ events: [ChallengeEvent], ownerID: UUID) async throws
    func fetchEvents(ownerID: UUID, challengeID: UUID) async throws -> RemoteEvents
}
