import Foundation
import Testing
@testable import ChallengeCore

private let backupDate = Date(timeIntervalSince1970: 1_791_460_800)

@Test func backupRoundTripMergeQueueUndoAndRecovery() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let owner = UUID(), aDir = root.appendingPathComponent("a"), bDir = root.appendingPathComponent("b")
    var a = try ChallengeStore(ownerID: owner, directory: aDir)
    var b = try ChallengeStore(ownerID: owner, directory: bDir)
    try a.start(on: backupDate)
    let record = try #require(a.record)
    try b.merge(record: record, events: [])
    try a.record(.pour(450), on: backupDate, at: backupDate)
    try a.record(.undoLatestPour, on: backupDate, at: backupDate.addingTimeInterval(1))
    try a.record(.pour(4000), on: backupDate, at: backupDate.addingTimeInterval(2))
    for habit in Challenge.Habit.allCases {
        try a.record(.setHabit(habit, completed: true), on: backupDate, at: backupDate.addingTimeInterval(3))
    }
    try a.record(.setDiet(.clean), on: backupDate, at: backupDate.addingTimeInterval(4))
    let data = try a.exportData()
    #expect(try ChallengeBackup.decode(data).encoded() == data)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(json.keys) == ["formatVersion", "settings", "activities"])
    let before = try Data(contentsOf: bDir.appendingPathComponent("challenge-\(owner.uuidString.lowercased()).json"))
    #expect(try b.previewImport(data).newCount == 7)
    let recovery = try b.importData(data)
    #expect(try Data(contentsOf: recovery) == before)
    #expect(b.pending.count == 7)
    #expect(b.challenge?.summary(on: backupDate, asOf: backupDate).waterMillilitres == 4000)
    #expect(b.challenge?.streaks(asOf: backupDate).current == 1)
    #expect(b.challenge?.streaks(asOf: backupDate).best == 1)
    #expect(try b.previewImport(data).duplicateCount == 7)
    try b.importData(data)
    #expect(b.pending.count == 7)
    var reopened = try ChallengeStore(ownerID: owner, directory: bDir)
    #expect(reopened.challenge?.allActivities == a.challenge?.allActivities)
    let ack = reopened.pending.map {
        ChallengeEvent(ownerID: owner, challengeID: record.id, activity: $0.activity, receivedAt: backupDate.ISO8601Format())
    }
    try reopened.merge(record: record, events: ack)
    try reopened.importData(data)
    #expect(reopened.pendingCount == 0) // duplicates must not requeue acknowledged events
    if let output = ProcessInfo.processInfo.environment["DAILY_CHALLENGE_BACKUP_EVIDENCE_DIR"] {
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("personal-data-export.json"))
        try Data(contentsOf: recovery).write(to: directory.appendingPathComponent("pre-import-recovery.json"))
        let persisted = bDir.appendingPathComponent("challenge-\(owner.uuidString.lowercased()).json")
        try Data(contentsOf: persisted).write(to: directory.appendingPathComponent("after-import-and-sync.json"))
    }
}

