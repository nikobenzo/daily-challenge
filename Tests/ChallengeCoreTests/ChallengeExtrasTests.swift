import Foundation
import Testing
@testable import ChallengeCore

private let day1 = Date(timeIntervalSince1970: 1_791_460_800) // 8 October 2026, 13:00 Jersey
private let day2 = day1.addingTimeInterval(86_400)
private func fixtureDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
private func confirmed(_ events: [ChallengeEvent]) -> [ChallengeEvent] {
    events.map { ChallengeEvent(ownerID: $0.ownerID, challengeID: $0.challengeID, activity: $0.activity,
                                receivedAt: day2.ISO8601Format()) }
}

@Test func extrasActionsUseTheDocumentedWireFormat() throws {
    let id = UUID(uuidString: "E1E1E1E1-0000-4000-8000-000000000001")!
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    func json(_ action: Challenge.Action) throws -> String { String(decoding: try encoder.encode(action), as: UTF8.self) }
    #expect(try json(.defineExtra(id: id, title: "Stretch")) == #"{"defineExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","title":"Stretch"}}"#)
    #expect(try json(.archiveExtra(id: id)) == #"{"archiveExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001"}}"#)
    #expect(try json(.setExtra(id: id, completed: true)) == #"{"setExtra":{"completed":true,"id":"E1E1E1E1-0000-4000-8000-000000000001"}}"#)
    // The original four are unchanged.
    #expect(try json(.setHabit(.walk, completed: true)) == #"{"setHabit":{"_0":"walk","completed":true}}"#)
    for action in [Challenge.Action.defineExtra(id: id, title: "Stretch"), .archiveExtra(id: id), .setExtra(id: id, completed: false)] {
        #expect(try JSONDecoder().decode(Challenge.Action.self, from: encoder.encode(action)) == action)
    }
}

@Test func twoDevicesConvergeOnDefineRenameArchiveAndTicks() throws {
    let aDir = fixtureDirectory(), bDir = fixtureDirectory(), owner = UUID()
    defer { try? FileManager.default.removeItem(at: aDir); try? FileManager.default.removeItem(at: bDir) }
    var a = try ChallengeStore(ownerID: owner, directory: aDir)
    var b = try ChallengeStore(ownerID: owner, directory: bDir)
    try a.start(on: day1)
    let stretch = UUID(), journal = UUID(), read = UUID()
    try a.record(.defineExtra(id: stretch, title: "Stretch"), on: day1, at: day1)
    try a.record(.defineExtra(id: journal, title: "Journal"), on: day1, at: day1.addingTimeInterval(1))
    let header = try #require(a.record)
    let initial = confirmed(a.pending)
    try a.merge(record: header, events: initial)
    try b.merge(record: header, events: initial)

    // Offline on both: A renames, ticks and archives; B renames the same extra later,
    // adds one, and ticks the extra A archived before it heard of the archive.
    try a.record(.defineExtra(id: stretch, title: "Stretch 10 min"), on: day2, at: day2)
    try a.record(.setExtra(id: stretch, completed: true), on: day1, at: day2.addingTimeInterval(1))
    try a.record(.archiveExtra(id: journal), on: day2, at: day2.addingTimeInterval(2))
    try b.record(.defineExtra(id: stretch, title: "Stretch 15 min"), on: day2, at: day2.addingTimeInterval(3))
    try b.record(.defineExtra(id: read, title: "Read"), on: day2, at: day2.addingTimeInterval(4))
    try b.record(.setExtra(id: journal, completed: true), on: day2, at: day2.addingTimeInterval(5))
    try b.record(.setExtra(id: read, completed: true), on: day2, at: day2.addingTimeInterval(6))

    let union = confirmed(a.pending + b.pending)
    try a.merge(record: header, events: union.reversed())
    try b.merge(record: header, events: union + initial)
    let merged = try #require(a.challenge)
    #expect(merged.allActivities == b.challenge?.allActivities)
    #expect(a.pendingCount == 0 && b.pendingCount == 0)

    // Creation order; the last rename in event order wins; the archive is permanent.
    #expect(merged.allExtras.map(\.title) == ["Stretch 15 min", "Journal", "Read"])
    #expect(merged.allExtras.map(\.isArchived) == [false, true, false])
    // Stretch was completed on day 1 and Journal archived on day 2; Read first appears on day 2.
    #expect(merged.extras(asOf: day2).map(\.id) == [read])
    // History keeps the archived extra on earlier days, with their ticks.
    #expect(merged.extras(asOf: day1).map(\.id) == [stretch, journal])
    let first = merged.summary(on: day1, asOf: day2)
    #expect(first.completedExtras == [stretch] && first.extrasDone == 1 && first.extrasTotal == 2)
    // B's tick on the archive day is kept as history but not shown or counted.
    let second = merged.summary(on: day2, asOf: day2)
    #expect(second.completedExtras == [read] && second.extrasTotal == 1)
    #expect(merged.allExtras.first { $0.id == journal }?.completedOn == nil)
    #expect(merged.history(on: day2).contains { $0.action == .setExtra(id: journal, completed: true) })

    let reopened = try ChallengeStore(ownerID: owner, directory: aDir)
    #expect(reopened.challenge?.allActivities == b.challenge?.allActivities)
    #expect(reopened.challenge?.allExtras == b.challenge?.allExtras)
}

