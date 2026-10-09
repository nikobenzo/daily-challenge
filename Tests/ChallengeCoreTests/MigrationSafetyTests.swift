import Foundation
import Testing
@testable import ChallengeCore

private struct LegacyFixture: Encodable { let version = 1; let challenge: Challenge }

@Test func failedMigrationBackupLeavesLegacyBytesUntouched() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let owner = UUID(), now = Date(timeIntervalSince1970: 1_791_460_800)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
    }
    var challenge = Challenge(ownerID: owner, startDate: now)
    try challenge.record(.pour(900), on: now, at: now)
    let file = directory.appendingPathComponent("challenge-\(owner.uuidString.lowercased()).json")
    let original = try JSONEncoder().encode(LegacyFixture(challenge: challenge))
    try original.write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    #expect(throws: (any Error).self) { _ = try ChallengeStore(ownerID: owner, directory: directory) }
    #expect(try Data(contentsOf: file) == original)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
}

@Test func failedAcknowledgmentWriteRetainsPendingAndClockWarningSurvivesSuccessfulRelaunch() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let owner = UUID(), now = Date(timeIntervalSince1970: 1_791_460_800)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
    }
    var store = try ChallengeStore(ownerID: owner, directory: directory)
    try store.start(on: now); try store.record(.pour(900), on: now, at: now)
    let header = try #require(store.record)
    let events = store.pending.map {
        ChallengeEvent(ownerID: owner, challengeID: header.id, activity: $0.activity,
                       receivedAt: now.addingTimeInterval(-301).ISO8601Format())
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    #expect(throws: (any Error).self) { try store.merge(record: header, events: events) }
    #expect(store.pendingCount == 2)
    #expect(!store.hasClockWarning)
    #expect(try ChallengeStore(ownerID: owner, directory: directory).pendingCount == 2)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    try store.merge(record: header, events: events)
    let reopened = try ChallengeStore(ownerID: owner, directory: directory)
    #expect(reopened.pendingCount == 0)
    #expect(reopened.hasClockWarning)
}

@Test func invalidReceiptAndDanglingUndoCannotAcknowledgeOrErasePendingHistory() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let owner = UUID(), now = Date(timeIntervalSince1970: 1_791_460_800)
    defer { try? FileManager.default.removeItem(at: directory) }
    var store = try ChallengeStore(ownerID: owner, directory: directory)
    try store.start(on: now); try store.record(.pour(900), on: now, at: now)
    let header = try #require(store.record), original = try #require(store.pending.first)
    #expect(throws: (any Error).self) {
        try store.merge(record: header, events: [ChallengeEvent(ownerID: owner, challengeID: header.id,
                                                              activity: original.activity, receivedAt: "invalid")])
    }
    let undo = Challenge.Activity(id: UUID(), day: original.activity.day, recordedAt: now,
                                  action: .undoLatestPour, undonePourID: UUID(), deviceID: "fixture")
    #expect(throws: (any Error).self) {
        try store.merge(record: header, events: [ChallengeEvent(ownerID: owner, challengeID: header.id,
                                                              activity: undo, receivedAt: now.ISO8601Format())])
    }
    #expect(store.pendingCount == 2)
    #expect(store.challenge?.summary(on: now, asOf: now).waterMillilitres == 900)
    #expect(try ChallengeStore(ownerID: owner, directory: directory).pendingCount == 2)
}
