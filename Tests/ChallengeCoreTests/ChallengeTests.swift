import ChallengeCore
import Foundation
import Testing

func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

@Test func nineStandardPoursReachFourLitresWithoutClampingTheTotal() throws {
    let now = instant("2026-10-08T12:00:00Z")
    var challenge = Challenge(ownerID: UUID(), startDate: now)
    for _ in 0..<8 { try challenge.record(.pour(450), on: now, at: now) }
    #expect(challenge.summary(on: now, asOf: now).waterMillilitres == 3_600)
    #expect(!challenge.summary(on: now, asOf: now).waterComplete)
    try challenge.record(.pour(450), on: now, at: now)
    #expect(challenge.summary(on: now, asOf: now).waterMillilitres == 4_050)
    #expect(challenge.summary(on: now, asOf: now).waterComplete)
}

@Test func undoRemovesTheLatestActivePourAndKeepsCorrectionHistory() throws {
    let now = instant("2026-10-08T12:00:00Z")
    var challenge = Challenge(ownerID: UUID(), startDate: now)
    #expect(try challenge.record(.undoLatestPour, on: now, at: now) == nil)
    try challenge.record(.pour(3_600), on: now, at: now)
    let latest = try challenge.record(.pour(450), on: now, at: now)
    try challenge.record(.undoLatestPour, on: now, at: now)
    let day = challenge.summary(on: now, asOf: now)
    #expect(day.waterMillilitres == 3_600)
    #expect(!day.waterComplete)
    #expect(day.activePours.count == 1)
    #expect(challenge.history(on: now).count == 3)
    #expect(challenge.history(on: now).last?.undonePourID == latest)
}

@Test func allFiveRequirementsMustBeMetAndCanBeReversed() throws {
    let now = instant("2026-10-08T12:00:00Z")
    var challenge = Challenge(ownerID: UUID(), startDate: now)
    try challenge.record(.pour(4_000), on: now, at: now)
    for habit in Challenge.Habit.allCases {
        try challenge.record(.setHabit(habit, completed: true), on: now, at: now)
    }
    #expect(!challenge.summary(on: now, asOf: now).isComplete)
    try challenge.record(.setDiet(.clean), on: now, at: now)
    #expect(challenge.summary(on: now, asOf: now).isComplete)
    try challenge.record(.setHabit(.bibleReading, completed: false), on: now, at: now)
    #expect(!challenge.summary(on: now, asOf: now).isComplete)
    try challenge.record(.setHabit(.bibleReading, completed: true), on: now, at: now)
    try challenge.record(.setDiet(.missed), on: now, at: now)
    #expect(!challenge.summary(on: now, asOf: now).isComplete)
    try challenge.record(.setDiet(.pending), on: now, at: now)
    #expect(challenge.summary(on: now, asOf: now).diet == .pending)
}

@Test(arguments: [0, -1])
func invalidWaterAmountsDoNotChangeTheDay(_ amount: Int) throws {
    let now = instant("2026-10-08T12:00:00Z")
    var challenge = Challenge(ownerID: UUID(), startDate: now)
    try challenge.record(.pour(450), on: now, at: now)
    #expect(throws: (any Error).self) { try challenge.record(.pour(amount), on: now, at: now) }
    #expect(challenge.summary(on: now, asOf: now).waterMillilitres == 450)
    #expect(challenge.history(on: now).count == 1)
}

@Test(arguments: ["2026-10-07T12:00:00Z", "2026-10-09T12:00:00Z"])
func datesOutsideTrackingCannotBeCompleted(_ date: String) throws {
    let now = instant("2026-10-08T12:00:00Z")
    let selected = instant(date)
    var challenge = Challenge(ownerID: UUID(), startDate: now)
    #expect(throws: (any Error).self) { try challenge.record(.pour(450), on: selected, at: now) }
    #expect(challenge.history(on: selected).isEmpty)
}

