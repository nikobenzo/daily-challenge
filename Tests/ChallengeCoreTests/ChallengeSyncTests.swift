import Foundation
import Testing
@testable import ChallengeCore

private let syncDate = Date(timeIntervalSince1970: 1_791_460_800)
private func fixtureDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
private func confirmed(_ events: [ChallengeEvent], at date: Date = syncDate) -> [ChallengeEvent] {
    events.map { ChallengeEvent(ownerID: $0.ownerID, challengeID: $0.challengeID, activity: $0.activity, receivedAt: date.ISO8601Format()) }
}

@Test func twoOfflineDevicesMergeAdditionsAndDuplicateUndoWithoutResurrection() throws {
    let aDir = fixtureDirectory(), bDir = fixtureDirectory(), owner = UUID()
    defer { try? FileManager.default.removeItem(at: aDir); try? FileManager.default.removeItem(at: bDir) }
    var a = try ChallengeStore(ownerID: owner, directory: aDir)
    var b = try ChallengeStore(ownerID: owner, directory: bDir)
    try a.start(on: syncDate)
    try a.record(.pour(450), on: syncDate, at: syncDate)
    try a.record(.pour(450), on: syncDate, at: syncDate.addingTimeInterval(1))
    let header = try #require(a.record)
    let initial = confirmed(a.pending)
    try a.merge(record: header, events: initial)
    try b.merge(record: header, events: initial)
    try a.record(.undoLatestPour, on: syncDate, at: syncDate.addingTimeInterval(2))
    try b.record(.undoLatestPour, on: syncDate, at: syncDate.addingTimeInterval(3))
    try a.record(.pour(200), on: syncDate, at: syncDate.addingTimeInterval(4))
    try b.record(.pour(300), on: syncDate, at: syncDate.addingTimeInterval(5))
    let union = confirmed(a.pending + b.pending)
    try a.merge(record: header, events: union.reversed())
    try b.merge(record: header, events: union + initial + union)
    #expect(a.challenge?.allActivities == b.challenge?.allActivities)
    #expect(a.challenge?.summary(on: syncDate, asOf: syncDate).waterMillilitres == 950)
    #expect(a.pendingCount == 0 && b.pendingCount == 0)
    try a.merge(record: header, events: initial) // a stale snapshot cannot resurrect the undone pour
    let reopened = try ChallengeStore(ownerID: owner, directory: aDir)
    #expect(reopened.challenge?.allActivities == b.challenge?.allActivities)
    #expect(reopened.challenge?.streaks(asOf: syncDate).current == b.challenge?.streaks(asOf: syncDate).current)
}

@Test func conflictingHabitEditsUseTimestampDeviceThenEventIDIncludingSkew() throws {
    let owner = UUID()
    let day = Challenge(ownerID: owner, startDate: syncDate).startDate
    let firstID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let lastID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    func edit(_ id: UUID, device: String, time: Date, action: Challenge.Action) -> Challenge.Activity {
        .init(id: id, day: day, recordedAt: time, action: action, undonePourID: nil, deviceID: device)
    }
    let older = edit(UUID(), device: "Z", time: syncDate, action: .setHabit(.walk, completed: false))
    let skewed = edit(UUID(), device: "A", time: syncDate.addingTimeInterval(86400), action: .setHabit(.walk, completed: true))
    let deviceA = edit(UUID(), device: "A", time: syncDate, action: .setDiet(.missed))
    let deviceB = edit(firstID, device: "B", time: syncDate, action: .setDiet(.pending))
    let final = edit(lastID, device: "B", time: syncDate, action: .setDiet(.clean))
    let events = [older, skewed, deviceA, deviceB, final]
    var a = Challenge(ownerID: owner, startDate: syncDate)
    var b = a
    try a.merge(events)
    try b.merge(events.reversed())
    #expect(a.allActivities == b.allActivities)
    #expect(a.summary(on: syncDate, asOf: syncDate).completedHabits.contains(.walk))
    #expect(a.summary(on: syncDate, asOf: syncDate).diet == .clean)
}

@Test func clockWarningOnlyFlagsAnEntryRecordedAheadOfItsReceipt() {
    let activity = Challenge.Activity(id: UUID(), day: syncDate, recordedAt: syncDate,
                                      action: .pour(450), undonePourID: nil, deviceID: "fixture")
    // Positive deltas are late delivery (received after recording), however late.
    for delta in [-301.0, -300, 0, 300, 301, 86_400] {
        let event = ChallengeEvent(ownerID: UUID(), challengeID: UUID(), activity: activity,
                                   receivedAt: syncDate.addingTimeInterval(delta).ISO8601Format())
        #expect(event.hasClockWarning == (delta < -300), "receipt offset \(delta)")
    }
}

@Test func clockWarningClearsOnTheNextCleanMergeAndIgnoresRefetchedHistory() throws {
    let directory = fixtureDirectory(), owner = UUID()
    defer { try? FileManager.default.removeItem(at: directory) }
    var store = try ChallengeStore(ownerID: owner, directory: directory)
    try store.start(on: syncDate)
    try store.record(.pour(450), on: syncDate, at: syncDate)
    let header = try #require(store.record)
    let ahead = confirmed(store.pending, at: syncDate.addingTimeInterval(-301))
    try store.merge(record: header, events: ahead)
    #expect(store.hasClockWarning)
    #expect(try ChallengeStore(ownerID: owner, directory: directory).hasClockWarning)
    // The next sync refetches the flagged entry with a late-delivered new one.
    try store.record(.pour(450), on: syncDate, at: syncDate.addingTimeInterval(60))
    let late = confirmed(store.pending, at: syncDate.addingTimeInterval(3600))
    try store.merge(record: header, events: ahead + late)
    #expect(!store.hasClockWarning)
    try store.merge(record: header, events: ahead + late)
    #expect(!store.hasClockWarning)
    #expect(try !ChallengeStore(ownerID: owner, directory: directory).hasClockWarning)
}

