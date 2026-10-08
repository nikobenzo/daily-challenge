import AppKit
import ChallengeCore
import Foundation
import SwiftUI
import Testing
@testable import DailyChallengeProof

@MainActor private final class ReminderClock {
    var now = ISO8601DateFormatter().date(from: "2026-10-08T07:59:30Z")!
    func set(_ string: String) { now = ISO8601DateFormatter().date(from: string)! }
}

@MainActor private final class FakeWaterCenter: WaterNotificationCenter {
    var authorization = WaterNotificationPermission.allowed
    var requested = 0
    var pending: [Date] = []
    var additions: [Date] = []
    var scheduleHook: (() -> Void)?
    var failSchedule = false
    var failPermission = false
    func permission() async -> WaterNotificationPermission { authorization }
    func requestPermission() async throws {
        requested += 1
        if failPermission { throw URLError(.noPermissionsToReadFile) }
    }
    func cancel() { pending = [] }
    func schedule(at date: Date, timeZone: TimeZone) async throws {
        if failSchedule { throw URLError(.unknown) }
        let hook = scheduleHook; scheduleHook = nil; hook?()
        await Task.yield()
        pending = [date]
        additions.append(date)
    }
}

@MainActor private struct ReminderFixture {
    let suite = "WaterReminderTests.\(UUID())"
    let clock = ReminderClock()
    let center = FakeWaterCenter()
    let defaults: UserDefaults
    let model: WaterReminderController
    init() {
        defaults = UserDefaults(suiteName: suite)!
        let clock = self.clock
        model = WaterReminderController(defaults: defaults, center: center, clock: { clock.now })
    }
    func enable(water: Int? = 0) async {
        model.refresh(waterMillilitres: water)
        model.update(.init(enabled: true))
        await model.settle()
    }
    func cleanup() { defaults.removePersistentDomain(forName: suite) }
}

@Test @MainActor func permissionGrantDenialAndRequestErrorAreTruthful() async {
    let f = ReminderFixture(); defer { f.cleanup() }
    f.center.authorization = .notDetermined
    f.center.failPermission = true
    await f.enable()
    #expect(f.center.requested == 1 && f.center.pending.isEmpty)
    #expect(f.model.permission == .notDetermined && f.model.errorMessage != nil)
    f.center.authorization = .denied
    f.model.refresh(waterMillilitres: 0); await f.model.settle()
    #expect(f.center.pending.isEmpty)
    #expect(f.model.status.contains("System Settings > Notifications"))
    f.center.authorization = .allowed
    f.model.refresh(waterMillilitres: 0); await f.model.settle()
    #expect(f.center.pending.count == 1)
    #expect(f.center.requested == 1) // polling never prompts
    f.center.authorization = .denied
    f.model.refresh(waterMillilitres: 0); await f.model.settle()
    #expect(f.center.pending.isEmpty)
}

@Test @MainActor func deviceSettingsPersistWithoutEnablingOtherMacAndChangesReconcile() async {
    let f = ReminderFixture(), otherMac = ReminderFixture()
    defer { f.cleanup(); otherMac.cleanup() }
    await f.enable()
    let relaunched = WaterReminderController(defaults: f.defaults, center: f.center, clock: { f.clock.now })
    #expect(relaunched.settings.enabled)
    #expect(!otherMac.model.settings.enabled)
    f.model.update(.init(enabled: true, intervalMinutes: 30, startMinute: 600, endMinute: 660))
    await f.model.settle()
    #expect(f.center.pending.isEmpty)
    f.clock.set("2026-10-08T09:29:30Z")
    f.model.refresh(waterMillilitres: 0); await f.model.settle()
    #expect(f.center.pending == [f.clock.now.addingTimeInterval(30)])
    f.model.update(.init(enabled: false)); await f.model.settle()
    #expect(f.center.pending.isEmpty)
}

