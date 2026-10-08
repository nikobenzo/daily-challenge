import Foundation
import Testing
@testable import ChallengeCore

private func plan(_ date: String, settings: WaterReminderSettings = .init(enabled: true), water: Int? = 0) -> [Date] {
    let now = instant(date)
    let end = Challenge.calendar(for: Challenge.legacyTimeZone).dateInterval(of: .day, for: now)!.end.addingTimeInterval(-1)
    return WaterReminderPlanner(clock: { now }).upcoming(settings: settings, through: end, waterMillilitres: { _ in water })
}

@Test func midnightWaterSlotsUseTargetDayEligibilityWithinHorizon() {
    let settings = WaterReminderSettings(enabled: true, startMinute: 0, endMinute: 0)
    for midnight in ["2026-10-08T23:00:00Z", "2026-03-29T23:00:00Z", "2026-10-26T00:00:00Z"] {
        let target = instant(midnight)
        let now = target.addingTimeInterval(-60)
        let planner = WaterReminderPlanner(clock: { now })
        #expect(planner.upcoming(settings: settings, through: target, waterMillilitres: {
            $0 == target ? 0 : 4_000
        }) == [target])
        #expect(planner.upcoming(settings: settings, through: target, waterMillilitres: {
            $0 == target ? 4_000 : 0
        }).isEmpty)
        #expect(planner.upcoming(settings: settings, through: target, waterMillilitres: { _ in nil }).isEmpty)
        #expect(planner.upcoming(settings: settings, through: target.addingTimeInterval(-1), waterMillilitres: { _ in 0 }).isEmpty)
        for offset in [0.0, 1.0] {
            let late = target.addingTimeInterval(offset)
            #expect(WaterReminderPlanner(clock: { late }).upcoming(
                settings: settings, through: late.addingTimeInterval(60), waterMillilitres: { _ in 0 }).isEmpty)
        }
    }
}

@Test func defaultWaterSlotsAreJerseyAnchoredAndIncludeNineAndTwentyOne() {
    let dates = plan("2026-10-08T07:59:00Z")
    #expect(dates.count == 9)
    #expect(dates.first == instant("2026-10-08T08:00:00Z"))
    #expect(dates.last == instant("2026-10-08T20:00:00Z"))
    #expect(zip(dates, dates.dropFirst()).allSatisfy { $1.timeIntervalSince($0) == 90 * 60 })
    #expect(plan("2026-10-08T19:59:59Z") == [instant("2026-10-08T20:00:00Z")])
    #expect(plan("2026-10-08T20:00:00Z").isEmpty)
    #expect(plan("2026-10-08T21:00:00Z").isEmpty)
}

@Test func completionUndoAndMissingChallengeOnlyPlanFutureWaterSlots() {
    #expect(plan("2026-10-08T10:15:00Z", water: 4_000).isEmpty)
    #expect(plan("2026-10-08T10:15:00Z", water: 4_500).isEmpty)
    #expect(plan("2026-10-08T10:15:00Z", water: nil).isEmpty)
    #expect(plan("2026-10-08T10:15:00Z", water: 3_999).first == instant("2026-10-08T11:00:00Z"))
    #expect(plan("2026-10-08T10:15:00Z", settings: .init()).isEmpty)
}

@Test func configurableIntervalsAnchorToWindowAndNeverExtendPastIt() {
    let settings = WaterReminderSettings(enabled: true, intervalMinutes: 40, startMinute: 600, endMinute: 690)
    #expect(plan("2026-10-08T08:00:00Z", settings: settings) == [
        instant("2026-10-08T09:00:00Z"), instant("2026-10-08T09:40:00Z"), instant("2026-10-08T10:20:00Z")])
    #expect(plan("2026-10-08T08:00:00Z", settings: .init(enabled: true, intervalMinutes: 0)).isEmpty)
    #expect(plan("2026-10-08T08:00:00Z", settings: .init(enabled: true, startMinute: 1300, endMinute: 400)).isEmpty)
}

@Test func midnightAndRelaunchNeverReplayYesterdayOrEarlierSlots() {
    #expect(plan("2026-10-08T22:59:59Z").isEmpty)
    #expect(plan("2026-10-08T23:00:00Z").first == instant("2026-10-09T08:00:00Z"))
    #expect(plan("2026-10-09T17:00:01Z").first == instant("2026-10-09T18:30:00Z"))
}

@Test func jerseyDSTChangesRetainDefaultLocalWindow() {
    #expect(plan("2026-03-28T00:00:00Z").first == instant("2026-03-28T09:00:00Z"))
    #expect(plan("2026-03-29T00:00:00Z").first == instant("2026-03-29T08:00:00Z"))
    #expect(plan("2026-10-24T00:00:00Z").last == instant("2026-10-24T20:00:00Z"))
    #expect(plan("2026-10-25T00:00:00Z").last == instant("2026-10-25T21:00:00Z"))
}

@Test func customWindowSkipsMissingDSTTimesAndRepeatedTimesOnlyOccurOnce() {
    let settings = WaterReminderSettings(enabled: true, intervalMinutes: 30, startMinute: 60, endMinute: 150)
    #expect(plan("2026-03-29T00:00:00Z", settings: settings) == [
        instant("2026-03-29T01:00:00Z"), instant("2026-03-29T01:30:00Z")])
    #expect(plan("2026-10-24T23:00:00Z", settings: settings) == [
        instant("2026-10-25T00:00:00Z"), instant("2026-10-25T00:30:00Z"),
        instant("2026-10-25T02:00:00Z"), instant("2026-10-25T02:30:00Z")])
    #expect(plan("2026-10-25T01:00:00Z", settings: settings).first == instant("2026-10-25T02:00:00Z"))
}
