import ChallengeCore
import Foundation
import Testing
@testable import ChallengeSyncKit

private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

@MainActor private final class Clock {
    var now = date("2026-10-08T12:00:00Z")
}

@MainActor private func withTracker(_ test: (TrackerModel, URL, UUID, Clock) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let owner = UUID(), clock = Clock()
    let model = TrackerModel(directory: directory, clock: { clock.now })
    model.activate(ownerID: owner)
    try test(model, directory, owner, clock)
}

private let yoga = Challenge.Target(name: "Yoga", amount: 30, unit: .minutes, icon: "yoga")

@Test @MainActor func dailyGoalsChangeFromTodayAndEarlierDaysKeepTheirs() throws {
    try withTracker { model, directory, owner, clock in
        #expect(model.setTargets(.standard) == ChallengeStoreError.notStarted.localizedDescription)
        let start = clock.now.addingTimeInterval(-2 * 86_400)
        model.startChallenge(on: start, timeZone: TimeZone(identifier: "Europe/London")!)
        #expect(model.currentTargets == .standard)
        #expect(model.setTargets(.standard) == nil)
        #expect(model.history.isEmpty, "Unchanged targets record nothing")

        var next = Challenge.Targets.standard
        next.walk = yoga
        next.water = Challenge.WaterTarget(goal: 3_000, glass: 330)
        #expect(model.setTargets(next) == nil)
        #expect(model.currentTargets == next)
        #expect(model.history.count == 2, "One event per changed value, on today")
        #expect(model.challenge?.targets(on: start) == .standard)
        #expect(model.challenge?.targets(on: start.addingTimeInterval(86_400)) == .standard)

        // + now pours today's glass, and today's water is judged by today's goal.
        model.addWater()
        #expect(model.summary?.waterMillilitres == 330)
        for _ in 0..<8 { model.addWater() }
        #expect(model.summary?.waterMillilitres == 2_970)
        #expect(model.summary?.waterComplete == false)
        model.addWater()
        #expect(model.summary?.waterComplete == true)

        // A past day pours that day's own glass.
        model.selectHistoryDay(start)
        model.enableCorrections()
        model.addWater()
        #expect(model.summary?.waterMillilitres == 450)

        let reopened = TrackerModel(directory: directory, clock: { clock.now })
        reopened.activate(ownerID: owner)
        #expect(reopened.currentTargets == next)
        #expect(reopened.store?.pendingCount == model.store?.pendingCount)
    }
}

@Test @MainActor func invalidDailyGoalsSaveNothingAtAll() throws {
    try withTracker { model, _, _, clock in
        model.startChallenge(on: clock.now)
        var next = Challenge.Targets.standard
        next.walk = yoga
        next.water = Challenge.WaterTarget(goal: 3_000, glass: 3_500)
        #expect(model.setTargets(next) == ChallengeError.invalidTarget.localizedDescription)
        next.water = Challenge.WaterTarget(goal: 3_000, glass: 330)
        next.bibleReading = Challenge.Target(name: "Book", amount: 600, unit: .pages)
        #expect(model.setTargets(next) == ChallengeError.invalidTarget.localizedDescription)
        next.bibleReading = Challenge.Target(name: "   ")
        #expect(model.setTargets(next) == ChallengeError.invalidTarget.localizedDescription)
        next.bibleReading = .init(name: "Bible", amount: 10, unit: .pages)
        next.diet = Challenge.Target(name: "No sugar", amount: 5, unit: .minutes)
        #expect(model.setTargets(next) == ChallengeError.invalidTarget.localizedDescription)
        #expect(model.history.isEmpty, "A refused change writes none of its values")
        #expect(model.currentTargets == .standard)
    }
}

@Test @MainActor func modelSchedulesExtrasFromToday() throws {
    try withTracker { model, _, _, clock in
        model.startChallenge(on: clock.now)
        #expect(model.addExtra("Stretch") == nil)
        let stretch = try #require(model.activeExtras.first)
        #expect(model.scheduleExtra(stretch.id, .weekdays([1, 2, 3, 4, 5])) == nil)
        #expect(model.scheduleExtra(stretch.id, .weekdays([1, 2, 3, 4, 5])) == nil)
        #expect(model.history.count == 2, "The same rule again records nothing")
        #expect(model.challenge?.allExtras.first?.schedule == .weekdays([1, 2, 3, 4, 5]))
        #expect(model.scheduleExtra(UUID(), .every(2)) == ChallengeError.unknownExtra.localizedDescription)
        // 8 October 2026 is a Thursday, so a weekday rule shows it today, never late.
        #expect(model.summary?.extras.map(\.id) == [stretch.id])
        #expect(model.summary?.isLate(stretch) == false)
    }
}
