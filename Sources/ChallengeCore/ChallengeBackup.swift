import Foundation

public enum ChallengeBackupError: LocalizedError {
    case malformed, unsupportedVersion
    public var errorDescription: String? {
        switch self {
        case .malformed: "The file is not a valid Daily Challenge export. Nothing was imported."
        case .unsupportedVersion: "This export format version is not supported. Nothing was imported."
        }
    }
}

/// Portable personal data only: no auth state, device preferences or sync queue.
public struct ChallengeBackup: Codable, Sendable {
    public static let currentVersion = 1
    public let formatVersion: Int
    public let settings: ChallengeRecord
    public let activities: [Challenge.Activity]

    public init(settings: ChallengeRecord, activities: [Challenge.Activity]) {
        formatVersion = Self.currentVersion
        self.settings = settings
        self.activities = activities
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> Self {
        struct Version: Decodable { let formatVersion: Int }
        let decoder = JSONDecoder()
        guard let version = try? decoder.decode(Version.self, from: data) else {
            throw ChallengeBackupError.malformed
        }
        guard version.formatVersion == currentVersion else { throw ChallengeBackupError.unsupportedVersion }
        do { return try decoder.decode(Self.self, from: data) }
        catch { throw ChallengeBackupError.malformed }
    }

    public struct Plan: Sendable {
        public let newCount: Int
        public let duplicateCount: Int
        public let merged: Challenge
        let newIDs: Set<UUID>
    }

    /// Validate the entire file and the union before any disk or UI mutation.
    public func plan(for record: ChallengeRecord, challenge: Challenge) throws -> Plan {
        guard formatVersion == Self.currentVersion else { throw ChallengeBackupError.unsupportedVersion }
        guard settings.ownerID == record.ownerID, challenge.ownerID == record.ownerID else {
            throw ChallengeSyncError.wrongOwner
        }
        guard settings == record, challenge.startDate == record.startDate else {
            throw ChallengeSyncError.conflictingChallenge
        }
        guard settings.startTime.isFinite,
              Challenge(ownerID: settings.ownerID, startDate: settings.startDate).startDate == settings.startDate,
              Set(activities.map(\.id)).count == activities.count,
              activities.allSatisfy({ activity in
                  guard let deviceID = activity.deviceID else { return false }
                  return (1...128).contains(deviceID.unicodeScalars.count)
                      && !deviceID.unicodeScalars.contains(where: { $0.value == 0 })
              }) else {
            throw ChallengeBackupError.malformed
        }
        // Exports are complete histories, not arbitrary patches: dangling undo
        // targets must be rejected even if the current device has that pour.
        var standalone = Challenge(ownerID: settings.ownerID, startDate: settings.startDate)
        try standalone.merge(activities)
        var merged = challenge
        try merged.merge(activities)
        let newIDs = Set(activities.map(\.id)).subtracting(challenge.allActivities.map(\.id))
        return Plan(newCount: newIDs.count, duplicateCount: activities.count - newIDs.count,
                    merged: merged, newIDs: newIDs)
    }
}