@Test @MainActor func goalCompletionUndoAndSignOutCancelOrResumeOnlyFutureSlots() async {
    let f = ReminderFixture(); defer { f.cleanup() }
    await f.enable()
    #expect(f.center.pending.count == 1)
    f.model.refresh(waterMillilitres: 4_000)
    #expect(f.center.pending.isEmpty) // synchronous invalidation
    await f.model.settle()
    #expect(f.center.pending.isEmpty)
    f.clock.set("2026-10-08T08:00:01Z")
    f.model.refresh(waterMillilitres: 3_550); await f.model.settle()
    #expect(f.center.pending.isEmpty)
    f.clock.set("2026-10-08T09:29:30Z")
    f.model.refresh(waterMillilitres: 3_550); await f.model.settle()
    #expect(f.center.pending == [f.clock.now.addingTimeInterval(30)])
    f.model.refresh(waterMillilitres: nil); await f.model.settle()
    #expect(f.center.pending.isEmpty)
}

@Test @MainActor func sleepWakeMidnightAndTwentyOneBoundaryNeverQueueBacklog() async {
    let f = ReminderFixture(); defer { f.cleanup() }
    await f.enable()
    f.model.sleep(); await f.model.settle()
    #expect(f.center.pending.isEmpty)
    f.clock.set("2026-10-08T15:31:00Z")
    f.model.wake(); await f.model.settle()
    #expect(f.center.pending.isEmpty)
    #expect(f.center.additions.count == 1)
    f.clock.set("2026-10-08T19:59:30Z")
    f.model.refresh(waterMillilitres: 0); await f.model.settle()
    #expect(f.center.pending == [f.clock.now.addingTimeInterval(30)])
    f.clock.set("2026-10-08T20:00:00Z")
    f.model.refresh(waterMillilitres: 0); await f.model.settle()
    #expect(f.center.pending.isEmpty)
    f.clock.set("2026-10-08T23:00:00Z")
    f.model.refresh(waterMillilitres: 0); await f.model.settle()
    #expect(f.center.pending.isEmpty) // no next-day queue until the window nears
    f.clock.set("2026-10-09T07:59:30Z")
    f.model.refresh(waterMillilitres: 0); await f.model.settle()
    #expect(f.center.pending == [f.clock.now.addingTimeInterval(30)])
}

@Test @MainActor func midnightWindowUsesNextDaysTotalAndCancelsOnSleepOrCompletion() async {
    let f = ReminderFixture(); defer { f.cleanup() }
    f.model.update(.init(enabled: true, startMinute: 0, endMinute: 0))
    f.clock.set("2026-10-08T22:58:59Z")
    f.model.refresh(waterMillilitres: 4_000, nextDayWaterMillilitres: 0)
    await f.model.settle()
    #expect(f.center.pending.isEmpty)
    f.clock.set("2026-10-08T22:59:00Z")
    f.model.refresh(waterMillilitres: 4_000, nextDayWaterMillilitres: 0)
    await f.model.settle()
    #expect(f.center.pending == [f.clock.now.addingTimeInterval(60)])
    f.model.refresh(waterMillilitres: 0, nextDayWaterMillilitres: 4_000)
    #expect(f.center.pending.isEmpty)
    await f.model.settle()
    #expect(f.center.pending.isEmpty)
    f.model.refresh(waterMillilitres: 4_000, nextDayWaterMillilitres: 3_550)
    await f.model.settle()
    #expect(f.center.pending.count == 1)
    f.model.sleep(); await f.model.settle()
    #expect(f.center.pending.isEmpty)
    f.clock.set("2026-10-08T23:00:00Z")
    f.model.wake(); await f.model.settle()
    #expect(f.center.pending.isEmpty)
    f.model.refresh(waterMillilitres: 3_550, nextDayWaterMillilitres: 0)
    await f.model.settle()
    #expect(f.center.pending.isEmpty)
    #expect(f.center.additions.count == 2)
}