@Test func backupValidationRejectsWithoutChangingDisk() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let owner = UUID()
    var store = try ChallengeStore(ownerID: owner, directory: dir)
    try store.start(on: backupDate)
    try store.record(.pour(450), on: backupDate, at: backupDate)
    let record = try #require(store.record), challenge = try #require(store.challenge)
    let event = try #require(challenge.allActivities.first)
    func export(_ settings: ChallengeRecord, _ events: [Challenge.Activity]) throws -> Data {
        try ChallengeBackup(settings: settings, activities: events).encoded()
    }
    func altered(_ action: Challenge.Action, target: UUID? = nil, device: String? = "fixture", day: Date? = nil) -> Challenge.Activity {
        .init(id: event.id, day: day ?? event.day, recordedAt: event.recordedAt,
              action: action, undonePourID: target, deviceID: device)
    }
    let bad: [Data] = try [
        Data("not json".utf8), Data("{\"formatVersion\":999}".utf8), Data("{\"formatVersion\":1}".utf8),
        export(.init(id: record.id, ownerID: UUID(), startDate: record.startDate), [event]),
        export(.init(ownerID: owner, startDate: record.startDate), [event]),
        export(.init(id: record.id, ownerID: owner, startDate: record.startDate.addingTimeInterval(-86400)), [event]),
        export(record, [event, event]), export(record, [altered(.pour(0))]),
        export(record, [altered(.pour(500))]),
        export(record, [altered(.undoLatestPour, target: UUID())]),
        export(record, [altered(.pour(450), device: nil)]),
        export(record, [altered(.pour(450), day: record.startDate.addingTimeInterval(-86400))])
    ]
    let file = dir.appendingPathComponent("challenge-\(owner.uuidString.lowercased()).json")
    let before = try Data(contentsOf: file)
    for data in bad {
        #expect(throws: (any Error).self) { try store.importData(data) }
        #expect(try Data(contentsOf: file) == before)
        #expect(store.challenge?.allActivities == challenge.allActivities)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 1)
    // An unavailable source file makes the exclusive recovery copy fail. No
    // import commit may recreate it or mutate in-memory history afterwards.
    let valid = try export(record, [])
    try FileManager.default.removeItem(at: file)
    #expect(throws: (any Error).self) { try store.importData(valid) }
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(store.challenge?.allActivities == challenge.allActivities)
}

@Test(arguments: ["", "\u{0}", "a\u{0}b", String(repeating: "a", count: 128), String(repeating: "a", count: 129),
                  String(repeating: "é", count: 128), String(repeating: "e\u{301}", count: 65)])
func backupDeviceIDStorageLimits(deviceID: String) throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    var store = try ChallengeStore(ownerID: UUID(), directory: dir)
    try store.start(on: backupDate)
    let record = try #require(store.record)
    let event = Challenge.Activity(id: UUID(), day: record.startDate, recordedAt: backupDate,
                                   action: .pour(450), undonePourID: nil, deviceID: deviceID)
    let data = try ChallengeBackup(settings: record, activities: [event]).encoded()
    if deviceID == String(repeating: "a", count: 128) || deviceID == String(repeating: "é", count: 128) {
        #expect(try store.previewImport(data).newCount == 1)
        try store.importData(data)
        #expect(store.pending.map(\.activity) == [event])
    } else {
        let file = dir.appendingPathComponent("challenge-\(record.ownerID.uuidString.lowercased()).json")
        let before = try Data(contentsOf: file)
        let pendingCount = store.pendingCount
        #expect(throws: ChallengeBackupError.self) { try store.previewImport(data) }
        #expect(throws: ChallengeBackupError.self) { try store.importData(data) }
        #expect(try Data(contentsOf: file) == before)
        #expect(store.challenge?.allActivities.isEmpty == true)
        #expect(store.pendingCount == pendingCount)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 1)
    }
}

@Test func importedCorrectionsRecalculateMilestones() throws {
    let owner = UUID()
    var challenge = Challenge(ownerID: owner, startDate: backupDate)
    for day in 0..<75 {
        let date = backupDate.addingTimeInterval(Double(day) * 86400)
        try challenge.record(.pour(4000), on: date, at: date, deviceID: "fixture")
        for habit in Challenge.Habit.allCases {
            try challenge.record(.setHabit(habit, completed: true), on: date, at: date, deviceID: "fixture")
        }
        try challenge.record(.setDiet(.clean), on: date, at: date, deviceID: "fixture")
    }
    let now = backupDate.addingTimeInterval(74 * 86400)
    #expect(challenge.streaks(asOf: now).milestones.count == 1)
    let record = ChallengeRecord(ownerID: owner, startDate: challenge.startDate)
    var corrected = challenge
    try corrected.record(.setDiet(.missed), on: backupDate, at: now, deviceID: "fixture")
    let plan = try ChallengeBackup(settings: record, activities: corrected.allActivities).plan(for: record, challenge: challenge)
    #expect(plan.merged.streaks(asOf: now).milestones.isEmpty)
    #expect(plan.merged.streaks(asOf: now).best == 74)
}
