import Foundation
import Testing
@testable import ChallengeCore

/// The boundary fixtures from ChallengeTests, re-run in each challenge's own zone.
/// "GMT" is how Foundation canonically spells UTC.
private let zones = ["Europe/Jersey", "America/New_York", "Australia/Sydney", "GMT"]

/// An instant from wall-clock time in a zone, so one fixture reads the same everywhere.
private func local(_ identifier: String, _ year: Int, _ month: Int, _ day: Int,
                   _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0) -> Date {
    Challenge.calendar(for: zone(identifier)).date(from: DateComponents(
        year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

private func fixtureDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

@Test(arguments: zones)
func anUnfinishedDayClosesAtTheChallengeZonesMidnight(_ identifier: String) throws {
    let start = local(identifier, 2026, 10, 8)
    let before = local(identifier, 2026, 10, 8, 23, 59, 59)
    let midnight = local(identifier, 2026, 10, 9, 0)
    var challenge = Challenge(ownerID: UUID(), startDate: start, timeZone: zone(identifier))
    try challenge.record(.pour(450), on: start, at: before)
    #expect(challenge.summary(on: start, asOf: before).status == .inProgress)
    #expect(challenge.summary(on: start, asOf: midnight).status == .missed)
    #expect(challenge.summary(on: midnight, asOf: before).status == .future)
    #expect(challenge.summary(on: midnight, asOf: midnight).status == .inProgress)
    #expect(challenge.summary(on: local(identifier, 2026, 10, 7), asOf: midnight).status == .outsideChallenge)
    #expect(challenge.streaks(asOf: before).current == 0)
}

@Test(arguments: zones)
func startDatesNormalizeToTheChallengeZonesMidnight(_ identifier: String) throws {
    for (hour, minute) in [(0, 10), (23, 30)] {
        let picked = local(identifier, 2026, 10, 8, hour, minute)
        let challenge = Challenge(ownerID: UUID(), startDate: picked, timeZone: zone(identifier))
        #expect(challenge.startDate == local(identifier, 2026, 10, 8, 0))
        var copy = challenge
        #expect(throws: (any Error).self) {
            try copy.record(.pour(450), on: local(identifier, 2026, 10, 7, 23, 59), at: picked)
        }
    }
}

/// One instant is a different challenge day depending on the zone: 13:30 UTC on
/// 8 October is already 9 October in Sydney.
@Test func theSameInstantIsTheZonesOwnCalendarDate() throws {
    let moment = instant("2026-10-08T13:30:00Z")
    var sydney = Challenge(ownerID: UUID(), startDate: moment, timeZone: zone("Australia/Sydney"))
    var jersey = Challenge(ownerID: UUID(), startDate: moment, timeZone: zone("Europe/Jersey"))
    try sydney.record(.pour(450), on: moment, at: moment)
    try jersey.record(.pour(450), on: moment, at: moment)
    #expect(sydney.allActivities[0].day == local("Australia/Sydney", 2026, 10, 9, 0))
    #expect(jersey.allActivities[0].day == local("Europe/Jersey", 2026, 10, 8, 0))
    #expect(sydney.startDate == instant("2026-10-08T13:00:00Z"))
    #expect(jersey.startDate == instant("2026-10-07T23:00:00Z"))
}

/// Both transitions per zone (23- and 25-hour days); GMT has none.
@Test(arguments: [
    ("Europe/Jersey", 2026, 3, 29, 82_800.0), ("Europe/Jersey", 2026, 10, 25, 90_000.0),
    ("America/New_York", 2026, 3, 8, 82_800.0), ("America/New_York", 2026, 11, 1, 90_000.0),
    ("Australia/Sydney", 2026, 10, 4, 82_800.0), ("Australia/Sydney", 2026, 4, 5, 90_000.0),
    ("GMT", 2026, 3, 29, 86_400.0), ("GMT", 2026, 10, 25, 86_400.0),
])
func dayIntervalsRespectTheChallengeZonesDaylightSaving(_ fixture: (String, Int, Int, Int, Double)) {
    let date = local(fixture.0, fixture.1, fixture.2, fixture.3)
    let challenge = Challenge(ownerID: UUID(), startDate: date, timeZone: zone(fixture.0))
    #expect(challenge.summary(on: date, asOf: date).interval.duration == fixture.4)
    #expect(challenge.summary(on: date, asOf: date).interval.start == local(fixture.0, fixture.1, fixture.2, fixture.3, 0))
}

@Test(arguments: [
    ("Europe/Jersey", 2026, 3, 28), ("Europe/Jersey", 2026, 10, 24),
    ("America/New_York", 2026, 3, 7), ("America/New_York", 2026, 10, 31),
    ("Australia/Sydney", 2026, 10, 3), ("Australia/Sydney", 2026, 4, 4),
    ("GMT", 2026, 3, 28), ("GMT", 2026, 10, 24),
])
func streaksCountTheZonesCalendarDaysAcrossDaylightSaving(_ fixture: (String, Int, Int, Int)) throws {
    let days = (0..<3).map { local(fixture.0, fixture.1, fixture.2, fixture.3 + $0) }
    let now = days[2]
    var challenge = Challenge(ownerID: UUID(), startDate: days[0], timeZone: zone(fixture.0))
    for day in days { try complete(&challenge, on: day, at: now) }
    #expect(challenge.streaks(asOf: now).current == 3)
    let missedMidnight = local(fixture.0, fixture.1, fixture.2, fixture.3 + 4, 0)
    #expect(challenge.streaks(asOf: missedMidnight.addingTimeInterval(-1)).current == 3)
    #expect(challenge.streaks(asOf: missedMidnight).current == 0)
    #expect(challenge.streaks(asOf: missedMidnight).best == 3)
}

@Test(arguments: zones)
func seventyFiveDayMilestonesFallOnTheZonesLocalDay(_ identifier: String) throws {
    let calendar = Challenge.calendar(for: zone(identifier))
    let start = local(identifier, 2026, 1, 1)
    let now = local(identifier, 2026, 3, 17)
    var challenge = Challenge(ownerID: UUID(), startDate: start, timeZone: zone(identifier))
    for offset in 0..<76 { try complete(&challenge, on: calendar.date(byAdding: .day, value: offset, to: start)!, at: now) }
    #expect(challenge.streaks(asOf: now).current == 76)
    #expect(challenge.streaks(asOf: now).milestones == [local(identifier, 2026, 3, 16, 0)])
}

@Test func challengeSnapshotsCarryTheirZoneAndOlderOnesDecodeAsJersey() throws {
    let start = local("America/New_York", 2026, 10, 8)
    var challenge = Challenge(ownerID: UUID(), startDate: start, timeZone: zone("America/New_York"))
    try challenge.record(.pour(450), on: start, at: start)
    let data = try JSONEncoder().encode(challenge)
    var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["timeZone"] as? String == "America/New_York")
    let decoded = try JSONDecoder().decode(Challenge.self, from: data)
    #expect(decoded.timeZone.identifier == "America/New_York")
    #expect(decoded.allActivities == challenge.allActivities)

    let legacy = Challenge(ownerID: UUID(), startDate: instant("2026-10-08T12:00:00Z"))
    var legacyJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
    legacyJSON.removeValue(forKey: "timeZone")
    let reopened = try JSONDecoder().decode(Challenge.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
    #expect(reopened.timeZone.identifier == "Europe/Jersey")
    #expect(reopened.startDate == legacy.startDate)

    for invalid in ["Mars/Olympus_Mons", "", "UTC", "europe/london"] {
        json["timeZone"] = invalid
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Challenge.self, from: JSONSerialization.data(withJSONObject: json))
        }
    }
    // A New York midnight is not a Jersey midnight: activity days must match the zone.
    json["timeZone"] = "Europe/Jersey"
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(Challenge.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

@Test func settingsRecordsWithAndWithoutTimeZoneDecode() throws {
    let owner = UUID(), id = UUID()
    let base = "\"id\":\"\(id.uuidString)\",\"owner_id\":\"\(owner.uuidString)\",\"start_time\":1791414000"
    let unmigrated = try JSONDecoder().decode(ChallengeRecord.self, from: Data("{\(base)}".utf8))
    #expect(unmigrated.timeZone == "Europe/Jersey")
    #expect(unmigrated.emptyChallenge?.timeZone.identifier == "Europe/Jersey")
    let sydney = try JSONDecoder().decode(ChallengeRecord.self, from: Data("{\(base),\"time_zone\":\"Australia/Sydney\"}".utf8))
    #expect(sydney.timeZone == "Australia/Sydney")
    #expect(sydney != unmigrated)
    // 1791414000 is a Jersey midnight, not a Sydney one: an impossible record.
    #expect(sydney.emptyChallenge == nil)
    let written = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(
        ChallengeRecord(id: id, ownerID: owner, startDate: local("Australia/Sydney", 2026, 10, 8, 0),
                        timeZone: zone("Australia/Sydney")))) as? [String: Any])
    #expect(Set(written.keys) == ["id", "owner_id", "start_time", "time_zone"])
    #expect(written["time_zone"] as? String == "Australia/Sydney")
    for invalid in ["Bogus/Zone", "", "UTC"] {
        let record = try JSONDecoder().decode(ChallengeRecord.self, from: Data("{\(base),\"time_zone\":\"\(invalid)\"}".utf8))
        #expect(record.emptyChallenge == nil)
    }
}