@Test func anUnfinishedDayClosesAtJerseyMidnightRatherThanUTCMidnight() throws {
    let start = instant("2026-10-08T12:00:00Z")
    let before = instant("2026-10-08T22:59:59Z")
    let midnight = instant("2026-10-08T23:00:00Z")
    var challenge = Challenge(ownerID: UUID(), startDate: start)
    try challenge.record(.pour(450), on: start, at: before)
    #expect(challenge.summary(on: start, asOf: before).status == .inProgress)
    #expect(challenge.summary(on: start, asOf: midnight).status == .missed)
    #expect(challenge.summary(on: midnight, asOf: before).status == .future)
    #expect(challenge.summary(on: midnight, asOf: midnight).status == .inProgress)
    #expect(challenge.summary(on: instant("2026-10-07T12:00:00Z"), asOf: midnight).status == .outsideChallenge)
}

func complete(_ challenge: inout Challenge, on day: Date, at now: Date) throws {
    try challenge.record(.pour(4_000), on: day, at: now)
    for habit in Challenge.Habit.allCases {
        try challenge.record(.setHabit(habit, completed: true), on: day, at: now)
    }
    try challenge.record(.setDiet(.clean), on: day, at: now)
}

@Test func todayExtendsTheStreakButOnlyAClosedMissedDayResetsIt() throws {
    let first = instant("2026-10-06T12:00:00Z")
    let yesterday = instant("2026-10-07T12:00:00Z")
    let today = instant("2026-10-08T12:00:00Z")
    let tomorrow = instant("2026-10-09T12:00:00Z")
    var challenge = Challenge(ownerID: UUID(), startDate: first)
    try complete(&challenge, on: first, at: today)
    try complete(&challenge, on: yesterday, at: today)
    #expect(challenge.streaks(asOf: today).current == 2)
    try complete(&challenge, on: today, at: today)
    #expect(challenge.streaks(asOf: today).current == 3)
    try challenge.record(.undoLatestPour, on: today, at: today)
    #expect(challenge.streaks(asOf: today).current == 2)
    #expect(challenge.streaks(asOf: tomorrow).current == 0)
    try complete(&challenge, on: tomorrow, at: tomorrow)
    #expect(challenge.streaks(asOf: tomorrow).current == 1)
    #expect(challenge.streaks(asOf: tomorrow).best == 2)
}

@Test(arguments: [("2026-03-29T12:00:00Z", 82_800.0), ("2026-10-25T12:00:00Z", 90_000.0)])
func jerseyDayIntervalsRespectBothDaylightSavingTransitions(_ fixture: (String, Double)) {
    let date = instant(fixture.0)
    let challenge = Challenge(ownerID: UUID(), startDate: date)
    #expect(challenge.summary(on: date, asOf: date).interval.duration == fixture.1)
}

@Test func seventyFiveDayMilestonesAreRecalculatedWithoutStoppingTracking() throws {
    let start = instant("2026-01-01T12:00:00Z")
    let now = instant("2026-03-17T12:00:00Z")
    var challenge = Challenge(ownerID: UUID(), startDate: start)
    for offset in 0..<76 {
        let day = start.addingTimeInterval(Double(offset) * 86_400)
        try complete(&challenge, on: day, at: now)
    }
    #expect(challenge.streaks(asOf: now).current == 76)
    #expect(challenge.streaks(asOf: now).best == 76)
    #expect(challenge.streaks(asOf: now).milestones == [instant("2026-03-16T00:00:00Z")])
    let missed = instant("2026-01-10T12:00:00Z")
    try challenge.record(.setDiet(.missed), on: missed, at: now)
    #expect(challenge.streaks(asOf: now).current == 66)
    #expect(challenge.streaks(asOf: now).milestones.isEmpty)
    try challenge.record(.setDiet(.clean), on: missed, at: now)
    #expect(challenge.streaks(asOf: now).current == 76)
    #expect(challenge.streaks(asOf: now).milestones == [instant("2026-03-16T00:00:00Z")])
    #expect(challenge.history(on: missed).count == 7)
}

