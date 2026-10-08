import ChallengeCore
import Foundation
import Testing
@testable import DailyChallengeProof

private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }
private func zone(_ identifier: String) -> TimeZone { Challenge.canonicalTimeZone(identifier)! }

@MainActor private final class Clock {
    var now = date("2026-10-08T13:30:00Z") // 00:30 on 9 October in Sydney, 14:30 on 8 October in Jersey
}

@MainActor private final class ZoneServer: ChallengeTransport {
    var header: ChallengeRecord?
    var events: [ChallengeEvent] = []
    func fetchChallenge(ownerID: UUID) async throws -> ChallengeRecord? { header }
    func insertChallenge(_ record: ChallengeRecord) async throws { if header == nil { header = record } }
    func upload(_ incoming: [ChallengeEvent], ownerID: UUID) async throws {
        for event in incoming where !events.contains(where: { $0.id == event.id }) {
            events.append(ChallengeEvent(ownerID: ownerID, challengeID: event.challengeID, activity: event.activity,
                                         receivedAt: event.activity.recordedAt.ISO8601Format()))
        }
    }
    func fetchEvents(ownerID: UUID, challengeID: UUID) async throws -> [ChallengeEvent] { events }
}

@MainActor private final class ZoneRecordingCenter: WaterNotificationCenter {
    var scheduled: [(Date, TimeZone)] = []
    func permission() async -> WaterNotificationPermission { .allowed }
    func requestPermission() async throws {}
    func cancel() {}
    func schedule(at date: Date, timeZone: TimeZone) async throws { scheduled.append((date, timeZone)) }
}

@MainActor private func withTracker(_ test: (TrackerModel, URL, UUID, Clock) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let owner = UUID(), clock = Clock()
    let model = TrackerModel(directory: directory, clock: { clock.now })
    model.activate(ownerID: owner)
    try await test(model, directory, owner, clock)
}

@Test @MainActor func trackerDaysFollowTheChosenZonesMidnight() async throws {
    try await withTracker { model, directory, owner, clock in
        model.startChallenge(on: clock.now, timeZone: zone("Australia/Sydney"))
        let sydney = Challenge.calendar(for: zone("Australia/Sydney"))
        #expect(model.challenge?.timeZone.identifier == "Australia/Sydney")
        #expect(model.today == sydney.date(from: DateComponents(year: 2026, month: 10, day: 9))!)
        #expect(model.selectedDay == model.today)
        #expect(model.dates.label(model.now, format: "d MMM") == "9 Oct")
        model.addWater()
        clock.now = date("2026-10-09T12:59:59Z") // 23:59:59 in Sydney
        model.refresh()
        #expect(model.dayNumber == 1)
        #expect(model.summary?.waterMillilitres == 450)
        clock.now = date("2026-10-09T13:00:00Z") // Sydney midnight; still 9 October in Jersey
        model.refresh()
        #expect(model.dayNumber == 2)
        #expect(model.summary?.waterMillilitres == 0)
        #expect(model.challenge?.summary(on: date("2026-10-08T13:30:00Z"), asOf: clock.now).status == .missed)
        let reopened = try ChallengeStore(ownerID: owner, directory: directory)
        #expect(reopened.record?.timeZone == "Australia/Sydney")
    }
}

@Test @MainActor func setupRejectsAStartDateThatIsStillFutureInTheChosenZone() async throws {
    try await withTracker { model, _, _, clock in
        let ninthInSydney = date("2026-10-09T01:00:00Z") // midday 9 October in Sydney, 02:00 in Jersey
        model.startChallenge(on: ninthInSydney, timeZone: zone("Europe/Jersey"))
        #expect(model.challenge == nil)
        #expect(model.errorMessage == "Choose today or an earlier start date.")
        model.startChallenge(on: ninthInSydney, timeZone: zone("Australia/Sydney"))
        #expect(model.challenge?.startDate == date("2026-10-08T13:00:00Z"))
        #expect(model.errorMessage == nil)
        #expect(model.dayNumber == 1)
        _ = clock
    }
}