@Test @MainActor func lateAsyncScheduleCannotSurviveIncomingCompletion() async {
    let f = ReminderFixture(); defer { f.cleanup() }
    f.center.scheduleHook = { f.model.refresh(waterMillilitres: 4_000) }
    await f.enable()
    #expect(f.center.pending.isEmpty && f.model.scheduledDate == nil)
}

@Test @MainActor func relaunchClearsStaleRequestsAndUsesOnlyShortUpcomingHorizon() async {
    let f = ReminderFixture(); defer { f.cleanup() }
    await f.enable()
    #expect(f.center.pending.count == 1)
    f.clock.set("2026-10-08T12:00:01Z")
    let relaunched = WaterReminderController(defaults: f.defaults, center: f.center, clock: { f.clock.now })
    relaunched.refresh(waterMillilitres: 0); await relaunched.settle()
    #expect(f.center.pending.isEmpty)
    #expect(f.center.additions.count == 1) // no missed-slot replay
    f.clock.set("2026-10-08T12:28:59Z")
    relaunched.refresh(waterMillilitres: 0); await relaunched.settle()
    #expect(f.center.pending.isEmpty) // next slot still more than 60 seconds away
    f.clock.set("2026-10-08T12:29:00Z")
    relaunched.refresh(waterMillilitres: 0); await relaunched.settle()
    #expect(f.center.pending == [f.clock.now.addingTimeInterval(60)])
}

@Test @MainActor func disablingDuringAnAsyncAddCancelsTheStaleRequest() async {
    let f = ReminderFixture(); defer { f.cleanup() }
    f.center.scheduleHook = { f.model.update(.init(enabled: false)) }
    await f.enable()
    #expect(f.center.pending.isEmpty && f.model.scheduledDate == nil)
}

@Test @MainActor func scheduleFailureIsVisibleAndPeriodicRefreshRetriesWithoutDuplicateRequests() async {
    let f = ReminderFixture(); defer { f.cleanup() }
    f.center.failSchedule = true
    await f.enable()
    #expect(f.model.errorMessage != nil && f.center.pending.isEmpty)
    f.center.failSchedule = false
    f.model.refresh(waterMillilitres: 0); await f.model.settle()
    f.model.refresh(waterMillilitres: 0); await f.model.settle()
    #expect(f.model.errorMessage == nil)
    #expect(f.center.additions.count == 1 && f.center.pending.count == 1)
}

/// Optional in-process evidence; never requests OS permission or reads real accounts.
@Test @MainActor func waterReminderSettingsRenderWithTruthfulPermissionAndMidnightState() async throws {
    let f = ReminderFixture(); defer { f.cleanup() }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let tracker = TrackerModel(directory: directory, clock: { f.clock.now })
    let owner = UUID()
    tracker.activate(ownerID: owner)
    tracker.startChallenge(on: f.clock.now)
    tracker.reminders = f.model
    let auth = ProofModel(fixtureOwnerID: owner, directory: directory)
    let previousAppearance = NSApplication.shared.appearance
    defer { NSApplication.shared.appearance = previousAppearance }
    let appearance = AppAppearance(defaults: f.defaults)
    var transcript: [String] = ["Isolated controller/centre fixture; not native notification delivery."]
    for denied in [true, false] {
        f.center.authorization = denied ? .denied : .allowed
        f.clock.set("2026-10-08T22:59:30Z")
        f.model.update(.init(enabled: true, startMinute: 0, endMinute: 0))
        f.model.refresh(waterMillilitres: 4_000, nextDayWaterMillilitres: 0)
        await f.model.settle()
        #expect(f.center.pending.count == (denied ? 0 : 1))
        transcript.append("At \(f.clock.now.ISO8601Format()), today=4000 ml, tomorrow=0 ml: \(f.model.status) Pending: \(f.center.pending.map { $0.ISO8601Format() })")
        guard let output = ProcessInfo.processInfo.environment["DAILY_CHALLENGE_SNAPSHOT_DIR"] else { continue }
        let outputDirectory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for fullSettings in [false, true] {
            let content = fullSettings
                ? AnyView(WaterReminderSettingsView(model: f.model).padding().frame(width: 420).trackerSurface())
                : AnyView(TrackerPopup(model: tracker, auth: auth, appearance: appearance, section: .account))
            let host = NSHostingView(rootView: content)
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 640), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.close() }
            window.setContentSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: outputDirectory.appendingPathComponent("water-\(fullSettings ? "settings" : "account")-\(denied ? "denied" : "allowed").png"))
        }
        try transcript.joined(separator: "\n").write(to: outputDirectory.appendingPathComponent("midnight-fixture.txt"), atomically: true, encoding: .utf8)
    }
}