@Test func storeStartsInTheChosenZoneAndAdoptsTheServersZone() throws {
    let aDir = fixtureDirectory(), bDir = fixtureDirectory(), owner = UUID()
    defer { try? FileManager.default.removeItem(at: aDir); try? FileManager.default.removeItem(at: bDir) }
    let now = local("Australia/Sydney", 2026, 10, 8, 0, 30)
    var a = try ChallengeStore(ownerID: owner, directory: aDir)
    try a.start(on: now, timeZone: zone("Australia/Sydney"))
    try a.record(.pour(450), on: now, at: now)
    let record = try #require(a.record)
    #expect(record.timeZone == "Australia/Sydney")
    #expect(record.startDate == local("Australia/Sydney", 2026, 10, 8, 0))
    var b = try ChallengeStore(ownerID: owner, directory: bDir)
    let confirmed = a.pending.map {
        ChallengeEvent(ownerID: owner, challengeID: record.id, activity: $0.activity, receivedAt: now.ISO8601Format())
    }
    try b.merge(record: record, events: confirmed)
    #expect(b.challenge?.timeZone.identifier == "Australia/Sydney")
    #expect(b.challenge?.summary(on: now, asOf: now).waterMillilitres == 450)
    let reopened = try ChallengeStore(ownerID: owner, directory: bDir)
    #expect(reopened.record == record)
    #expect(reopened.challenge?.timeZone.identifier == "Australia/Sydney")

    var invalid = try ChallengeStore(ownerID: owner, directory: fixtureDirectory())
    let unknownZone = try JSONDecoder().decode(ChallengeRecord.self, from: JSONSerialization.data(withJSONObject: [
        "id": UUID().uuidString, "owner_id": owner.uuidString, "start_time": record.startTime, "time_zone": "Bogus/Zone"]))
    #expect(throws: ChallengeSyncError.invalidRecord) { try invalid.merge(record: unknownZone, events: []) }
    #expect(invalid.challenge == nil)
}