@Test func extrasNeverChangeWhetherADayIsComplete() throws {
    let owner = UUID()
    var plain = Challenge(ownerID: owner, startDate: day1)
    func five(_ challenge: inout Challenge, on date: Date) throws {
        try challenge.record(.pour(4_000), on: date, at: date)
        for habit in Challenge.Habit.allCases { try challenge.record(.setHabit(habit, completed: true), on: date, at: date) }
        try challenge.record(.setDiet(.clean), on: date, at: date)
    }
    try five(&plain, on: day1)
    var withExtras = plain
    let pending = UUID(), done = UUID()
    try withExtras.record(.defineExtra(id: pending, title: "Never ticked"), on: day1, at: day1)
    try withExtras.record(.defineExtra(id: done, title: "Ticked"), on: day1, at: day1)
    try withExtras.record(.setExtra(id: done, completed: true), on: day1, at: day1)
    try withExtras.record(.setExtra(id: done, completed: true), on: day2, at: day2)
    try withExtras.record(.setExtra(id: pending, completed: true), on: day2, at: day2)

    // Day 1: complete with an extra left open. Day 2: every extra done, nothing else.
    for date in [day1, day2] {
        let before = plain.summary(on: date, asOf: day2), after = withExtras.summary(on: date, asOf: day2)
        #expect(before.isComplete == after.isComplete)
        #expect(before.status == after.status)
    }
    #expect(withExtras.summary(on: day1, asOf: day2).isComplete && !withExtras.summary(on: day1, asOf: day2).allExtrasDone)
    #expect(!withExtras.summary(on: day2, asOf: day2).isComplete && withExtras.summary(on: day2, asOf: day2).allExtrasDone)
    let streaks = withExtras.streaks(asOf: day2), plainStreaks = plain.streaks(asOf: day2)
    #expect(streaks.current == plainStreaks.current && streaks.best == plainStreaks.best)
    #expect(streaks.milestones == plainStreaks.milestones)
    // Archiving does not change completion either.
    try withExtras.record(.archiveExtra(id: pending), on: day2, at: day2)
    #expect(withExtras.summary(on: day1, asOf: day2).isComplete)
    #expect(!withExtras.summary(on: day2, asOf: day2).isComplete)
}

