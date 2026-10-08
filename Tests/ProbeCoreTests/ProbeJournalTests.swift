import Foundation
import Testing
@testable import ProbeCore

private func inDirectory(_ test: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try test(directory)
}

@Test func queueSurvivesRelaunchAndRetriesKeepIDs() throws {
    try inDirectory { directory in
        let owner = UUID()
        let entry = ProbeEntry(ownerID: owner, message: "Offline")
        var journal = try ProbeJournal(ownerID: owner, directory: directory)
        try journal.enqueue(entry)
        try journal.enqueue(entry)
        let reopened = try ProbeJournal(ownerID: owner, directory: directory)
        #expect(reopened.entries == [entry])
        #expect(reopened.pending == [entry])
    }
}

@Test func serverConfirmationClearsOnlyConfirmedPendingRecords() throws {
    try inDirectory { directory in
        let owner = UUID()
        let first = ProbeEntry(ownerID: owner, message: "Mac A")
        let second = ProbeEntry(ownerID: owner, message: "Mac B")
        let remote = ProbeEntry(ownerID: owner, message: "Another Mac")
        var journal = try ProbeJournal(ownerID: owner, directory: directory)
        try journal.enqueue(first)
        try journal.enqueue(second)
        try journal.merge([first, remote])
        #expect(Set(journal.entries.map(\.id)) == Set([first.id, second.id, remote.id]))
        #expect(journal.pending == [second])
        let reopened = try ProbeJournal(ownerID: owner, directory: directory)
        #expect(reopened.pending == [second])
        try journal.merge([first, remote])
        #expect(journal.entries.count == 3)
    }
}

@Test func accountCachesAreIsolated() throws {
    try inDirectory { directory in
        let first = UUID(), second = UUID()
        var journal = try ProbeJournal(ownerID: first, directory: directory)
        try journal.enqueue(ProbeEntry(ownerID: first, message: "Private"))
        let other = try ProbeJournal(ownerID: second, directory: directory)
        #expect(other.entries.isEmpty)
        #expect(other.pending.isEmpty)
    }
}

@Test func wrongOwnerMergeDoesNotChangeMemoryOrDisk() throws {
    try inDirectory { directory in
        let owner = UUID()
        let entry = ProbeEntry(ownerID: owner, message: "Keep this")
        var journal = try ProbeJournal(ownerID: owner, directory: directory)
        try journal.enqueue(entry)
        let wrong = ProbeEntry(ownerID: UUID(), message: "Other account")
        #expect(throws: JournalError.self) { try journal.merge([entry, wrong]) }
        #expect(journal.pending == [entry])
        #expect(try ProbeJournal(ownerID: owner, directory: directory).pending == [entry])
        #expect(throws: JournalError.self) { try journal.enqueue(wrong) }
    }
}

@Test func conflictingIDIsNotSilentlyAcknowledged() throws {
    try inDirectory { directory in
        let owner = UUID(), id = UUID(), date = Date()
        let entry = ProbeEntry(id: id, ownerID: owner, message: "Original", date: date)
        let conflict = ProbeEntry(id: id, ownerID: owner, message: "Different", date: date)
        var journal = try ProbeJournal(ownerID: owner, directory: directory)
        try journal.enqueue(entry)
        #expect(throws: JournalError.self) { try journal.merge([conflict]) }
        #expect(journal.pending == [entry])
    }
}

@Test func failedDiskWriteDoesNotEnqueueInMemory() throws {
    try inDirectory { directory in
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocked = directory.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: blocked)
        let owner = UUID()
        var journal = try ProbeJournal(ownerID: owner, directory: blocked)
        #expect(throws: (any Error).self) {
            try journal.enqueue(ProbeEntry(ownerID: owner, message: "Cannot save"))
        }
        #expect(journal.pending.isEmpty)
        #expect(journal.entries.isEmpty)
    }
}

@Test func corruptCacheIsNotOverwritten() throws {
    try inDirectory { directory in
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let owner = UUID()
        let file = directory.appendingPathComponent("\(owner.uuidString.lowercased()).json")
        let badData = Data("broken json".utf8)
        try badData.write(to: file)
        #expect(throws: (any Error).self) { try ProbeJournal(ownerID: owner, directory: directory) }
        #expect(try Data(contentsOf: file) == badData)
    }
}

@Test func postgresTimestampNormalizationDoesNotCreateConflict() throws {
    let owner = UUID(), id = UUID()
    let entry = ProbeEntry(id: id, ownerID: owner, message: "Same", date: Date(timeIntervalSince1970: 0))
    let json = """
    {"id":"\(id)","owner_id":"\(owner)","message":"Same","client_created_at":"1970-01-01T00:00:00+00:00"}
    """
    let remote = try JSONDecoder().decode(ProbeEntry.self, from: Data(json.utf8))
    #expect(remote == entry)
}

@Test func emptyMessagesAreRejected() throws {
    try inDirectory { directory in
        let owner = UUID()
        var journal = try ProbeJournal(ownerID: owner, directory: directory)
        #expect(throws: JournalError.self) {
            try journal.enqueue(ProbeEntry(ownerID: owner, message: ""))
        }
        #expect(journal.entries.isEmpty)
    }
}