/// The existing conflict rule, now including the zone: only the zone differs
/// (Jersey and London share every midnight), so sync stops and both histories
/// stay exactly as they were.
@Test func settingsThatDifferOnlyInTimeZoneConflictWithoutReplacingHistory() throws {
    let dir = fixtureDirectory(), owner = UUID()
    defer { try? FileManager.default.removeItem(at: dir) }
    let now = instant("2026-10-08T12:00:00Z")
    var store = try ChallengeStore(ownerID: owner, directory: dir)
    try store.start(on: now, timeZone: zone("Europe/Jersey"))
    try store.record(.pour(900), on: now, at: now)
    let local = try #require(store.record)
    let remote = ChallengeRecord(id: local.id, ownerID: owner, startDate: local.startDate, timeZone: zone("Europe/London"))
    #expect(remote.startTime == local.startTime && remote.id == local.id && remote != local)
    let file = dir.appendingPathComponent("challenge-\(owner.uuidString.lowercased()).json")
    let before = try Data(contentsOf: file)
    #expect(throws: ChallengeSyncError.conflictingChallenge) { try store.merge(record: remote, events: []) }
    #expect(try Data(contentsOf: file) == before)
    #expect(store.pendingCount == 2)
    #expect(store.record == local)
}

/// A version-2 snapshot from before this change has no zone. It opens as Jersey,
/// keeps every record and pending ID, makes no migration backup, and writes the
/// zone from its next save.
@Test func versionTwoSnapshotsWithoutAZoneOpenAsJerseyWithoutABackup() throws {
    let dir = fixtureDirectory(), owner = UUID()
    defer { try? FileManager.default.removeItem(at: dir) }
    let now = instant("2026-10-08T12:00:00Z")
    var store = try ChallengeStore(ownerID: owner, directory: dir)
    try store.start(on: now)
    try store.record(.pour(450), on: now, at: now)
    try store.record(.pour(450), on: now, at: now.addingTimeInterval(1))
    let file = dir.appendingPathComponent("challenge-\(owner.uuidString.lowercased()).json")
    var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    var challenge = try #require(json["challenge"] as? [String: Any])
    var record = try #require(json["record"] as? [String: Any])
    #expect(challenge.removeValue(forKey: "timeZone") as? String == "Europe/Jersey")
    #expect(record.removeValue(forKey: "time_zone") as? String == "Europe/Jersey")
    json["challenge"] = challenge; json["record"] = record
    #expect(json["version"] as? Int == 2)
    let legacy = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    try legacy.write(to: file)

    var reopened = try ChallengeStore(ownerID: owner, directory: dir)
    #expect(reopened.challenge?.timeZone.identifier == "Europe/Jersey")
    #expect(reopened.record == store.record)
    #expect(reopened.challenge?.allActivities == store.challenge?.allActivities)
    #expect(reopened.pendingCount == 3)
    #expect(try Data(contentsOf: file) == legacy) // opening alone never rewrites
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == [file.lastPathComponent])
    try reopened.record(.pour(450), on: now, at: now.addingTimeInterval(2))
    let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    #expect((saved["challenge"] as? [String: Any])?["timeZone"] as? String == "Europe/Jersey")
    #expect((saved["record"] as? [String: Any])?["time_zone"] as? String == "Europe/Jersey")
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == [file.lastPathComponent])

    // A snapshot whose record and challenge disagree on the zone is never guessed at.
    var mismatched = saved
    var mismatchedRecord = try #require(saved["record"] as? [String: Any])
    mismatchedRecord["time_zone"] = "America/New_York"
    mismatched["record"] = mismatchedRecord
    try JSONSerialization.data(withJSONObject: mismatched).write(to: file)
    #expect(throws: ChallengeSyncError.invalidRecord) { try ChallengeStore(ownerID: owner, directory: dir) }
}