@Test func mergeRejectsExtrasEventsForAnUndefinedExtraOrAnInvalidTitle() throws {
    let owner = UUID()
    var challenge = Challenge(ownerID: owner, startDate: day1)
    try challenge.record(.pour(450), on: day1, at: day1, deviceID: "MacA")
    let before = challenge.allActivities
    func event(_ action: Challenge.Action) -> Challenge.Activity {
        .init(id: UUID(), day: challenge.calendar.startOfDay(for: day1), recordedAt: day1, action: action,
              undonePourID: nil, deviceID: "MacB")
    }
    let stranger = UUID()
    #expect(throws: ChallengeError.unknownExtra) { try challenge.merge([event(.setExtra(id: stranger, completed: true))]) }
    #expect(throws: ChallengeError.unknownExtra) { try challenge.merge([event(.archiveExtra(id: stranger))]) }
    for title in ["", "   ", " Padded", String(repeating: "x", count: 41), "Two\nlines", "Tab\there"] {
        #expect(throws: ChallengeError.invalidExtraTitle) {
            try challenge.merge([event(.defineExtra(id: UUID(), title: title))])
        }
    }
    #expect(challenge.allActivities == before)
    // A definition anywhere in the same union is enough, whatever its timestamp.
    let id = UUID()
    let tick = event(.setExtra(id: id, completed: true))
    let late = Challenge.Activity(id: UUID(), day: tick.day, recordedAt: day1.addingTimeInterval(60),
                                  action: .defineExtra(id: id, title: String(repeating: "é", count: 40)),
                                  undonePourID: nil, deviceID: "MacC")
    try challenge.merge([tick, late])
    #expect(challenge.summary(on: day1, asOf: day1).completedExtras == [id])
}

@Test func recordingEnforcesTheCapTitlesAndArchivedExtras() throws {
    var challenge = Challenge(ownerID: UUID(), startDate: day1)
    #expect(Challenge.extraTitle("  Walk the dog \n") == "Walk the dog")
    #expect(Challenge.extraTitle(String(repeating: "x", count: 40)) != nil)
    #expect(Challenge.extraTitle(String(repeating: "x", count: 41)) == nil)
    #expect(throws: ChallengeError.invalidExtraTitle) {
        try challenge.record(.defineExtra(id: UUID(), title: " untrimmed"), on: day1, at: day1)
    }
    #expect(throws: ChallengeError.unknownExtra) {
        try challenge.record(.setExtra(id: UUID(), completed: true), on: day1, at: day1)
    }
    let ids = (0..<Challenge.maximumActiveExtras).map { _ in UUID() }
    for (index, id) in ids.enumerated() {
        try challenge.record(.defineExtra(id: id, title: "Extra \(index)"), on: day1, at: day1)
    }
    #expect(throws: ChallengeError.tooManyExtras) {
        try challenge.record(.defineExtra(id: UUID(), title: "Eleventh"), on: day1, at: day1)
    }
    // Renaming at the cap is fine; archiving frees a place.
    try challenge.record(.defineExtra(id: ids[0], title: "Renamed"), on: day1, at: day1)
    try challenge.record(.setExtra(id: ids[1], completed: true), on: day1, at: day1)
    try challenge.record(.archiveExtra(id: ids[1]), on: day2, at: day2)
    #expect(try challenge.record(.archiveExtra(id: ids[1]), on: day2, at: day2) == nil)
    try challenge.record(.defineExtra(id: UUID(), title: "Eleventh"), on: day2, at: day2)
    #expect(challenge.extras(asOf: day2).count == Challenge.maximumActiveExtras)
    // An archived extra can't be renamed or ticked from its archive day on; earlier days can still be corrected.
    #expect(throws: ChallengeError.archivedExtra) {
        try challenge.record(.defineExtra(id: ids[1], title: "Back"), on: day2, at: day2)
    }
    #expect(throws: ChallengeError.archivedExtra) {
        try challenge.record(.setExtra(id: ids[1], completed: false), on: day2, at: day2)
    }
    try challenge.record(.setExtra(id: ids[1], completed: false), on: day1, at: day2)
    #expect(challenge.summary(on: day1, asOf: day2).completedExtras.isEmpty)
}