@Test func retryingTheSameUndoDoesNotUndoASecondPour() throws {
    let now = instant("2026-10-08T12:00:00Z")
    var challenge = Challenge(ownerID: UUID(), startDate: now)
    let firstID = UUID()
    try challenge.record(.pour(450), on: now, at: now, id: firstID)
    try challenge.record(.pour(450), on: now, at: now, id: firstID)
    try challenge.record(.pour(450), on: now, at: now)
    let undoID = UUID()
    try challenge.record(.undoLatestPour, on: now, at: now, id: undoID)
    try challenge.record(.undoLatestPour, on: now, at: now, id: undoID)
    #expect(challenge.summary(on: now, asOf: now).waterMillilitres == 450)
    #expect(challenge.history(on: now).count == 3)
    #expect(throws: (any Error).self) {
        try challenge.record(.pour(900), on: now, at: now, id: firstID)
    }
    #expect(challenge.summary(on: now, asOf: now).waterMillilitres == 450)
}

@Test func overflowingWaterTotalsAreRejectedWithoutChangingHistory() throws {
    let now = instant("2026-10-08T12:00:00Z")
    var challenge = Challenge(ownerID: UUID(), startDate: now)
    try challenge.record(.pour(Int.max), on: now, at: now)
    #expect(throws: (any Error).self) { try challenge.record(.pour(1), on: now, at: now) }
    #expect(challenge.history(on: now).count == 1)
}

@Test func correctionsFillHistoricalGapsWithoutChangingTodaysWater() throws {
    let first = instant("2026-10-05T12:00:00Z")
    let missing = instant("2026-10-06T12:00:00Z")
    let yesterday = instant("2026-10-07T12:00:00Z")
    let today = instant("2026-10-08T12:00:00Z")
    var challenge = Challenge(ownerID: UUID(), startDate: first)
    try complete(&challenge, on: first, at: today)
    try complete(&challenge, on: yesterday, at: today)
    try complete(&challenge, on: today, at: today)
    #expect(challenge.streaks(asOf: today).current == 2)
    #expect(challenge.summary(on: missing, asOf: today).status == .missed)
    try complete(&challenge, on: missing, at: today)
    #expect(challenge.streaks(asOf: today).current == 4)
    #expect(challenge.streaks(asOf: today).best == 4)
    #expect(challenge.summary(on: today, asOf: today).waterMillilitres == 4_000)
}

@Test func launchAfterAnUnrecordedGapFindsMissedDaysWithoutStoredResetFlags() throws {
    let first = instant("2026-10-01T12:00:00Z")
    let today = instant("2026-10-05T12:00:00Z")
    var challenge = Challenge(ownerID: UUID(), startDate: first)
    try complete(&challenge, on: first, at: first)
    #expect(challenge.streaks(asOf: today).current == 0)
    #expect(challenge.streaks(asOf: today).best == 1)
    #expect(challenge.summary(on: instant("2026-10-04T12:00:00Z"), asOf: today).status == .missed)
    let notStartedYet = Challenge(ownerID: UUID(), startDate: instant("2026-10-06T12:00:00Z"))
    #expect(notStartedYet.streaks(asOf: today).current == 0)
    #expect(notStartedYet.streaks(asOf: today).best == 0)
}

@Test func explicitlyMissedDietTodayDoesNotEraseYesterdaysStreakEarly() throws {
    let yesterday = instant("2026-10-07T12:00:00Z")
    let today = instant("2026-10-08T12:00:00Z")
    var challenge = Challenge(ownerID: UUID(), startDate: yesterday)
    try complete(&challenge, on: yesterday, at: yesterday)
    try challenge.record(.setDiet(.missed), on: today, at: today)
    #expect(challenge.streaks(asOf: today).current == 1)
    #expect(challenge.streaks(asOf: instant("2026-10-08T23:00:00Z")).current == 0)
}

@Test(arguments: [
    ["2026-03-28T12:00:00Z", "2026-03-29T12:00:00Z", "2026-03-30T12:00:00Z"],
    ["2026-10-24T12:00:00Z", "2026-10-25T12:00:00Z", "2026-10-26T12:00:00Z"]
])
func streaksCountCalendarDaysAcrossDaylightSavingRatherThanTwentyFourHourPeriods(_ dates: [String]) throws {
    let days = dates.map(instant)
    let now = days[2]
    var challenge = Challenge(ownerID: UUID(), startDate: days[0])
    for day in days { try complete(&challenge, on: day, at: now) }
    #expect(challenge.streaks(asOf: now).current == 3)
    #expect(challenge.streaks(asOf: now).best == 3)
}