@Test @MainActor func remindersScheduleInTheChallengeZone() async throws {
    try await withTracker { model, _, _, clock in
        let suite = "TimeZoneTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        clock.now = date("2026-10-08T12:59:30Z") // 08:59:30 in New York
        let center = ZoneRecordingCenter()
        let reminders = WaterReminderController(defaults: defaults, center: center, clock: { clock.now })
        model.reminders = reminders
        model.startChallenge(on: clock.now, timeZone: zone("America/New_York"))
        reminders.update(.init(enabled: true))
        await reminders.settle()
        #expect(reminders.timeZone.identifier == "America/New_York")
        #expect(reminders.scheduledDate == date("2026-10-08T13:00:00Z")) // 09:00 in New York
        #expect(center.scheduled.last?.1.identifier == "America/New_York")
        #expect(WaterReminderSettingsView.details(timeZone: reminders.timeZone).hasPrefix("Times are New York time"))
    }
}

@Test @MainActor func aSecondMacAdoptsTheServersZoneWithoutSetup() async throws {
    try await withTracker { model, _, owner, clock in
        let server = ZoneServer()
        let start = Challenge(ownerID: owner, startDate: clock.now, timeZone: zone("Australia/Sydney")).startDate
        server.header = ChallengeRecord(ownerID: owner, startDate: start, timeZone: zone("Australia/Sydney"))
        model.configureSync(server)
        #expect(model.dates.timeZone == .current)
        await model.sync(force: true)
        #expect(model.syncError == nil)
        #expect(model.challenge?.timeZone.identifier == "Australia/Sydney")
        #expect(model.store?.record == server.header)
        #expect(model.today == start)
        #expect(model.selectedDay == start)
        #expect(model.dayNumber == 1)
    }
}

@Test @MainActor func aZoneOnlySettingsConflictStopsSyncAndKeepsBothHistories() async throws {
    try await withTracker { model, directory, owner, clock in
        let server = ZoneServer()
        model.configureSync(server)
        await model.sync(force: true)
        model.startChallenge(on: clock.now, timeZone: zone("Europe/Jersey"))
        model.addCustomWater("900")
        let local = try #require(model.store?.record)
        // Same ID, owner and start; Jersey and London share every midnight.
        let remote = ChallengeRecord(id: local.id, ownerID: owner, startDate: local.startDate, timeZone: zone("Europe/London"))
        server.header = remote
        server.events = [ChallengeEvent(ownerID: owner, challengeID: local.id, activity: .init(
            id: UUID(), day: local.startDate, recordedAt: clock.now, action: .pour(450), undonePourID: nil, deviceID: "MacB"),
            receivedAt: clock.now.ISO8601Format())]
        let file = directory.appendingPathComponent("challenge-\(owner.uuidString.lowercased()).json")
        let before = try Data(contentsOf: file)
        await model.sync(force: true)
        #expect(model.syncError?.contains("Different challenges") == true)
        #expect(model.store?.record == local)
        #expect(model.summary?.waterMillilitres == 900)
        #expect(model.store?.pendingCount == 2)
        #expect(try Data(contentsOf: file) == before)
        #expect(server.header == remote && server.events.count == 1)
    }
}

@Test func timeZoneChoicesAreFindableByCityAndShowTheirCurrentOffset() {
    let october = date("2026-10-08T12:00:00Z")
    #expect(TimeZoneChoices.title(zone("America/New_York"), at: october) == "New York · GMT−4")
    #expect(TimeZoneChoices.title(zone("Europe/Jersey"), at: october) == "Jersey · GMT+1")
    #expect(TimeZoneChoices.title(zone("Europe/Jersey"), at: date("2026-12-01T12:00:00Z")) == "Jersey · GMT")
    #expect(ChallengeDates.offset(zone("Asia/Kolkata"), at: october) == "GMT+5:30")
    #expect(ChallengeDates.offset(zone("Australia/Sydney"), at: october) == "GMT+11")
    func found(_ query: String) -> [String] {
        TimeZoneChoices.groups(matching: query).flatMap(\.zones).map(\.identifier)
    }
    #expect(found("sydney") == ["Australia/Sydney"])
    #expect(found("new york") == ["America/New_York"])
    #expect(found("Jersey").contains("Europe/Jersey"))
    #expect(found("australia").contains("Australia/Perth"))
    #expect(found("zzz-nowhere").isEmpty)
    let all = TimeZoneChoices.groups(matching: "")
    #expect(all.map(\.region).contains("Europe"))
    #expect(all.flatMap(\.zones).count == TimeZone.knownTimeZoneIdentifiers.count)
    #expect(all.flatMap(\.zones).allSatisfy { Challenge.canonicalTimeZone($0.identifier) != nil })
}
