import Foundation
import Testing
@testable import ChallengeCore

// Custom daily targets and recurring extras (P1 of the custom goals plan). The day rules
// themselves are in the shared parity vectors; these cover the store, files and planner.

private let day1 = Date(timeIntervalSince1970: 1_791_460_800) // 8 October 2026, 13:00 Jersey
private let day2 = day1.addingTimeInterval(86_400)
private let day3 = day2.addingTimeInterval(86_400)
private func fixtureDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

private var custom: Challenge.Targets {
    var targets = Challenge.Targets.standard
    targets.water = .init(goal: 3_000, glass: 250)
    targets.walk = .init(name: "Yoga", amount: 30, unit: .minutes, icon: "yoga")
    targets.bibleReading = .init(name: "Audiobook", amount: 20, unit: .minutes, icon: "headphones")
    return targets
}

@Test func targetAndScheduleActionsUseTheDocumentedWireFormat() throws {
    let id = UUID(uuidString: "E1E1E1E1-0000-4000-8000-000000000001")!
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    func json(_ action: Challenge.Action) throws -> String { String(decoding: try encoder.encode(action), as: UTF8.self) }
    let cases: [(Challenge.Action, String)] = [
        (.setTarget(.walk, name: "Yoga", amount: 30, unit: .minutes, icon: "yoga"),
         #"{"setTarget":{"_0":"walk","amount":30,"icon":"yoga","name":"Yoga","unit":"minutes"}}"#),
        (.setTarget(.diet, name: "No sugar"), #"{"setTarget":{"_0":"diet","name":"No sugar"}}"#),
        (.setWater(goal: 3_000, pour: 250), #"{"setWater":{"goal":3000,"pour":250}}"#),
        (.scheduleExtra(id: id, weekdays: [1, 2, 3, 4, 5]),
         #"{"scheduleExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","weekdays":[1,2,3,4,5]}}"#),
        (.scheduleExtra(id: id, every: 2), #"{"scheduleExtra":{"every":2,"id":"E1E1E1E1-0000-4000-8000-000000000001"}}"#),
        (.scheduleExtra(id: id), #"{"scheduleExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001"}}"#),
    ]
    for (action, text) in cases {
        #expect(try json(action) == text)
        #expect(try JSONDecoder().decode(Challenge.Action.self, from: Data(text.utf8)) == action)
    }
    #expect(Challenge.ExtraSchedule.weekdays([5, 1, 3]).action(for: id) == .scheduleExtra(id: id, weekdays: [1, 3, 5]))
    #expect(Challenge.ExtraSchedule(weekdays: nil, every: nil) == .once)
}

@Test func standardTargetsAreTheOriginalFiveAndWriteNothing() {
    let standard = Challenge.Targets.standard
    #expect(standard.water == .init(goal: 4_000, glass: 450))
    #expect(standard.workout == .init(name: "Workout", amount: 45, unit: .minutes))
    #expect(standard.walk == .init(name: "Walk", amount: 45, unit: .minutes))
    #expect(standard.diet == .init(name: "Diet"))
    #expect(standard.bibleReading == .init(name: "Bible", amount: 10, unit: .pages))
    #expect(standard.changes().isEmpty)
    #expect(Challenge.TargetSlot.allCases.allSatisfy { standard[$0].isValid(for: $0) } && standard.water.isValid)
    #expect(custom.changes() == [.setWater(goal: 3_000, pour: 250),
                                 .setTarget(.walk, name: "Yoga", amount: 30, unit: .minutes, icon: "yoga"),
                                 .setTarget(.bibleReading, name: "Audiobook", amount: 20, unit: .minutes, icon: "headphones")])
}

@Test func setupWithCustomTargetsCommitsThemWithTheSettingsOnTheStartDay() throws {
    let root = fixtureDirectory(), owner = UUID()
    defer { try? FileManager.default.removeItem(at: root) }
    var store = try ChallengeStore(ownerID: owner, directory: root)
    // A start date in the past: the targets apply from that day, recorded now.
    try store.start(on: day1, timeZone: Challenge.legacyTimeZone, targets: custom, at: day3)
    let challenge = try #require(store.challenge)
    #expect(store.pending.count == 3)
    #expect(store.pendingCount == 4) // and the settings header
    #expect(store.pending.allSatisfy { $0.activity.day == challenge.startDate && $0.activity.recordedAt == day3 })
    #expect(store.pending.map(\.activity.action) == custom.changes())
    #expect(challenge.targets(on: day1) == custom && challenge.targets(on: day3) == custom)
    // One atomic file: reopening finds the same settings, events and queue.
    let reopened = try ChallengeStore(ownerID: owner, directory: root)
    #expect(reopened.pending.map(\.id) == store.pending.map(\.id))
    #expect(reopened.challenge?.targets(on: day2) == custom)

    // The standard targets write no events at all.
    var plain = try ChallengeStore(ownerID: UUID(), directory: root)
    try plain.start(on: day1, timeZone: Challenge.legacyTimeZone, targets: .standard, at: day1)
    #expect(plain.pending.isEmpty && plain.pendingCount == 1)
}

@Test func setupRefusesInvalidTargetsWithoutWritingAnything() throws {
    let root = fixtureDirectory(), owner = UUID()
    defer { try? FileManager.default.removeItem(at: root) }
    var store = try ChallengeStore(ownerID: owner, directory: root)
    var bad = custom
    bad.water = .init(goal: 999, glass: 250)
    #expect(throws: ChallengeError.invalidTarget) {
        try store.start(on: day1, timeZone: Challenge.legacyTimeZone, targets: bad, at: day1)
    }
    bad = custom
    bad.diet = .init(name: "No sugar", amount: 1, unit: .pages)
    #expect(throws: ChallengeError.invalidTarget) {
        try store.start(on: day1, timeZone: Challenge.legacyTimeZone, targets: bad, at: day1)
    }
    // A start after `now` cannot hold events dated on it.
    #expect(throws: ChallengeError.dateOutsideChallenge) {
        try store.start(on: day2, timeZone: Challenge.legacyTimeZone, targets: custom, at: day1)
    }
    #expect(store.challenge == nil)
    #expect(!FileManager.default.fileExists(atPath: root.path))
}

@Test func unreadableTargetsAndSchedulesAreRefusedByTheDecoderNotTheMerge() throws {
    func activity(_ action: String) -> Data {
        Data(#"{"id":"AAAAAAAA-0000-4000-8000-000000000001","day":781484400,"recordedAt":781527600,"deviceID":"x","action":\#(action)}"#.utf8)
    }
    for action in [#"{"setTarget":{"_0":"walk","name":"Yoga","amount":301,"unit":"minutes"}}"#,
                   #"{"setTarget":{"_0":"yoga","name":"Yoga"}}"#,
                   #"{"setWater":{"goal":3000,"pour":3001}}"#,
                   #"{"scheduleExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","weekdays":[1,1]}}"#] {
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Challenge.Activity.self, from: activity(action)) }
    }
    // An icon id this version doesn't know is kept, and shows the slot's default.
    let unknownIcon = try JSONDecoder().decode(Challenge.Activity.self, from: activity(
        #"{"setTarget":{"_0":"walk","name":"Yoga","icon":"trampoline"}}"#))
    #expect(unknownIcon.action == .setTarget(.walk, name: "Yoga", icon: "trampoline"))
}

@Test func backupsWithTargetsAreVersionFourAndVersionThreeStillImports() throws {
    let root = fixtureDirectory(), owner = UUID()
    defer { try? FileManager.default.removeItem(at: root) }
    var source = try ChallengeStore(ownerID: owner, directory: root.appendingPathComponent("source"))
    try source.start(on: day1, timeZone: Challenge.legacyTimeZone, targets: custom, at: day1)
    let extra = UUID()
    try source.record(.defineExtra(id: extra, title: "Stretch"), on: day1, at: day1.addingTimeInterval(1))
    try source.record(.scheduleExtra(id: extra, every: 1), on: day1, at: day1.addingTimeInterval(2))
    try source.record(.setExtra(id: extra, completed: true), on: day2, at: day2)

    let export = try source.exportData()
    let json = try #require(JSONSerialization.jsonObject(with: export) as? [String: Any])
    #expect(json["formatVersion"] as? Int == 4)
    #expect(try ChallengeBackup.decode(export).encoded() == export)
    var target = try ChallengeStore(ownerID: owner, directory: root.appendingPathComponent("target"))
    try target.merge(record: try #require(source.record), events: [])
    #expect(try target.previewImport(export).newCount == 6)
    try target.importData(export)
    #expect(target.challenge?.targets(on: day2) == custom)
    #expect(target.challenge?.allExtras == source.challenge?.allExtras)
    #expect(target.challenge?.allExtras.first?.schedule == .every(1))

    // A version-3 file (extras, no targets) still imports, with the standard targets.
    var three = try ChallengeStore(ownerID: owner, directory: root.appendingPathComponent("three"))
    try three.merge(record: try #require(source.record), events: [])
    var older = json
    older["formatVersion"] = 3
    older["activities"] = (older["activities"] as? [[String: Any]])?.filter { activity in
        let kind = (activity["action"] as? [String: Any])?.keys.first ?? ""
        return !["setTarget", "setWater", "scheduleExtra"].contains(kind)
    }
    #expect(try three.previewImport(JSONSerialization.data(withJSONObject: older)).newCount == 2)
    try three.importData(JSONSerialization.data(withJSONObject: older))
    #expect(three.challenge?.targets(on: day2) == .standard)
}

@Test func remindersStopOnceThatDaysOwnGoalIsMet() {
    let now = day1 // 13:00 Jersey
    let settings = WaterReminderSettings(enabled: true, intervalMinutes: 60, startMinute: 9 * 60, endMinute: 21 * 60)
    let planner = WaterReminderPlanner(timeZone: Challenge.legacyTimeZone, clock: { now })
    let calendar = Challenge.calendar(for: Challenge.legacyTimeZone)
    let today = calendar.startOfDay(for: now)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
    let horizon = calendar.date(byAdding: .day, value: 2, to: today)!
    func plan(goal: @escaping (Date) -> Int, water: Int) -> [Date] {
        planner.upcoming(settings: settings, through: horizon, goal: goal, waterMillilitres: { _ in water })
    }
    // 3,150 ml meets a 3,000 ml goal, so only tomorrow (a 4,000 ml day) is planned.
    let lowered = plan(goal: { $0 == today ? 3_000 : 4_000 }, water: 3_150)
    #expect(!lowered.isEmpty && lowered.allSatisfy { $0 >= tomorrow })
    // Raised above the total, today is planned again.
    #expect(plan(goal: { _ in 3_500 }, water: 3_150).contains { $0 < tomorrow })
    // Without a goal the standard 4,000 ml applies, as before.
    #expect(planner.upcoming(settings: settings, through: horizon, waterMillilitres: { _ in 4_000 }).isEmpty)
}
