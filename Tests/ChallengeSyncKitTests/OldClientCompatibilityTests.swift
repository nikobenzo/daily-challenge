import ChallengeCore
import Foundation
import Testing
@testable import ChallengeSyncKit

// Custom targets and recurring extras must not stop sync on iPhone 1.0, Mac 1.0 or Android
// phase 1, which read events with the seven kinds below and nothing else. These tests feed
// a new client's real upload to that frozen decoder (custom goals plan, section 5.4).

/// The 1.0 wire decoder, frozen: synthesized Codable over the seven original kinds.
/// Never update it; it stands for apps already installed.
private enum Habit10: String, Codable { case workout, walk, bibleReading }
private enum Diet10: String, Codable { case pending, clean, missed }
private enum Action10: Codable, Equatable {
    case pour(Int)
    case undoLatestPour
    case setHabit(Habit10, completed: Bool)
    case setDiet(Diet10)
    case defineExtra(id: UUID, title: String)
    case archiveExtra(id: UUID)
    case setExtra(id: UUID, completed: Bool)

    /// The same event as today's rules see it: 1.0 merged these kinds with the rules
    /// ChallengeCore still applies to them.
    var current: Challenge.Action {
        switch self {
        case .pour(let amount): .pour(amount)
        case .undoLatestPour: .undoLatestPour
        case .setHabit(let habit, let completed): .setHabit(Challenge.Habit(rawValue: habit.rawValue)!, completed: completed)
        case .setDiet(let diet): .setDiet(Challenge.DietState(rawValue: diet.rawValue)!)
        case .defineExtra(let id, let title): .defineExtra(id: id, title: title)
        case .archiveExtra(let id): .archiveExtra(id: id)
        case .setExtra(let id, let completed): .setExtra(id: id, completed: completed)
        }
    }
}
private struct Activity10: Decodable {
    let id: UUID, day: Double, recordedAt: Double, action: Action10, undonePourID: UUID?, deviceID: String?
    var current: Challenge.Activity {
        .init(id: id, day: Date(timeIntervalSinceReferenceDate: day), recordedAt: Date(timeIntervalSinceReferenceDate: recordedAt),
              action: action.current, undonePourID: undonePourID, deviceID: deviceID)
    }
}
private struct Event10: Decodable { let id: UUID; let activity: Activity10 }

private let day1 = Date(timeIntervalSince1970: 1_791_460_800) // 8 October 2026, 13:00 Jersey
private let day2 = day1.addingTimeInterval(86_400)

/// Server rows as a fetch returns them.
private func rows(_ events: [ChallengeEvent]) throws -> Data {
    let encoder = JSONEncoder()
    return try encoder.encode(events.map {
        ChallengeEvent(ownerID: $0.ownerID, challengeID: $0.challengeID, activity: $0.activity, receivedAt: "2026-10-09T12:00:00Z")
    })
}

/// What a 1.0 client does with fetched rows: decode each on its own, skip the unreadable
/// ones and merge the rest. A throw here is a sync that stops on that device.
private func oldClientSync(_ data: Data, into challenge: inout Challenge) throws -> Int {
    let fetched = try JSONDecoder().decode([ServerRow<Event10>].self, from: data)
    try challenge.merge(fetched.compactMap(\.value).map(\.activity.current))
    return fetched.count - fetched.compactMap(\.value).count
}

