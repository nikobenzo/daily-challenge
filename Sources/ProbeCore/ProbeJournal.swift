import Foundation

public struct ProbeEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let ownerID: UUID
    public let message: String
    public let clientCreatedAt: String

    public init(id: UUID = UUID(), ownerID: UUID, message: String, date: Date = Date()) {
        self.id = id
        self.ownerID = ownerID
        self.message = message
        self.clientCreatedAt = date.ISO8601Format()
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        ownerID = try values.decode(UUID.self, forKey: .ownerID)
        message = try values.decode(String.self, forKey: .message)
        let rawDate = try values.decode(String.self, forKey: .clientCreatedAt)
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = parser.date(from: rawDate)
        if date == nil {
            parser.formatOptions = [.withInternetDateTime]
            date = parser.date(from: rawDate)
        }
        guard let date else {
            throw DecodingError.dataCorruptedError(
                forKey: .clientCreatedAt, in: values, debugDescription: "Invalid entry timestamp"
            )
        }
        // Postgres normalizes 'Z' to '+00:00'; compare canonical timestamps.
        clientCreatedAt = date.ISO8601Format()
    }

    enum CodingKeys: String, CodingKey {
        case id, message
        case ownerID = "owner_id"
        case clientCreatedAt = "client_created_at"
    }
}

public enum JournalError: LocalizedError {
    case wrongOwner, invalidSnapshot, conflictingEntry, invalidMessage

    public var errorDescription: String? {
        switch self {
        case .wrongOwner: "The local or remote data belongs to another account. Nothing was merged."
        case .invalidSnapshot: "The local queue is invalid. It has been preserved; do not delete it."
        case .conflictingEntry: "A test-entry ID has conflicting content. Nothing was overwritten."
        case .invalidMessage: "A test message must contain between 1 and 200 characters."
        }
    }
}

/// One account's durable, append-only proof history and outbound queue.
/// No credentials are stored here. All mutations reach disk before memory changes.
public struct ProbeJournal {
    private struct Snapshot: Codable {
        let version: Int
        let ownerID: UUID
        var entries: [ProbeEntry]
        var pendingIDs: Set<UUID>
    }

    private var snapshot: Snapshot
    private let fileURL: URL

    public var ownerID: UUID { snapshot.ownerID }
    public var entries: [ProbeEntry] { snapshot.entries }
    public var pending: [ProbeEntry] {
        snapshot.entries.filter { snapshot.pendingIDs.contains($0.id) }
    }
    public func isPending(_ id: UUID) -> Bool { snapshot.pendingIDs.contains(id) }

    public init(ownerID: UUID, directory: URL) throws {
        self.fileURL = directory.appendingPathComponent("\(ownerID.uuidString.lowercased()).json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let loaded = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: fileURL))
            guard loaded.ownerID == ownerID else { throw JournalError.wrongOwner }
            guard loaded.version == 1,
                  loaded.entries.allSatisfy({ $0.ownerID == ownerID }),
                  Set(loaded.entries.map(\.id)).count == loaded.entries.count,
                  loaded.pendingIDs.isSubset(of: Set(loaded.entries.map(\.id))) else {
                throw JournalError.invalidSnapshot
            }
            self.snapshot = loaded
        } else {
            self.snapshot = Snapshot(version: 1, ownerID: ownerID, entries: [], pendingIDs: [])
        }
    }

    public mutating func enqueue(_ entry: ProbeEntry) throws {
        guard entry.ownerID == ownerID else { throw JournalError.wrongOwner }
        guard (1...200).contains(entry.message.count) else { throw JournalError.invalidMessage }
        if let existing = snapshot.entries.first(where: { $0.id == entry.id }) {
            guard existing == entry else { throw JournalError.conflictingEntry }
            return
        }
        var next = snapshot
        next.entries.append(entry)
        next.pendingIDs.insert(entry.id)
        try commit(next)
    }

    /// Merge a fetched snapshot. Entries absent from the response are not deleted:
    /// partial fetches and stale responses must not drop durable local work.
    public mutating func merge(_ remote: [ProbeEntry]) throws {
        guard remote.allSatisfy({ $0.ownerID == ownerID }) else { throw JournalError.wrongOwner }
        var next = snapshot
        var known = Dictionary(uniqueKeysWithValues: next.entries.map { ($0.id, $0) })
        for entry in remote {
            if let existing = known[entry.id] {
                guard existing == entry else { throw JournalError.conflictingEntry }
            } else {
                next.entries.append(entry)
                known[entry.id] = entry
            }
            // Receiving exactly this immutable record proves it reached the server.
            next.pendingIDs.remove(entry.id)
        }
        try commit(next)
    }

    private mutating func commit(_ next: Snapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(next).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        snapshot = next
    }
}
