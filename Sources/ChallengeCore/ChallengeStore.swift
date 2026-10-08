import Foundation

public enum ChallengeStoreError: LocalizedError {
    case notStarted, alreadyStarted, wrongOwner, unsupportedVersion
    public var errorDescription: String? {
        switch self {
        case .notStarted: "Select a challenge start date first."
        case .alreadyStarted: "This account already has a challenge. Existing history was not replaced."
        case .wrongOwner: "The saved challenge belongs to another account. It has not been reset."
        case .unsupportedVersion: "The saved challenge uses an unsupported format. It has not been reset."
        }
    }
}

/// One serialized writer per account. History and its outbound queue commit in
/// one atomic file, including acknowledgments. No network is needed to record.
public struct ChallengeStore {
    private struct Snapshot: Codable {
        var version: Int
        var challenge: Challenge
        var record: ChallengeRecord?
        var deviceID: String?
        var pendingIDs: Set<UUID>?
        var headerPending: Bool?
        var clockWarning: Bool?
    }
    private var snapshot: Snapshot?
    public var challenge: Challenge? { snapshot?.challenge }
    public var record: ChallengeRecord? { snapshot?.record }
    public var hasClockWarning: Bool { snapshot?.clockWarning ?? false }
    public var pendingCount: Int { pending.count + ((snapshot?.headerPending ?? false) ? 1 : 0) }
    public var pending: [ChallengeEvent] {
        guard let snapshot, let record = snapshot.record else { return [] }
        return snapshot.challenge.allActivities.filter { snapshot.pendingIDs!.contains($0.id) }
            .map { ChallengeEvent(ownerID: ownerID, challengeID: record.id, activity: $0) }
    }
    private let ownerID: UUID
    private let fileURL: URL