@Test func aStickyWarningFromAnOlderFileClearsOnTheFirstCleanMerge() throws {
    let directory = fixtureDirectory(), owner = UUID()
    defer { try? FileManager.default.removeItem(at: directory) }
    var store = try ChallengeStore(ownerID: owner, directory: directory)
    try store.start(on: syncDate)
    try store.record(.pour(900), on: syncDate, at: syncDate)
    let header = try #require(store.record)
    let late = confirmed(store.pending, at: syncDate.addingTimeInterval(3600))
    try store.merge(record: header, events: late)
    // Older builds OR'd every delayed entry into a flag that never cleared.
    let file = directory.appendingPathComponent("challenge-\(owner.uuidString.lowercased()).json")
    var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    json["clockWarning"] = true
    try JSONSerialization.data(withJSONObject: json).write(to: file)
    var reopened = try ChallengeStore(ownerID: owner, directory: directory)
    #expect(reopened.hasClockWarning)
    try reopened.merge(record: header, events: late)
    #expect(!reopened.hasClockWarning)
    #expect(try !ChallengeStore(ownerID: owner, directory: directory).hasClockWarning)
}

@Test func migrationBacksUpExactLegacyBytesAndRetainsTheRealWorld900mlScenario() throws {
    struct Legacy: Encodable { let version = 1; let challenge: Challenge }
    let directory = fixtureDirectory(), owner = UUID()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var legacy = Challenge(ownerID: owner, startDate: syncDate)
    try legacy.record(.pour(450), on: syncDate, at: syncDate)
    try legacy.record(.pour(450), on: syncDate, at: syncDate)
    try legacy.record(.setHabit(.walk, completed: true), on: syncDate, at: syncDate)
    try legacy.record(.setHabit(.walk, completed: false), on: syncDate, at: syncDate)
    let file = directory.appendingPathComponent("challenge-\(owner.uuidString.lowercased()).json")
    let original = try JSONEncoder().encode(Legacy(challenge: legacy))
    try original.write(to: file)
    let migrated = try ChallengeStore(ownerID: owner, directory: directory)
    #expect(migrated.challenge?.startDate == legacy.startDate)
    #expect(migrated.challenge?.summary(on: syncDate, asOf: syncDate).waterMillilitres == 900)
    #expect(migrated.challenge?.summary(on: syncDate, asOf: syncDate).completedHabits.isEmpty == true)
    #expect(migrated.challenge?.allActivities.map(\.id) == legacy.allActivities.map(\.id))
    #expect(migrated.pendingCount == 5)
    let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent != file.lastPathComponent }
    #expect(backups.count == 1)
    #expect(try Data(contentsOf: #require(backups.first)) == original)
    let reopened = try ChallengeStore(ownerID: owner, directory: directory)
    #expect(reopened.record == migrated.record)
    #expect(reopened.pending.map(\.id) == migrated.pending.map(\.id))
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)
}

@Test func acknowledgmentRequiresMatchingImmutableContentsAndOwner() throws {
    let directory = fixtureDirectory(), owner = UUID()
    defer { try? FileManager.default.removeItem(at: directory) }
    var store = try ChallengeStore(ownerID: owner, directory: directory)
    try store.start(on: syncDate)
    let id = UUID()
    try store.record(.pour(450), on: syncDate, at: syncDate, id: id)
    try store.record(.pour(450), on: syncDate, at: syncDate, id: id)
    let header = try #require(store.record), event = try #require(store.pending.first)
    let conflicting = Challenge.Activity(id: id, day: event.activity.day, recordedAt: syncDate,
                                        action: .pour(900), undonePourID: nil, deviceID: event.activity.deviceID)
    #expect(throws: (any Error).self) {
        try store.merge(record: header, events: confirmed([ChallengeEvent(ownerID: owner, challengeID: header.id, activity: conflicting)]))
    }
    #expect(throws: (any Error).self) {
        try store.merge(record: header, events: confirmed([ChallengeEvent(ownerID: UUID(), challengeID: header.id, activity: event.activity)]))
    }
    #expect(store.pendingCount == 2)
    let reopened = try ChallengeStore(ownerID: owner, directory: directory)
    #expect(reopened.pendingCount == 2)
    try store.merge(record: header, events: confirmed([event]))
    #expect(store.pendingCount == 0)
}

@Test func differingChallengesNeverReplaceLocalHistory() throws {
    let directory = fixtureDirectory(), owner = UUID()
    defer { try? FileManager.default.removeItem(at: directory) }
    var store = try ChallengeStore(ownerID: owner, directory: directory)
    try store.start(on: syncDate)
    try store.record(.pour(900), on: syncDate, at: syncDate)
    let original = store.record
    #expect(throws: (any Error).self) {
        try store.merge(record: ChallengeRecord(ownerID: owner, startDate: syncDate), events: [])
    }
    #expect(store.record == original)
    #expect(store.challenge?.summary(on: syncDate, asOf: syncDate).waterMillilitres == 900)
    #expect(try ChallengeStore(ownerID: owner, directory: directory).record == original)
}
