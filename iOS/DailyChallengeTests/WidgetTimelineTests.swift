import ChallengeCore
import ChallengeSyncKit
import Foundation
import Testing
@testable import Daily_Challenge

private func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

@Test func widgetSchedulesUseChallengeMidnightsAcrossDST() {
    for (zone, date, hours) in [
        ("Europe/Jersey", "2026-03-28T23:00:00Z", 23.0),
        ("Europe/Jersey", "2026-10-24T22:00:00Z", 25.0),
        ("America/New_York", "2026-03-07T23:00:00Z", 23.0),
        ("America/New_York", "2026-10-31T23:00:00Z", 25.0),
        ("Australia/Sydney", "2026-10-03T00:00:00Z", 23.0),
        ("Australia/Sydney", "2026-04-04T00:00:00Z", 25.0)
    ] {
        let tz = TimeZone(identifier: zone)!
        let dates = WidgetDaySchedule.dates(now: instant(date), timeZone: tz)
        #expect(dates.count == 4)
        #expect(dates[2].timeIntervalSince(dates[1]) == hours * 3600)
        let calendar = ChallengeDates(timeZone: tz).calendar
        for midnight in dates.dropFirst() { #expect(calendar.startOfDay(for: midnight) == midnight) }
    }
    let now = instant("2026-10-10T12:00:00Z")
    let dates = WidgetDaySchedule.dates(now: now, timeZone: TimeZone(identifier: "Australia/Sydney")!)
    #expect(dates[1] == instant("2026-10-10T13:00:00Z")) // independent of device's zone
}

@Test func widgetEntriesRecalculateDayWaterHabitsExtrasAndStreak() throws {
    let now = instant("2026-10-10T12:00:00Z")
    let owner = UUID()
    var challenge = Challenge(ownerID: owner, startDate: now, timeZone: Challenge.legacyTimeZone)
    for action in [Challenge.Action.pour(4500), .setHabit(.workout, completed: true), .setHabit(.walk, completed: true), .setHabit(.bibleReading, completed: true), .setDiet(.clean)] {
        _ = try challenge.record(action, on: now, at: now)
    }
    let extra = UUID()
    _ = try challenge.record(.defineExtra(id: extra, title: "Synthetic extra"), on: now, at: now)
    _ = try challenge.record(.setExtra(id: extra, completed: true), on: now, at: now)
    let dates = WidgetDaySchedule.dates(now: now, timeZone: challenge.timeZone)
    let entries = dates.map { ChallengeWidgetEntry.derive(challenge, at: $0) }
    #expect(entries[0].summary?.waterMillilitres == 4500)
    #expect(entries[0].summary?.isComplete == true)
    #expect(entries[0].dayNumber == 1)
    #expect(entries[1].dayNumber == 2)
    #expect(entries[1].summary?.waterMillilitres == 0)
    #expect(entries[1].summary?.completedHabits.isEmpty == true)
    #expect(entries[1].summary?.diet == .pending)
    #expect(entries[1].summary?.extrasDone == 0)
    #expect(entries[1].streak == 1)
    #expect(entries[2].streak == 0)
    // Derivation is correct even when a provider wakes days late.
    #expect(ChallengeWidgetEntry.derive(challenge, at: dates[3]).dayNumber == 4)
    #expect(ChallengeWidgetEntry.derive(challenge, at: now.addingTimeInterval(-86400)).dayNumber == nil)
    _ = try challenge.record(.archiveExtra(id: extra), on: dates[1], at: dates[1])
    #expect(ChallengeWidgetEntry.derive(challenge, at: now).summary?.extrasTotal == 1)
    #expect(ChallengeWidgetEntry.derive(challenge, at: dates[1]).summary?.extrasTotal == 0)
}

@Test func widgetProviderNeverLeaksInactiveOrUnreadableHistory() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("widget-tests-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PhoneSharedStore(root: root)
    let now = Date()
    let provider = ChallengeWidgetProvider(store: store)
    #expect(provider.entries(now: now)[0].state == .signedOut)
    let owner = UUID()
    _ = try store.activate(ownerID: owner)
    #expect(provider.entries(now: now)[0].state == .noChallenge)
    _ = try store.transaction(ownerID: owner) { current in
        try current.start(on: now, timeZone: Challenge.legacyTimeZone)
        try current.record(.defineExtra(id: UUID(), title: "Private title"), on: now, at: now)
    }
    #expect(provider.entries(now: now)[0].summary?.extrasTotal == 1)
    let snapshot = root.appendingPathComponent("challenge-\(owner.uuidString.lowercased()).json")
    let bytes = try Data(contentsOf: snapshot)
    try Data("corrupt snapshot".utf8).write(to: snapshot)
    #expect(provider.entries(now: now)[0].state == .unavailable)
    #expect(provider.entries(now: now)[0].summary == nil)
    #expect(try Data(contentsOf: snapshot) == Data("corrupt snapshot".utf8))
    try bytes.write(to: snapshot)
    _ = try store.activate(ownerID: UUID())
    #expect(provider.entries(now: now)[0].summary == nil)
    _ = try store.activate(ownerID: nil)
    #expect(provider.entries(now: now)[0].state == .signedOut)
    try Data("corrupt".utf8).write(to: root.appendingPathComponent("active-account.json"))
    #expect(provider.entries(now: now)[0].state == .unavailable)
    #expect(provider.entries(now: now)[0].summary == nil)
    #expect(ChallengeWidgetProvider(store: PhoneSharedStore(root: nil)).entries(now: now)[0].state == .unavailable)
    #expect(ChallengeWidgetProvider(store: PhoneSharedStore(root: root, available: { false })).entries(now: now)[0].state == .unavailable)
    let placeholder = ChallengeWidgetEntry.sample(at: now)
    #expect(placeholder.summary?.extrasTotal == 0)
}

@Test @MainActor func widgetDeepLinksGateManagementAndUseFixedDestinations() {
    let defaults = UserDefaults(suiteName: "widget-routing-\(UUID())")!
    let app = PhoneFixtures.make(.today, defaults: defaults)
    app.openWidgetURL(URL(string: "daily-challenge://extras")!)
    #expect(app.tab == .today)
    #expect(app.manageExtrasRequested)
    app.openWidgetURL(URL(string: "daily-challenge://today")!)
    #expect(!app.manageExtrasRequested)
    app.openWidgetURL(URL(string: "https://extras")!)
    #expect(!app.manageExtrasRequested)
}