@Test func backupsWithExtrasAreTheCurrentVersionAndOlderVersionsStillImport() throws {
    let root = fixtureDirectory(), owner = UUID()
    defer { try? FileManager.default.removeItem(at: root) }
    var source = try ChallengeStore(ownerID: owner, directory: root.appendingPathComponent("source"))
    try source.start(on: day1)
    var target = try ChallengeStore(ownerID: owner, directory: root.appendingPathComponent("target"))
    try target.merge(record: try #require(source.record), events: [])
    let id = UUID()
    try source.record(.pour(450), on: day1, at: day1)
    try source.record(.defineExtra(id: id, title: "Stretch"), on: day1, at: day1.addingTimeInterval(1))
    try source.record(.setExtra(id: id, completed: true), on: day1, at: day1.addingTimeInterval(2))

    let export = try source.exportData()
    let json = try #require(JSONSerialization.jsonObject(with: export) as? [String: Any])
    #expect(ChallengeBackup.currentVersion == 3)
    #expect(json["formatVersion"] as? Int == 3)
    #expect(try ChallengeBackup.decode(export).encoded() == export)
    #expect(try target.previewImport(export).newCount == 3)
    try target.importData(export)
    #expect(target.challenge?.summary(on: day1, asOf: day1).completedExtras == [id])
    #expect(target.challenge?.allExtras == source.challenge?.allExtras)

    // A version-2 file (no extras could exist then) still imports.
    var versionTwo = try ChallengeStore(ownerID: owner, directory: root.appendingPathComponent("two"))
    try versionTwo.merge(record: try #require(source.record), events: [])
    var older = try #require(JSONSerialization.jsonObject(with: export) as? [String: Any])
    older["formatVersion"] = 2
    older["activities"] = (older["activities"] as? [[String: Any]])?.filter { ($0["action"] as? [String: Any])?["pour"] != nil }
    let olderData = try JSONSerialization.data(withJSONObject: older)
    #expect(try versionTwo.previewImport(olderData).newCount == 1)

    // A newer version is refused by its number before any activity is read, so the
    // message is "unsupported version", never "malformed". Apps that predate extras
    // support only up to version 2 and reject this app's exports the same way.
    var newer = json
    newer["formatVersion"] = ChallengeBackup.currentVersion + 1
    newer["activities"] = [["action": ["somethingNew": [:]]]]
    let error = #expect(throws: ChallengeBackupError.unsupportedVersion) {
        try ChallengeBackup.decode(JSONSerialization.data(withJSONObject: newer))
    }
    #expect(error?.localizedDescription == "This export format version is not supported. Nothing was imported.")
    #expect(!ChallengeBackup.supportedVersions.contains(ChallengeBackup.currentVersion + 1))
    #expect(ChallengeBackup.supportedVersions.contains(2) && ChallengeBackup.supportedVersions.contains(1))
}

// MARK: Carry-over day rules

private let day3 = day2.addingTimeInterval(86_400)
private let day4 = day3.addingTimeInterval(86_400)

private func shown(_ challenge: Challenge, on date: Date, asOf now: Date = day4) -> [String] {
    let summary = challenge.summary(on: date, asOf: now)
    return summary.extras.map { extra in
        extra.title + (summary.completedExtras.contains(extra.id) ? " ✓" : "") + (summary.isLate(extra) ? " late" : "")
    }
}

@Test func anOpenExtraCarriesOverAsLateAndACompletedOneLeavesLaterDays() throws {
    var challenge = Challenge(ownerID: UUID(), startDate: day1)
    let stretch = UUID(), dentist = UUID(), lunch = UUID()
    try challenge.record(.defineExtra(id: stretch, title: "Stretch"), on: day1, at: day1)
    try challenge.record(.defineExtra(id: dentist, title: "Book dentist"), on: day1, at: day1)
    try challenge.record(.setExtra(id: stretch, completed: true), on: day1, at: day1)
    #expect(shown(challenge, on: day1) == ["Stretch ✓", "Book dentist"])
    // Nothing is written at midnight: the next day derives the carry-over.
    #expect(shown(challenge, on: day2) == ["Book dentist late"])
    #expect(challenge.extras(asOf: day2).map(\.id) == [dentist])
    // An extra added later never appears on earlier days.
    try challenge.record(.defineExtra(id: lunch, title: "Prep lunch"), on: day3, at: day3)
    try challenge.record(.setExtra(id: dentist, completed: true), on: day3, at: day3)
    #expect(shown(challenge, on: day2) == ["Book dentist late"])
    #expect(shown(challenge, on: day3) == ["Book dentist ✓ late", "Prep lunch"])
    #expect(challenge.summary(on: day3, asOf: day3).allExtrasDone == false)
    #expect(shown(challenge, on: day4) == ["Prep lunch late"])
    let dentistExtra = try #require(challenge.allExtras.first { $0.id == dentist })
    #expect(dentistExtra.firstDay == challenge.calendar.startOfDay(for: day1))
    #expect(dentistExtra.completedOn == challenge.calendar.startOfDay(for: day3))
}

@Test func correctingAPastDayMovesTheCompletionAndTheCarryOver() throws {
    var challenge = Challenge(ownerID: UUID(), startDate: day1)
    let id = UUID()
    try challenge.record(.defineExtra(id: id, title: "Stretch"), on: day1, at: day1)
    try challenge.record(.setExtra(id: id, completed: true), on: day1, at: day1)
    #expect(shown(challenge, on: day3, asOf: day3).isEmpty)
    // Unticking day 1 (Edit this day) reopens it: it carries over to today again.
    try challenge.record(.setExtra(id: id, completed: false), on: day1, at: day3)
    #expect(shown(challenge, on: day1, asOf: day3) == ["Stretch"])
    #expect(shown(challenge, on: day2, asOf: day3) == ["Stretch late"])
    #expect(shown(challenge, on: day3, asOf: day3) == ["Stretch late"])
    // Ticking day 2 instead completes it there and hides it from day 3 on.
    try challenge.record(.setExtra(id: id, completed: true), on: day2, at: day3)
    #expect(shown(challenge, on: day1, asOf: day3) == ["Stretch"])
    #expect(shown(challenge, on: day2, asOf: day3) == ["Stretch ✓ late"])
    #expect(shown(challenge, on: day3, asOf: day3).isEmpty)
    // A rename changes the title on every day it shows; the days stay the same.
    try challenge.record(.defineExtra(id: id, title: "Stretch 10 min"), on: day3, at: day3)
    #expect(shown(challenge, on: day2, asOf: day3) == ["Stretch 10 min ✓ late"])
    #expect(shown(challenge, on: day3, asOf: day3).isEmpty)
}

@Test func archivingEndsTheCarryOverAndATickFromItsArchiveDayNeverCompletesIt() throws {
    var challenge = Challenge(ownerID: UUID(), startDate: day1)
    let id = UUID()
    try challenge.record(.defineExtra(id: id, title: "Journal"), on: day1, at: day1, deviceID: "MacA")
    try challenge.record(.archiveExtra(id: id), on: day3, at: day3, deviceID: "MacA")
    // Another device, offline, ticked it on the archive day before it heard of the archive.
    try challenge.merge([.init(id: UUID(), day: challenge.calendar.startOfDay(for: day3), recordedAt: day3,
                               action: .setExtra(id: id, completed: true), undonePourID: nil, deviceID: "MacB")])
    #expect(shown(challenge, on: day1) == ["Journal"])
    #expect(shown(challenge, on: day2) == ["Journal late"])
    #expect(shown(challenge, on: day3).isEmpty && shown(challenge, on: day4).isEmpty)
    #expect(challenge.allExtras.first?.completedOn == nil)
    #expect(challenge.openExtras(asOf: day3).isEmpty)
}

@Test func historiesRecordedUnderTheEveryDayRuleRenderWithoutRewriting() throws {
    // Before carry-over, every extra showed on every day: it could be ticked on a day
    // before its definition and again on later days.
    var challenge = Challenge(ownerID: UUID(), startDate: day1)
    let daily = UUID(), never = UUID()
    try challenge.record(.defineExtra(id: daily, title: "Stretch"), on: day2, at: day2, deviceID: "MacA")
    try challenge.record(.defineExtra(id: never, title: "Journal"), on: day2, at: day2, deviceID: "MacA")
    try challenge.record(.setExtra(id: daily, completed: true), on: day1, at: day2, deviceID: "MacA")
    try challenge.record(.setExtra(id: daily, completed: true), on: day2, at: day2, deviceID: "MacA")
    try challenge.record(.setExtra(id: daily, completed: true), on: day3, at: day3, deviceID: "MacA")
    let events = challenge.allActivities
    // The earliest ticked day completes it, and is its first day.
    #expect(shown(challenge, on: day1) == ["Stretch ✓"])
    #expect(shown(challenge, on: day2) == ["Journal"])
    #expect(shown(challenge, on: day3) == ["Journal late"])
    #expect(challenge.history(on: day3).contains { $0.action == .setExtra(id: daily, completed: true) })
    // Derived, not stored: the events are unchanged and any merge order agrees.
    var reversed = Challenge(ownerID: challenge.ownerID, startDate: day1)
    try reversed.merge(events.reversed())
    #expect(reversed.allActivities == events && reversed.allExtras == challenge.allExtras)
}

@Test func theCapCountsOnlyOpenExtras() throws {
    var challenge = Challenge(ownerID: UUID(), startDate: day1)
    let ids = (0..<Challenge.maximumActiveExtras).map { _ in UUID() }
    for (index, id) in ids.enumerated() {
        try challenge.record(.defineExtra(id: id, title: "Extra \(index)"), on: day1, at: day1)
    }
    #expect(throws: ChallengeError.tooManyExtras) {
        try challenge.record(.defineExtra(id: UUID(), title: "Eleventh"), on: day1, at: day1)
    }
    // Ticking frees its place at once; today still shows it ticked until midnight.
    try challenge.record(.setExtra(id: ids[0], completed: true), on: day1, at: day1)
    #expect(challenge.openExtras(asOf: day1).count == Challenge.maximumActiveExtras - 1)
    try challenge.record(.defineExtra(id: UUID(), title: "Eleventh"), on: day1, at: day1)
    #expect(challenge.extras(asOf: day1).count == Challenge.maximumActiveExtras + 1)
    #expect(challenge.extras(asOf: day2).count == Challenge.maximumActiveExtras)
    // Unticking can leave more than ten open, like two devices adding offline; adding waits.
    try challenge.record(.setExtra(id: ids[0], completed: false), on: day1, at: day1)
    #expect(challenge.openExtras(asOf: day1).count == Challenge.maximumActiveExtras + 1)
    #expect(throws: ChallengeError.tooManyExtras) {
        try challenge.record(.defineExtra(id: UUID(), title: "Twelfth"), on: day1, at: day1)
    }
}

@Test func theCarryOverRollsAtTheChallengeZonesMidnight() throws {
    let sydney = TimeZone(identifier: "Australia/Sydney")!
    let calendar = Challenge.calendar(for: sydney)
    let lateEvening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 23, minute: 30))!
    let pastMidnight = lateEvening.addingTimeInterval(3_600)
    var challenge = Challenge(ownerID: UUID(), startDate: lateEvening, timeZone: sydney)
    let id = UUID()
    try challenge.record(.defineExtra(id: id, title: "Stretch"), on: lateEvening, at: lateEvening)
    let before = challenge.summary(on: lateEvening, asOf: lateEvening)
    #expect(before.extras.map(\.id) == [id] && !before.isLate(before.extras[0]))
    let after = challenge.summary(on: pastMidnight, asOf: pastMidnight)
    #expect(after.extras.map(\.id) == [id] && after.isLate(after.extras[0]))
}
