import ChallengeCore
import Foundation
import Testing

private func withStoreDirectory(_ test: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try test(directory)
}

@Test func allFiveRequirementsAndCorrectionsSurviveRelaunch() throws {
    try withStoreDirectory { directory in
        let owner = UUID()
        let now = instant("2026-10-08T12:00:00Z")
        var store = try ChallengeStore(ownerID: owner, directory: directory)
        #expect(store.challenge == nil)
        try store.start(on: now)
        try store.record(.pour(4_000), on: now, at: now)
        for habit in Challenge.Habit.allCases {
            try store.record(.setHabit(habit, completed: true), on: now, at: now)
        }
        try store.record(.setDiet(.clean), on: now, at: now)
        try store.record(.setDiet(.missed), on: now, at: now)
        try store.record(.setDiet(.clean), on: now, at: now)
        let reopened = try ChallengeStore(ownerID: owner, directory: directory)
        let challenge = try #require(reopened.challenge)
        #expect(challenge.summary(on: now, asOf: now).isComplete)
        #expect(challenge.streaks(asOf: now).current == 1)
        #expect(challenge.history(on: now).count == 7)
    }
}

@Test func duplicatedActivityInASavedFileIsRejectedRatherThanDoubleCounted() throws {
    try withStoreDirectory { directory in
        let owner = UUID()
        let now = instant("2026-10-08T12:00:00Z")
        var store = try ChallengeStore(ownerID: owner, directory: directory)
        try store.start(on: now)
        try store.record(.pour(450), on: now, at: now)
        let file = directory.appendingPathComponent("challenge-\(owner.uuidString.lowercased()).json")
        // Damage the versioned on-disk format, not the in-memory rules module.
        var envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        var saved = envelope["challenge"] as! [String: Any]
        let activities = saved["activities"] as! [[String: Any]]
        saved["activities"] = activities + activities
        envelope["challenge"] = saved
        try JSONSerialization.data(withJSONObject: envelope).write(to: file)
        #expect(throws: (any Error).self) {
            try ChallengeStore(ownerID: owner, directory: directory)
        }
        // The live store still has the last valid state; no automatic reset.
        #expect(store.challenge?.summary(on: now, asOf: now).waterMillilitres == 450)
    }
}

@Test func aFailedWritePreservesThePreviouslySavedDayAndLiveState() throws {
    try withStoreDirectory { directory in
        let owner = UUID()
        let now = instant("2026-10-08T12:00:00Z")
        var store = try ChallengeStore(ownerID: owner, directory: directory)
        try store.start(on: now)
        try store.record(.pour(450), on: now, at: now)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
        #expect(throws: (any Error).self) { try store.record(.pour(450), on: now, at: now) }
        #expect(store.challenge?.summary(on: now, asOf: now).waterMillilitres == 450)
        let reopened = try ChallengeStore(ownerID: owner, directory: directory)
        #expect(reopened.challenge?.summary(on: now, asOf: now).waterMillilitres == 450)
    }
}

@Test func localChallengeHistoryIsSeparatedByAppAccount() throws {
    try withStoreDirectory { directory in
        let firstOwner = UUID(), secondOwner = UUID()
        let now = instant("2026-10-08T12:00:00Z")
        var first = try ChallengeStore(ownerID: firstOwner, directory: directory)
        try first.start(on: now)
        try first.record(.pour(450), on: now, at: now)
        var second = try ChallengeStore(ownerID: secondOwner, directory: directory)
        #expect(second.challenge == nil)
        try second.start(on: now)
        try second.record(.pour(900), on: now, at: now)
        let reopenedFirst = try ChallengeStore(ownerID: firstOwner, directory: directory)
        let reopenedSecond = try ChallengeStore(ownerID: secondOwner, directory: directory)
        #expect(reopenedFirst.challenge?.summary(on: now, asOf: now).waterMillilitres == 450)
        #expect(reopenedSecond.challenge?.summary(on: now, asOf: now).waterMillilitres == 900)
    }
}

@Test func setupCannotReplaceAnExistingChallengeOrLogBeforeStarting() throws {
    try withStoreDirectory { directory in
        let owner = UUID()
        let now = instant("2026-10-08T12:00:00Z")
        var store = try ChallengeStore(ownerID: owner, directory: directory)
        #expect(throws: (any Error).self) { try store.record(.pour(450), on: now, at: now) }
        #expect(store.challenge == nil)
        try store.start(on: now)
        try store.record(.pour(450), on: now, at: now)
        #expect(throws: (any Error).self) {
            try store.start(on: instant("2026-10-09T12:00:00Z"))
        }
        #expect(store.challenge?.summary(on: now, asOf: now).waterMillilitres == 450)
        let reopened = try ChallengeStore(ownerID: owner, directory: directory)
        #expect(reopened.challenge?.summary(on: now, asOf: now).waterMillilitres == 450)
    }
}

@Test func unreadableSavedDataIsPreservedRatherThanReplacedWithAnEmptyChallenge() throws {
    try withStoreDirectory { directory in
        let owner = UUID()
        let now = instant("2026-10-08T12:00:00Z")
        var store = try ChallengeStore(ownerID: owner, directory: directory)
        try store.start(on: now)
        let file = directory.appendingPathComponent("challenge-\(owner.uuidString.lowercased()).json")
        try Data("broken json".utf8).write(to: file)
        #expect(throws: (any Error).self) { try ChallengeStore(ownerID: owner, directory: directory) }
        // Repeated opening must still fail, rather than silently overwriting/resetting.
        #expect(throws: (any Error).self) { try ChallengeStore(ownerID: owner, directory: directory) }
    }
}
