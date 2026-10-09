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

@Test @MainActor func setupAndAllFiveUIControlsPersistACompleteDay() throws {
    try withTracker { model, directory, owner, clock in
        #expect(model.store != nil)
        #expect(model.challenge == nil)
        model.startChallenge(on: clock.now)
        for _ in 0..<9 { model.addWater() }
        for habit in Challenge.Habit.allCases { model.toggle(habit) }
        model.setDiet(.clean)
        #expect(model.summary?.waterMillilitres == 4_050)
        #expect(model.summary?.isComplete == true)
        #expect(model.streaks?.current == 1)
        #expect(model.dayNumber == 1)
        let reopened = TrackerModel(directory: directory, clock: { clock.now })
        reopened.activate(ownerID: owner)
        #expect(reopened.summary?.isComplete == true)
        #expect(reopened.history.count == 13)
    }
}

@Test @MainActor func customPourAndUndoUseTheSelectedDaysActiveHistory() throws {
    try withTracker { model, _, _, clock in
        model.startChallenge(on: clock.now)
        model.addCustomWater(" 250 ")
        model.addWater()
        let pouredID = model.summary?.activePours.last?.id
        model.undoWater()
        #expect(model.summary?.waterMillilitres == 250)
        #expect(model.history.first?.undonePourID == pouredID)
        model.addCustomWater("1.5")
        #expect(model.errorMessage != nil)
        model.addCustomWater("0")
        #expect(model.summary?.waterMillilitres == 250)
        #expect(model.history.count == 3)
    }
}

@Test @MainActor func historicalControlsRequireExplicitEditingAndDoNotChangeToday() throws {
    try withTracker { model, _, _, clock in
        let yesterday = date("2026-10-07T12:00:00Z")
        model.startChallenge(on: yesterday)
        model.selectHistoryDay(yesterday)
        #expect(!model.canEdit)
        model.addWater()
        #expect(model.history.isEmpty)
        model.enableCorrections()
        model.addCustomWater("4000")
        for habit in Challenge.Habit.allCases { model.toggle(habit) }
        model.setDiet(.clean)
        #expect(model.summary?.isComplete == true)
        #expect(model.streaks?.current == 1)
        model.selectHistoryDay(clock.now)
        #expect(!model.canEdit)
        #expect(model.summary?.waterMillilitres == 0)
        model.showToday()
        #expect(model.canEdit)
    }
}

@Test @MainActor func jerseyMidnightRefreshesTodayButDoesNotRetargetHistoryCorrections() throws {
    try withTracker { model, _, _, clock in
        clock.now = date("2026-10-08T22:59:59Z")
        model.refresh()
        model.startChallenge(on: clock.now)
        model.addWater()
        let firstDay = model.selectedDay
        clock.now = date("2026-10-08T23:00:00Z")
        model.refresh()
        #expect(model.dayNumber == 2)
        #expect(model.selectedDay != firstDay)
        #expect(model.summary?.waterMillilitres == 0)
        model.selectHistoryDay(clock.now)
        model.enableCorrections()
        let editingDay = model.selectedDay
        clock.now = date("2026-10-09T23:00:00Z")
        model.addWater()
        #expect(model.selectedDay == editingDay)
        #expect(model.summary?.waterMillilitres == 450)
        model.showToday()
        #expect(model.summary?.waterMillilitres == 0)
    }
}

@Test @MainActor func accountSwitchAndSignOutNeverExposeAnotherAccountsHistory() throws {
    try withTracker { model, _, owner, clock in
        model.startChallenge(on: clock.now)
        model.addWater()
        model.activate(ownerID: UUID())
        #expect(model.challenge == nil)
        #expect(model.summary == nil)
        model.startChallenge(on: clock.now)
        model.addCustomWater("900")
        model.activate(ownerID: nil)
        #expect(model.store == nil)
        #expect(model.history.isEmpty)
        model.activate(ownerID: owner)
        #expect(model.summary?.waterMillilitres == 450)
    }
}

@Test @MainActor func aFailedControlWriteReportsTheErrorAndKeepsTheSavedAmount() throws {
    try withTracker { model, directory, owner, clock in
        model.startChallenge(on: clock.now)
        model.addWater()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        model.addWater()
        #expect(model.errorMessage != nil)
        #expect(model.summary?.waterMillilitres == 450)
        let reopened = TrackerModel(directory: directory, clock: { clock.now })
        reopened.activate(ownerID: owner)
        #expect(reopened.summary?.waterMillilitres == 450)
    }
}

@Test @MainActor func corruptLocalDataShowsRecoveryInsteadOfSetupOrReset() throws {
    try withTracker { model, directory, owner, clock in
        model.startChallenge(on: clock.now)
        let file = directory.appendingPathComponent("challenge-\(owner.uuidString.lowercased()).json")
        try Data("corrupt".utf8).write(to: file)
        model.reload()
        #expect(model.store == nil)
        #expect(model.errorMessage != nil)
        model.startChallenge(on: clock.now)
        #expect(try String(contentsOf: file, encoding: .utf8) == "corrupt")
    }
}

@Test @MainActor func setupRejectsFutureDatesAndExistingHistoryIsNeverReplaced() throws {
    try withTracker { model, _, _, clock in
        model.startChallenge(on: date("2026-10-09T12:00:00Z"))
        #expect(model.challenge == nil)
        #expect(model.errorMessage != nil)
        model.startChallenge(on: clock.now)
        model.addWater()
        model.startChallenge(on: date("2026-10-07T12:00:00Z"))
        #expect(model.errorMessage != nil)
        #expect(model.summary?.waterMillilitres == 450)
        model.selectHistoryDay(date("2026-10-09T12:00:00Z"))
        #expect(model.selectedDay == model.today)
    }
}
