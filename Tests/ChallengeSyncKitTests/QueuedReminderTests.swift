import ChallengeCore
import Foundation
import Testing
@testable import ChallengeSyncKit

/// The iPhone's policy: every remaining slot today and tomorrow is queued, because a
/// suspended app cannot schedule the next one in time. The Mac's one-slot policy is
/// covered by the Mac's WaterReminderTests.
@MainActor private final class QueueCenter: WaterNotificationCenter {
    var pending: [Date] = []
    var singleRequests = 0
    func permission() async -> WaterNotificationPermission { .allowed }
    func requestPermission() async throws {}
    func cancel() { pending = [] }
    func schedule(at date: Date, timeZone: TimeZone) async throws { singleRequests += 1; pending = [date] }
    func schedule(_ dates: [Date], timeZone: TimeZone) async throws { pending = dates }
}

@MainActor private func queued(at now: Date) -> (WaterReminderController, QueueCenter, UserDefaults, String) {
    let suite = "QueuedReminderTests.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    let center = QueueCenter()
    let controller = WaterReminderController(defaults: defaults, center: center, wording: .iPhone,
                                             policy: .queued, clock: { now })
    return (controller, center, defaults, suite)
}

private let jersey = TimeZone(identifier: "Europe/Jersey")!
private func jerseyTime(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    Challenge.calendar(for: jersey).date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

@Test @MainActor func queuedPolicyHandsTheSystemEveryRemainingSlotOfTodayAndTomorrow() async {
    let (controller, center, defaults, suite) = queued(at: jerseyTime(8, 11))
    defer { defaults.removePersistentDomain(forName: suite) }
    controller.refresh(waterMillilitres: 450, nextDayWaterMillilitres: 0, timeZone: jersey)
    controller.update(.init(enabled: true))
    await controller.settle()
    // 12:00 … 21:00 today (7 slots) and 09:00 … 21:00 tomorrow (9 slots), every 90 minutes.
    #expect(center.pending.count == 16)
    #expect(center.pending.first == jerseyTime(8, 12))
    #expect(center.pending.last == jerseyTime(9, 21))
    #expect(controller.scheduledDates == center.pending)
    #expect(controller.scheduledDate == jerseyTime(8, 12))
    #expect(center.singleRequests == 0)
    #expect(controller.status == "Permission allowed · Reminders enabled on this iPhone. Delivery depends on iOS and Focus.")
}

@Test @MainActor func meetingTodaysGoalDropsTodaysQueuedRemindersButKeepsTomorrows() async {
    let (controller, center, defaults, suite) = queued(at: jerseyTime(8, 11))
    defer { defaults.removePersistentDomain(forName: suite) }
    controller.update(.init(enabled: true))
    controller.refresh(waterMillilitres: 4_050, nextDayWaterMillilitres: 0, timeZone: jersey)
    await controller.settle()
    #expect(center.pending.count == 9)
    #expect(center.pending.first == jerseyTime(9, 9))
    // An undo below the goal brings back only future slots of today.
    controller.refresh(waterMillilitres: 3_600, nextDayWaterMillilitres: 0, timeZone: jersey)
    await controller.settle()
    #expect(center.pending.first == jerseyTime(8, 12))
}

@Test @MainActor func turningQueuedRemindersOffCancelsAllOfThem() async {
    let (controller, center, defaults, suite) = queued(at: jerseyTime(8, 11))
    defer { defaults.removePersistentDomain(forName: suite) }
    controller.refresh(waterMillilitres: 0, nextDayWaterMillilitres: 0, timeZone: jersey)
    controller.update(.init(enabled: true))
    await controller.settle()
    #expect(!center.pending.isEmpty)
    controller.update(.init(enabled: false))
    await controller.settle()
    #expect(center.pending.isEmpty)
    #expect(controller.scheduledDates.isEmpty)
    #expect(controller.status == "Permission allowed · Reminders off on this iPhone.")
}

@Test func iPhoneSyncWordingNamesTheDevice() {
    #expect(SyncState.savedLocally(pending: 2).plainText(on: .iPhone) == "Saved on this iPhone, 2 changes waiting")
    #expect(SyncState.synced(at: Date(), clockWarning: true).clockWarningText(on: .iPhone)
        == "This iPhone's clock looks ahead of the server; check Settings > General > Date & Time if this keeps happening")
    #expect(SyncState.localOnly.plainText(on: .mac) == "Saved on this Mac only, not connected to the server")
}