@Test func anOldClientSkipsTargetAndScheduleRowsAndKeepsSyncing() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    var targets = Challenge.Targets.standard
    targets.water = .init(goal: 3_000, glass: 450)
    targets.walk = .init(name: "Yoga", amount: 30, unit: .minutes, icon: "yoga")
    var store = try ChallengeStore(ownerID: UUID(), directory: root)
    try store.start(on: day1, timeZone: Challenge.legacyTimeZone, targets: targets, at: day1)
    var at = day1
    func record(_ action: Challenge.Action, on day: Date = day1) throws {
        at = at.addingTimeInterval(1)
        try store.record(action, on: day, at: max(at, day))
    }
    for _ in 0..<7 { try record(.pour(450)) } // 3,150 ml
    for habit in Challenge.Habit.allCases { try record(.setHabit(habit, completed: true)) }
    try record(.setDiet(.clean))
    let stretch = UUID()
    try record(.defineExtra(id: stretch, title: "Stretch"))
    try record(.scheduleExtra(id: stretch, every: 1))
    try record(.setExtra(id: stretch, completed: true))
    try record(.setTarget(.diet, name: "No sugar"), on: day2)
    let header = try #require(store.record)
    let upload = try rows(store.pending)

    // The new client reads every row and judges day 1 by its own 3,000 ml goal.
    let current = try JSONDecoder().decode([ServerRow<ChallengeEvent>].self, from: upload)
    #expect(current.allSatisfy { $0.value != nil })
    var mine = try #require(header.emptyChallenge)
    try mine.merge(current.compactMap(\.value).map(\.activity))
    #expect(mine.summary(on: day1, asOf: day2).isComplete)
    #expect(mine.extras(asOf: day2).map(\.id) == [stretch])

    // A 1.0 client skips exactly the four new rows, merges the rest without an error and
    // shows the documented, harmless differences: water judged against 4,000 ml, the
    // standard labels, and the recurring extra as a to-do that left after its tick.
    var old = try #require(header.emptyChallenge)
    #expect(try oldClientSync(upload, into: &old) == 4)
    #expect(skippedRowsNotice(4) == "4 entries from the server could not be read and were skipped. Updating Daily Challenge may show them.")
    let oldDay1 = old.summary(on: day1, asOf: day2)
    #expect(oldDay1.waterMillilitres == 3_150 && !oldDay1.waterComplete && oldDay1.status == .missed)
    #expect(oldDay1.completedHabits.count == 3 && oldDay1.diet == .clean)
    #expect(oldDay1.completedExtras == [stretch])
    #expect(old.extras(asOf: day2).isEmpty)
    #expect(old.targets(on: day2) == .standard)
    // Nothing it read is lost or rewritten: every readable row is in its history as sent.
    #expect(old.allActivities.count == current.count - 4)
    #expect(old.allActivities.allSatisfy { activity in mine.allActivities.contains(activity) })
}

@Test func theAvoidedDesignsWouldHaveBrokenOldClients() throws {
    let owner = UUID(), challengeID = UUID(), stretch = UUID()
    let start = Challenge.calendar(for: Challenge.legacyTimeZone).startOfDay(for: day1)
    let header = ChallengeRecord(ownerID: owner, startDate: start, timeZone: Challenge.legacyTimeZone)
    let dayStart = start.timeIntervalSinceReferenceDate
    func row(_ action: String, second: Int) -> String {
        let id = String(format: "AAAAAAAA-0000-4000-8000-%012d", second)
        return #"{"id":"\#(id)","owner_id":"\#(owner)","challenge_id":"\#(challengeID)","received_at":"2026-10-09T12:00:00Z","#
            + #""activity":{"id":"\#(id)","day":\#(dayStart),"recordedAt":\#(day1.timeIntervalSinceReferenceDate + Double(second)),"#
            + #""deviceID":"New","action":\#(action)}}"#
    }

    // A recurring extra defined by a new kind: the 1.0 client skips the definition, then
    // its merge refuses the tick and the whole sync stops. So the design keeps defineExtra.
    let newKind = Data("[\(row(#"{"defineRecurringExtra":{"id":"\#(stretch)","title":"Stretch","every":1}}"#, second: 1)),\(row(#"{"setExtra":{"id":"\#(stretch)","completed":true}}"#, second: 2))]".utf8)
    var old = try #require(header.emptyChallenge)
    #expect(throws: ChallengeError.unknownExtra) { try oldClientSync(newKind, into: &old) }

    // The rule as a key inside defineExtra: 1.0 reads the definition without it, so its
    // next rename writes a definition without the rule, and the last definition wins for
    // everyone. So the schedule is its own kind.
    let withKey = #"{"defineExtra":{"id":"\#(stretch)","title":"Stretch","repeat":{"every":1}}}"#
    let read = try JSONDecoder().decode(Action10.self, from: Data(withKey.utf8))
    #expect(read == .defineExtra(id: stretch, title: "Stretch"))
    #expect(!String(decoding: try JSONEncoder().encode(read), as: UTF8.self).contains("repeat"))

    // A sixth slot as a new habit value: skipped, so 1.0 would judge the day on five.
    let sixth = Data("[\(row(#"{"setHabit":{"_0":"yoga","completed":true}}"#, second: 3))]".utf8)
    old = try #require(header.emptyChallenge)
    #expect(try oldClientSync(sixth, into: &old) == 1)

    // The chosen kinds, read by this version: an out-of-range row (which the server
    // refuses anyway) is skipped like an unknown kind, never a merge failure.
    let mixed = Data("[\(row(#"{"setWater":{"goal":6000,"pour":250}}"#, second: 4)),\(row(#"{"setWater":{"goal":3000,"pour":250}}"#, second: 5)),\(row(#"{"pour":{"_0":450}}"#, second: 6))]".utf8)
    let fetched = try JSONDecoder().decode([ServerRow<ChallengeEvent>].self, from: mixed)
    #expect(fetched.map { $0.value == nil } == [true, false, false])
    var mine = try #require(header.emptyChallenge)
    try mine.merge(fetched.compactMap(\.value).map(\.activity))
    #expect(mine.targets(on: day1).water == .init(goal: 3_000, glass: 250))
}
