import ChallengeCore
import Foundation
import Testing
@testable import ChallengeSyncKit

/// The model calls behind the goals editors and the repeat picker: changes recorded on
/// today in one commit, the + pour from the selected day's glass, and repeat rules.
private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

@MainActor private final class Clock {
    var now = date("2026-10-12T12:00:00Z")
}

@MainActor private func withTracker(_ test: (TrackerModel, URL, UUID, Clock) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let owner = UUID(), clock = Clock()
    let model = TrackerModel(directory: directory, clock: { clock.now })
    model.activate(ownerID: owner)
    try test(model, directory, owner, clock)
}

private let london = TimeZone(identifier: "Europe/London")!
private let yoga = Challenge.Target(name: "Yoga", amount: 30, unit: .minutes, icon: "yoga")

@Test @MainActor func goalChangesApplyFromTodayWhicheverDayIsSelected() throws {
    try withTracker { model, _, _, clock in
        let start = clock.now.addingTimeInterval(-3 * 86_400)
        model.startChallenge(on: start, timeZone: london)
        model.selectHistoryDay(start)
        model.enableCorrections()
        var targets = model.todayTargets
        targets.walk = yoga
        targets.water = Challenge.WaterTarget(goal: 3_000, glass: 330)
        #expect(model.setTargets(targets) == nil)
        let events = try #require(model.challenge?.allActivities)
        #expect(events.count == 2 && events.allSatisfy { $0.day == model.today })
        #expect(model.challenge?.targets(on: start) == .standard)
        #expect(model.todayTargets == targets)
        #expect(model.store?.pendingCount == 3, "The settings and both changes wait to upload")
        // Saving the same goals again records nothing.
        #expect(model.setTargets(targets) == nil)
        #expect(model.challenge?.allActivities.count == 2)
    }
}

@Test @MainActor func thePlusButtonPoursTheSelectedDaysGlass() throws {
    try withTracker { model, _, _, clock in
        let start = clock.now.addingTimeInterval(-86_400)
        model.startChallenge(on: start, timeZone: london)
        var targets = model.todayTargets
        targets.water = Challenge.WaterTarget(goal: 2_000, glass: 250)
        #expect(model.setTargets(targets) == nil)
        model.addWater()
        #expect(model.summary?.waterMillilitres == 250)
        model.selectHistoryDay(start)
        model.enableCorrections()
        model.addWater()
        #expect(model.summary?.waterMillilitres == 450, "Yesterday's glass was still the standard 450 ml")
        model.addWater(100)
        #expect(model.summary?.waterMillilitres == 550, "An explicit amount still pours as given")
    }
}

@Test @MainActor func aFailedGoalsSaveWritesNoneOfTheChanges() throws {
    try withTracker { model, directory, owner, clock in
        model.startChallenge(on: clock.now, timeZone: london)
        var targets = model.todayTargets
        targets.walk = yoga
        targets.diet = Challenge.Target(name: "No sugar")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        let error = try #require(model.setTargets(targets))
        #expect(error.hasPrefix("Could not save. Your previous history is intact."))
        #expect(model.todayTargets == .standard)
        let reopened = TrackerModel(directory: directory, clock: { clock.now })
        reopened.activate(ownerID: owner)
        #expect(reopened.challenge?.allActivities.isEmpty == true)
    }
}

@Test @MainActor func invalidGoalsAreRefusedWithTheirMessage() throws {
    try withTracker { model, _, _, clock in
        model.startChallenge(on: clock.now, timeZone: london)
        var targets = model.todayTargets
        targets.water = Challenge.WaterTarget(goal: 1_000, glass: 1_200)
        #expect(model.setTargets(targets) == ChallengeError.invalidTarget.localizedDescription)
        targets = model.todayTargets
        targets.diet = Challenge.Target(name: "No sugar", amount: 1, unit: .chapters)
        #expect(model.setTargets(targets) == ChallengeError.invalidTarget.localizedDescription)
        #expect(model.challenge?.allActivities.isEmpty == true)
    }
}

@Test @MainActor func repeatRulesApplyFromTodayAndRepeatingExtrasAreNeverLate() throws {
    try withTracker { model, _, _, clock in
        let start = clock.now.addingTimeInterval(-2 * 86_400)
        model.startChallenge(on: start, timeZone: london)
        #expect(model.addExtra("Stretch") == nil)
        let stretch = try #require(model.activeExtras.first)
        #expect(model.scheduleExtra(stretch.id, .every(1)) == nil)
        model.toggleExtra(stretch.id)
        #expect(model.summary?.allExtrasDone == true)
        clock.now = clock.now.addingTimeInterval(86_400)
        model.refresh()
        let tomorrow = try #require(model.summary)
        #expect(tomorrow.extras.map(\.id) == [stretch.id], "A repeating extra comes back each day")
        let shown = try #require(tomorrow.extras.first)
        #expect(tomorrow.completedExtras.isEmpty && !tomorrow.isLate(shown), "Unticked, and never late")
        #expect(model.activeExtras.count == 1, "It keeps its place in the cap")
        #expect(model.scheduleExtra(stretch.id, .weekdays([1, 2, 3, 4, 5])) == nil)
        #expect(model.challenge?.allExtras.first?.schedule == .weekdays([1, 2, 3, 4, 5]))
        #expect(model.scheduleExtra(stretch.id, .every(31)) == ChallengeError.invalidSchedule.localizedDescription)
        #expect(model.archiveExtra(stretch.id) == nil)
        #expect(model.scheduleExtra(stretch.id, .every(2)) == ChallengeError.archivedExtra.localizedDescription)
    }
}

@Test func severalActionsCommitTogetherOrNotAtAll() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = date("2026-10-12T12:00:00Z")
    let owner = UUID()
    var store = try ChallengeStore(ownerID: owner, directory: directory)
    try store.start(on: now, timeZone: london, at: now)
    let before = store.challenge?.allActivities.count
    #expect(throws: ChallengeError.invalidTarget) {
        try store.record(all: [.setWater(goal: 3_000, pour: 330), .setWater(goal: 3_000, pour: 4_000)], on: now, at: now)
    }
    #expect(store.challenge?.allActivities.count == before, "The valid first change was not kept either")
    let ids = try store.record(all: [.setWater(goal: 3_000, pour: 330),
                                     .setTarget(.walk, name: "Yoga", amount: 30, unit: .minutes, icon: "yoga")], on: now, at: now)
    #expect(ids.count == 2 && Set(ids).count == 2)
    #expect(store.pendingCount == 3)
    let reopened = try ChallengeStore(ownerID: owner, directory: directory)
    #expect(reopened.challenge?.targets(on: now).walk.name == "Yoga")
}