@Test func backupsCarryTheZoneAndVersionOneFilesImportAsJersey() throws {
    let root = fixtureDirectory(), owner = UUID()
    defer { try? FileManager.default.removeItem(at: root) }
    let now = local("America/New_York", 2026, 10, 8)
    var york = try ChallengeStore(ownerID: owner, directory: root.appendingPathComponent("york"))
    try york.start(on: now, timeZone: zone("America/New_York"))
    try york.record(.pour(450), on: now, at: now)
    let export = try york.exportData()
    let json = try #require(JSONSerialization.jsonObject(with: export) as? [String: Any])
    #expect(json["formatVersion"] as? Int == 2)
    #expect((json["settings"] as? [String: Any])?["time_zone"] as? String == "America/New_York")
    #expect(try ChallengeBackup.decode(export).encoded() == export)
    #expect(try york.previewImport(export).duplicateCount == 1)

    // The same file claiming another zone is a different challenge.
    var otherZone = json
    var settings = try #require(json["settings"] as? [String: Any])
    settings["time_zone"] = "America/Chicago"
    otherZone["settings"] = settings
    #expect(throws: ChallengeSyncError.conflictingChallenge) {
        try york.previewImport(JSONSerialization.data(withJSONObject: otherZone))
    }
    // A version-1 file has no zone: it is a Jersey export, so not this challenge.
    var versionOne = json
    settings.removeValue(forKey: "time_zone")
    versionOne["settings"] = settings
    versionOne["formatVersion"] = 1
    #expect(throws: ChallengeSyncError.conflictingChallenge) {
        try york.previewImport(JSONSerialization.data(withJSONObject: versionOne))
    }

    // A version-1 export of a Jersey challenge still imports into that challenge.
    let jerseyNow = instant("2026-10-08T12:00:00Z")
    var jersey = try ChallengeStore(ownerID: owner, directory: root.appendingPathComponent("jersey"))
    try jersey.start(on: jerseyNow)
    var source = try ChallengeStore(ownerID: owner, directory: root.appendingPathComponent("source"))
    try source.merge(record: try #require(jersey.record), events: [])
    try source.record(.pour(900), on: jerseyNow, at: jerseyNow)
    var legacy = try #require(JSONSerialization.jsonObject(with: source.exportData()) as? [String: Any])
    var legacySettings = try #require(legacy["settings"] as? [String: Any])
    legacySettings.removeValue(forKey: "time_zone")
    legacy["settings"] = legacySettings
    legacy["formatVersion"] = 1
    let legacyData = try JSONSerialization.data(withJSONObject: legacy)
    #expect(try ChallengeBackup.decode(legacyData).settings.timeZone == "Europe/Jersey")
    #expect(try jersey.previewImport(legacyData).newCount == 1)
    try jersey.importData(legacyData)
    #expect(jersey.challenge?.summary(on: jerseyNow, asOf: jerseyNow).waterMillilitres == 900)
    legacy["formatVersion"] = 3
    #expect(throws: ChallengeBackupError.unsupportedVersion) {
        try ChallengeBackup.decode(JSONSerialization.data(withJSONObject: legacy))
    }
}