@MainActor private final class ReminderTransport: ChallengeTransport {
    var header: ChallengeRecord?
    var events: [ChallengeEvent] = []
    func fetchChallenge(ownerID: UUID) async throws -> ChallengeRecord? { header }
    func insertChallenge(_ record: ChallengeRecord) async throws { header = record }
    func upload(_ events: [ChallengeEvent], ownerID: UUID) async throws {}
    func fetchEvents(ownerID: UUID, challengeID: UUID) async throws -> RemoteEvents { .init(events: events) }
}

@Test @MainActor func trackerEditsAndIncomingSyncedCompletionReconcileTodaysTotalNotSelectedHistory() async throws {
    let f = ReminderFixture(); defer { f.cleanup() }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let owner = UUID()
    let tracker = TrackerModel(directory: directory, clock: { f.clock.now })
    tracker.reminders = f.model
    tracker.activate(ownerID: owner)
    tracker.startChallenge(on: f.clock.now.addingTimeInterval(-86400))
    await f.enable()
    tracker.addWater(4_000); await f.model.settle()
    #expect(f.center.pending.isEmpty)
    tracker.undoWater(); await f.model.settle()
    #expect(f.center.pending.count == 1)
    tracker.selectHistoryDay(f.clock.now.addingTimeInterval(-86400))
    tracker.enableCorrections()
    tracker.addWater(4_000); await f.model.settle()
    #expect(f.center.pending.count == 1) // yesterday cannot silence today
    var remote = try ChallengeStore(ownerID: owner, directory: directory.appendingPathComponent("otherMac"))
    let localEvents = tracker.store!.pending.map {
        ChallengeEvent(ownerID: owner, challengeID: $0.challengeID, activity: $0.activity,
                       receivedAt: f.clock.now.ISO8601Format())
    }
    try remote.merge(record: tracker.store!.record!, events: localEvents)
    try remote.record(.pour(4_000), on: f.clock.now, at: f.clock.now)
    let transport = ReminderTransport()
    transport.header = remote.record
    transport.events = localEvents + remote.pending.map {
        ChallengeEvent(ownerID: owner, challengeID: $0.challengeID, activity: $0.activity,
                       receivedAt: f.clock.now.ISO8601Format())
    }
    tracker.configureSync(transport)
    await tracker.sync(force: true); await f.model.settle()
    #expect(tracker.syncError == nil)
    #expect(f.center.pending.isEmpty)
    f.model.update(.init(enabled: true, startMinute: 0, endMinute: 0))
    f.clock.set("2026-10-08T22:59:30Z")
    tracker.refreshReminders(); await f.model.settle()
    #expect(f.center.pending == [f.clock.now.addingTimeInterval(30)])
    f.clock.set("2026-10-08T23:00:00Z")
    tracker.refreshReminders(); await f.model.settle()
    #expect(f.center.pending.isEmpty)
    f.model.update(.init(enabled: true))
    f.clock.set("2026-10-09T07:59:30Z")
    tracker.refreshReminders(); await f.model.settle()
    #expect(f.center.pending.count == 1)
    tracker.activate(ownerID: nil); await f.model.settle()
    #expect(f.center.pending.isEmpty)
}