    public init(ownerID: UUID, directory: URL) throws {
        self.ownerID = ownerID
        fileURL = directory.appendingPathComponent("challenge-\(ownerID.uuidString.lowercased()).json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let data = try Data(contentsOf: fileURL)
        var saved = try JSONDecoder().decode(Snapshot.self, from: data)
        guard saved.version == 1 || saved.version == 2 else { throw ChallengeStoreError.unsupportedVersion }
        guard saved.challenge.ownerID == ownerID else { throw ChallengeStoreError.wrongOwner }
        if saved.version == 1 {
            // Validate before backing up. Never mutate/reset a corrupt file. The
            // exclusive copy preserves the exact original bytes before migration.
            try recoveryBackup()
            var migrated = Challenge(ownerID: ownerID, startDate: saved.challenge.startDate,
                                     timeZone: saved.challenge.timeZone)
            // Legacy records had only local append order. Stable migration tie
            // metadata preserves that order without changing IDs or timestamps.
            try migrated.merge(saved.challenge.allActivities.enumerated().map { index, a in
                Challenge.Activity(id: a.id, day: a.day, recordedAt: a.recordedAt, action: a.action,
                                   undonePourID: a.undonePourID, deviceID: String(format: "legacy-%020d", index))
            })
            saved = Snapshot(version: 2, challenge: migrated,
                             record: ChallengeRecord(ownerID: ownerID, startDate: migrated.startDate,
                                                     timeZone: migrated.timeZone),
                             deviceID: UUID().uuidString, pendingIDs: Set(migrated.allActivities.map(\.id)),
                             headerPending: true, clockWarning: false)
            try commit(saved)
        } else {
            // A version-2 snapshot written before per-challenge timezones decodes
            // both its challenge and record as Jersey. The zone is an additive
            // field, so it is written on the next commit without a migration backup.
            guard let record = saved.record, record.ownerID == ownerID,
                  record.startDate == saved.challenge.startDate,
                  record.timeZone == saved.challenge.timeZone.identifier,
                  saved.deviceID?.isEmpty == false, let pending = saved.pendingIDs,
                  pending.isSubset(of: Set(saved.challenge.allActivities.map(\.id))),
                  saved.headerPending != nil, saved.clockWarning != nil,
                  saved.challenge.allActivities.allSatisfy({ $0.deviceID?.isEmpty == false }) else {
                throw ChallengeSyncError.invalidRecord
            }
            snapshot = saved
        }
    }

    public mutating func start(on date: Date, timeZone: TimeZone) throws {
        guard challenge == nil else { throw ChallengeStoreError.alreadyStarted }
        guard Challenge.canonicalTimeZone(timeZone.identifier) != nil else { throw ChallengeSyncError.invalidRecord }
        let challenge = Challenge(ownerID: ownerID, startDate: date, timeZone: timeZone)
        try commit(Snapshot(version: 2, challenge: challenge,
                            record: ChallengeRecord(ownerID: ownerID, startDate: challenge.startDate,
                                                    timeZone: challenge.timeZone),
                            deviceID: UUID().uuidString, pendingIDs: [], headerPending: true, clockWarning: false))
    }

    @discardableResult
    public mutating func record(
        _ action: Challenge.Action, on date: Date, at now: Date, id: UUID? = nil
    ) throws -> UUID? {
        guard var next = snapshot else { throw ChallengeStoreError.notStarted }
        // Ordered IDs preserve explicit local order when the clock has identical
        // resolution for consecutive edits. Distributed ordering still uses only
        // (timestamp, device ID, event ID); explicit retry IDs are never changed.
        let eventID = id ?? nextID(at: now, snapshot: next)
        let result = try next.challenge.record(action, on: date, at: now, id: eventID, deviceID: next.deviceID)
        if let result {
            if !snapshot!.challenge.allActivities.contains(where: { $0.id == result }) {
                next.pendingIDs!.insert(result)
            }
            try commit(next)
        }
        return result
    }

    public mutating func merge(record remote: ChallengeRecord, events: [ChallengeEvent]) throws {
        guard remote.ownerID == ownerID else { throw ChallengeSyncError.wrongOwner }
        guard let adopted = remote.emptyChallenge else { throw ChallengeSyncError.invalidRecord }
        if let record, record != remote { throw ChallengeSyncError.conflictingChallenge }
        var next = snapshot ?? Snapshot(version: 2, challenge: adopted,
                                        record: remote, deviceID: UUID().uuidString, pendingIDs: [],
                                        headerPending: false, clockWarning: false)
        for event in events {
            guard event.ownerID == ownerID else { throw ChallengeSyncError.wrongOwner }
            guard event.challengeID == remote.id, event.id == event.activity.id,
                  event.activity.deviceID?.isEmpty == false, event.receiptDate != nil else {
                throw ChallengeSyncError.invalidRecord
            }
        }
        try next.challenge.merge(events.map(\.activity))
        for event in events { next.pendingIDs!.remove(event.id) }
        next.headerPending = false
        next.clockWarning = next.clockWarning! || events.contains(where: \.hasClockWarning)
        try commit(next)
    }

    public func exportData() throws -> Data {
        guard let record, let challenge else { throw ChallengeStoreError.notStarted }
        return try ChallengeBackup(settings: record, activities: challenge.allActivities).encoded()
    }

    public func previewImport(_ data: Data) throws -> ChallengeBackup.Plan {
        guard let record, let challenge else { throw ChallengeStoreError.notStarted }
        return try ChallengeBackup.decode(data).plan(for: record, challenge: challenge)
    }

    /// Revalidate at confirmation time: sync or account state may have changed
    /// since preview. Import never acknowledges events or replaces device state.
    @discardableResult
    public mutating func importData(_ data: Data) throws -> URL {
        let plan = try previewImport(data)
        guard var next = snapshot else { throw ChallengeStoreError.notStarted }
        next.challenge = plan.merged
        next.pendingIDs!.formUnion(plan.newIDs)
        let backup = try recoveryBackup()
        try commit(next)
        return backup
    }

    @discardableResult
    private func recoveryBackup() throws -> URL {
        let stamp = Date().ISO8601Format().replacingOccurrences(of: ":", with: "-")
        let backup = fileURL.deletingLastPathComponent().appendingPathComponent(
            "\(fileURL.lastPathComponent).backup-\(stamp)-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: fileURL, to: backup)
        return backup
    }

    private func nextID(at date: Date, snapshot: Snapshot) -> UUID {
        let last = snapshot.challenge.allActivities.filter { $0.recordedAt == date && $0.deviceID == snapshot.deviceID }
            .map(\.id).max { $0.uuidString < $1.uuidString }
        guard let last else { return UUID() }
        var bytes = withUnsafeBytes(of: last.uuid) { Array($0) }
        for index in bytes.indices.reversed() {
            if bytes[index] < 255 { bytes[index] += 1; break }
            bytes[index] = 0
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private mutating func commit(_ next: Snapshot) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(next).write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        snapshot = next
    }
}