@Test func reminderWindowsAreWallClockTimeInTheChallengeZone() {
    func plan(_ identifier: String, at now: Date, settings: WaterReminderSettings = .init(enabled: true)) -> [Date] {
        let planner = WaterReminderPlanner(timeZone: zone(identifier), clock: { now })
        let end = planner.calendar.dateInterval(of: .day, for: now)!.end.addingTimeInterval(-1)
        return planner.upcoming(settings: settings, through: end, waterMillilitres: { _ in 0 })
    }
    // New York in daylight time (UTC−4): 09:00–21:00 local every 90 minutes.
    let york = plan("America/New_York", at: local("America/New_York", 2026, 10, 8, 7))
    #expect(york.count == 9)
    #expect(york.first == instant("2026-10-08T13:00:00Z"))
    #expect(york.last == instant("2026-10-09T01:00:00Z"))
    // After the November change (UTC−5) the same wall times move an hour in UTC.
    #expect(plan("America/New_York", at: local("America/New_York", 2026, 11, 2, 7)).first == instant("2026-11-02T14:00:00Z"))
    // Sydney's 09:00 on 8 October is 22:00 UTC the day before.
    #expect(plan("Australia/Sydney", at: local("Australia/Sydney", 2026, 10, 8, 7)).first == instant("2026-10-07T22:00:00Z"))
    // Sydney skips 02:00–03:00 on 4 October 2026: missing wall times are skipped.
    let skipped = WaterReminderSettings(enabled: true, intervalMinutes: 30, startMinute: 90, endMinute: 210)
    #expect(plan("Australia/Sydney", at: local("Australia/Sydney", 2026, 10, 4, 0), settings: skipped) == [
        local("Australia/Sydney", 2026, 10, 4, 1, 30), local("Australia/Sydney", 2026, 10, 4, 3),
        local("Australia/Sydney", 2026, 10, 4, 3, 30)])
    // The window closes at the zone's 21:00, not Jersey's.
    #expect(plan("America/New_York", at: local("America/New_York", 2026, 10, 8, 21, 0, 1)).isEmpty)
    #expect(plan("GMT", at: instant("2026-10-08T20:59:00Z")) == [instant("2026-10-08T21:00:00Z")])
}
