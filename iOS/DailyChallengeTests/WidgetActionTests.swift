import ChallengeCore
import ChallengeSyncKit
import Foundation
import Testing
@testable import Daily_Challenge

/// Phase 4: widget App Intent writes through the shared recorder. Temporary roots,
/// injected clocks and fake transports only; no extension production account.
private final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

private let jersey = TimeZone(identifier: "Europe/Jersey")!
private func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
/// 9 October 2026, 15:00 in Jersey.
private let afternoon = instant("2026-10-09T14:00:00Z")

@MainActor private final class Harness {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("widget-actions-\(UUID())")
    let owner = UUID()
    let clock = Box(afternoon)
    let reloads = Box(0)
    var root: URL { directory.appendingPathComponent("group") }
    lazy var app = PhoneSharedStore(root: root)
    lazy var tracker: TrackerModel = {
        let clock = self.clock
        let model = TrackerModel(directory: root, clock: { clock.value }, access: app)
        model.activate(ownerID: owner)
        return model
    }()

    init(startDaysAgo: Int = 2) {
        let calendar = Challenge.calendar(for: jersey)
        tracker.startChallenge(on: calendar.date(byAdding: .day, value: -startDaysAgo, to: afternoon)!, timeZone: jersey)
    }

    func recorder(_ store: PhoneSharedStore? = nil) -> WidgetActionRecorder {
        let clock = self.clock, reloads = self.reloads
        return WidgetActionRecorder(store: store ?? PhoneSharedStore(root: root), clock: { clock.value },
                                    onCommitted: { reloads.value += 1 })
    }
    /// The binding a freshly rendered widget entry carries.
    func binding() throws -> WidgetActionBinding {
        try #require(ChallengeWidgetProvider(store: PhoneSharedStore(root: root)).entries(now: clock.value)[0].binding)
    }
    func request(_ action: WidgetActionRequest.Action) throws -> WidgetActionRequest {
        WidgetActionRequest(action, binding: try binding())
    }
    func stored(_ owner: UUID? = nil) throws -> ChallengeStore { try ChallengeStore(ownerID: owner ?? self.owner, directory: root) }
    func today(_ store: ChallengeStore? = nil) throws -> Challenge.DailySummary {
        let store = try store ?? stored()
        return store.challenge!.summary(on: clock.value, asOf: clock.value)
    }
    var snapshot: URL { root.appendingPathComponent("challenge-\(owner.uuidString.lowercased()).json") }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

@Test @MainActor func everyWidgetIntentRecordsItsExistingActionOnTodayWithTheSharedDevice() throws {
    let h = Harness(); defer { h.cleanup() }
    h.tracker.addWater(250)
    #expect(h.tracker.addExtra("Stretch") == nil)
    let extra = try #require(h.tracker.activeExtras.first?.id)
    let device = try #require(h.stored().challenge?.allActivities.last?.deviceID)
    let recorder = h.recorder()
    var pending = try h.stored().pending.count
    var latestPour: UUID?
    let steps: [(WidgetActionRequest.Action, (UUID) -> Challenge.Action)] = [
        (.pour, { _ in .pour(450) }),
        (.undoPour, { _ in .undoLatestPour }),
        (.toggleHabit(.walk), { _ in .setHabit(.walk, completed: true) }),
        (.toggleHabit(.walk), { _ in .setHabit(.walk, completed: false) }),
        (.toggleHabit(.bibleReading), { _ in .setHabit(.bibleReading, completed: true) }),
        (.toggleDiet, { _ in .setDiet(.clean) }),
        (.toggleDiet, { _ in .setDiet(.pending) }),
        (.toggleExtra(extra), { _ in .setExtra(id: extra, completed: true) }),
        (.toggleExtra(extra), { _ in .setExtra(id: extra, completed: false) })
    ]
    for (index, (action, expected)) in steps.enumerated() {
        h.clock.value = afternoon.addingTimeInterval(Double(index + 1) * 60)
        let id = UUID()
        #expect(try recorder.perform(h.request(action), invocationID: id) == .recorded(id))
        let store = try h.stored()
        let event = try #require(store.challenge?.allActivities.first { $0.id == id })
        #expect(event.action == expected(id))
        #expect(event.day == Challenge.calendar(for: jersey).startOfDay(for: afternoon))
        #expect(event.recordedAt == h.clock.value)
        #expect(event.deviceID == device)
        pending += 1
        #expect(store.pending.count == pending)
        #expect(store.pending.contains { $0.id == id })
        if action == .pour { latestPour = id }
        // Minus records the concrete pour it removed: the widget's own latest one.
        if action == .undoPour { #expect(event.undonePourID == latestPour) }
    }
    #expect(h.reloads.value == steps.count)
    #expect(try h.today().waterMillilitres == 250)
}

@Test @MainActor func minusWithNoPourTodayIsANoOpAndPlusContinuesPastTheGoal() throws {
    let h = Harness(); defer { h.cleanup() }
    // Yesterday's water is never touched by today's minus.
    let yesterday = Challenge.calendar(for: jersey).date(byAdding: .day, value: -1, to: afternoon)!
    h.tracker.selectHistoryDay(yesterday); h.tracker.enableCorrections(); h.tracker.addWater(1_000); h.tracker.showToday()
    let before = try Data(contentsOf: h.snapshot)
    #expect(try h.recorder().perform(h.request(.undoPour)) == .unchanged)
    #expect(try Data(contentsOf: h.snapshot) == before)
    #expect(h.reloads.value == 0)
    for _ in 0..<10 { _ = try h.recorder().perform(h.request(.pour)) }
    #expect(try h.today().waterMillilitres == 4_500)
    _ = try h.recorder().perform(h.request(.pour))
    #expect(try h.today().waterMillilitres == 4_950) // uncapped actual ml
    let entry = ChallengeWidgetProvider(store: PhoneSharedStore(root: h.root)).entries(now: h.clock.value)[0]
    #expect(entry.summary?.waterMillilitres == 4_950)
    #expect(try h.stored().challenge?.summary(on: yesterday, asOf: afternoon).waterMillilitres == 1_000)
}

@Test @MainActor func minusUndoesTodaysLatestSyncedCustomPourThenStops() throws {
    let h = Harness(); defer { h.cleanup() }
    h.tracker.addWater(450)
    let record = try #require(h.stored().record)
    // Another device's custom 300 ml pour, recorded later and already synced here.
    let synced = Challenge.Activity(id: UUID(), day: Challenge.calendar(for: jersey).startOfDay(for: afternoon),
                                    recordedAt: afternoon.addingTimeInterval(60), action: .pour(300),
                                    undonePourID: nil, deviceID: "another-phone")
    _ = try h.app.transaction(ownerID: h.owner) {
        try $0.merge(record: record, events: [ChallengeEvent(ownerID: h.owner, challengeID: record.id, activity: synced,
                                                             receivedAt: synced.recordedAt.ISO8601Format())])
    }
    h.clock.value = afternoon.addingTimeInterval(120)
    let first = UUID()
    #expect(try h.recorder().perform(h.request(.undoPour), invocationID: first) == .recorded(first))
    #expect(try h.stored().challenge?.allActivities.first { $0.id == first }?.undonePourID == synced.id)
    #expect(try h.today().waterMillilitres == 450) // never a fixed 450 subtraction
    _ = try h.recorder().perform(h.request(.undoPour))
    #expect(try h.today().waterMillilitres == 0)
    let count = try h.stored().challenge!.allActivities.count
    #expect(try h.recorder().perform(h.request(.undoPour)) == .unchanged)
    #expect(try h.stored().challenge!.allActivities.count == count)
}

@Test @MainActor func rapidTapsStayDistinctAndARetriedInvocationAddsNothing() throws {
    let h = Harness(); defer { h.cleanup() }
    let request = try h.request(.pour)
    let accessors = [h.recorder(), h.recorder()]
    let failures = Box(0)
    DispatchQueue.concurrentPerform(iterations: 24) { index in
        do { _ = try accessors[index % 2].perform(request) } catch { failures.value += 1 }
    }
    #expect(failures.value == 0)
    #expect(try h.today().waterMillilitres == 24 * 450)
    #expect(try h.stored().pending.count == 24)
    // The same invocation retried: one event, and a toggle is not flipped back.
    let retry = UUID(), toggle = UUID()
    #expect(try h.recorder().perform(request, invocationID: retry) == .recorded(retry))
    #expect(try h.recorder().perform(request, invocationID: retry) == .recorded(retry))
    #expect(try h.recorder().perform(h.request(.toggleHabit(.workout)), invocationID: toggle) == .recorded(toggle))
    #expect(try h.recorder().perform(h.request(.toggleHabit(.workout)), invocationID: toggle) == .recorded(toggle))
    #expect(try h.today().waterMillilitres == 25 * 450)
    #expect(try h.today().completedHabits.contains(.workout))
    #expect(try h.stored().pending.count == 26)
}

@Test @MainActor func archivedUnknownAndForgedRequestsAreRefusedWithoutChangingHistory() throws {
    let h = Harness(); defer { h.cleanup() }
    #expect(h.tracker.addExtra("Stretch") == nil)
    let archived = try #require(h.tracker.activeExtras.first?.id)
    #expect(h.tracker.archiveExtra(archived) == nil)
    let binding = try h.binding()
    let before = try Data(contentsOf: h.snapshot)
    for action in [WidgetActionRequest.Action.toggleExtra(archived), .toggleExtra(UUID())] {
        #expect(throws: WidgetActionError.self) { try h.recorder().perform(WidgetActionRequest(action, binding: binding)) }
    }
    for forged in [WidgetActionBinding(generation: UUID(), challengeID: binding.challengeID),
                   WidgetActionBinding(generation: binding.generation, challengeID: UUID())] {
        #expect(throws: PhoneSharedStoreError.self) { try h.recorder().perform(WidgetActionRequest(.pour, binding: forged)) }
    }
    #expect(try Data(contentsOf: h.snapshot) == before)
    #expect(h.reloads.value == 0)
    // Intent parameters: only supported identifiers and well-formed opaque IDs parse.
    let g = binding.generation.uuidString, c = binding.challengeID.uuidString
    #expect(WidgetActionRequest(kind: .habit, target: "walk", generation: g, challenge: c)?.action == .toggleHabit(.walk))
    #expect(WidgetActionRequest(kind: .extra, target: archived.uuidString, generation: g, challenge: c)?.action == .toggleExtra(archived))
    #expect(WidgetActionRequest(kind: .pour, generation: g, challenge: c) == WidgetActionRequest(.pour, binding: binding))
    for (kind, target, generation, challenge) in [
        (WidgetActionRequest.Kind.habit, "outdoorWorkout", g, c), (.habit, "Walk", g, c), (.habit, "", g, c),
        (.extra, "not-a-uuid", g, c), (.extra, "../challenge.json", g, c),
        (.pour, "", "owner", c), (.pour, "", g, ""), (.diet, "", "", "")
    ] {
        #expect(WidgetActionRequest(kind: kind, target: target, generation: generation, challenge: challenge) == nil)
    }
}

@Test @MainActor func corruptOrUnavailableStorageRefusesCalmlyAndPreservesBytes() throws {
    let h = Harness(); defer { h.cleanup() }
    let request = try h.request(.pour)
    try Data("corrupt snapshot".utf8).write(to: h.snapshot)
    #expect(throws: (any Error).self) { try h.recorder().perform(request) }
    #expect(try Data(contentsOf: h.snapshot) == Data("corrupt snapshot".utf8))
    #expect(throws: PhoneSharedStoreError.self) { try h.recorder(PhoneSharedStore(root: nil)).perform(request) }
    #expect(throws: PhoneSharedStoreError.self) {
        try h.recorder(PhoneSharedStore(root: h.root, available: { false })).perform(request)
    }
    try Data("corrupt".utf8).write(to: h.root.appendingPathComponent("active-account.json"))
    #expect(throws: (any Error).self) { try h.recorder().perform(request) }
    #expect(h.reloads.value == 0)
    // The widget then shows the calm unavailable state, never a stale success.
    let entry = ChallengeWidgetProvider(store: PhoneSharedStore(root: h.root)).entries(now: afternoon)[0]
    #expect(entry.state == .unavailable)
    #expect(entry.summary == nil && entry.binding == nil)
}

@Test @MainActor func staleGenerationAccountSwitchAndSignOutRefuseOldControls() throws {
    let h = Harness(); defer { h.cleanup() }
    let first = try h.binding()
    // A relaunch publishes a new generation; controls rendered before it are refused.
    let relaunched = TrackerModel(directory: h.root, clock: { afternoon }, access: PhoneSharedStore(root: h.root))
    relaunched.activate(ownerID: h.owner)
    #expect(throws: PhoneSharedStoreError.self) { try h.recorder().perform(WidgetActionRequest(.pour, binding: first)) }
    let second = try h.binding()
    #expect(second != first)
    _ = try h.recorder().perform(WidgetActionRequest(.pour, binding: second))
    let history = try Data(contentsOf: h.snapshot)
    let other = UUID()
    relaunched.activate(ownerID: other)
    #expect(throws: PhoneSharedStoreError.self) { try h.recorder().perform(WidgetActionRequest(.pour, binding: second)) }
    #expect(ChallengeWidgetProvider(store: PhoneSharedStore(root: h.root)).entries(now: afternoon)[0].binding == nil)
    #expect(try h.stored(other).challenge == nil)
    relaunched.activate(ownerID: nil)
    #expect(throws: PhoneSharedStoreError.self) { try h.recorder().perform(WidgetActionRequest(.pour, binding: second)) }
    let signedOut = ChallengeWidgetProvider(store: PhoneSharedStore(root: h.root)).entries(now: afternoon)[0]
    #expect(signedOut.state == .signedOut && signedOut.binding == nil)
    #expect(try Data(contentsOf: h.snapshot) == history) // dormant history kept, untouched
    #expect(ChallengeWidgetEntry.sample(at: afternoon).binding == nil)
}

@Test @MainActor func aTapAfterMidnightActsOnTheNewChallengeDayNeverTheRenderedOne() throws {
    let h = Harness(); defer { h.cleanup() }
    h.clock.value = instant("2026-10-09T22:59:00Z") // 23:59 in Jersey
    h.tracker.refresh()
    h.tracker.addWater(2_000); h.tracker.toggle(.workout)
    let rendered = ChallengeWidgetProvider(store: PhoneSharedStore(root: h.root)).entries(now: h.clock.value)[0]
    #expect(rendered.dateLabel.hasPrefix("9 Oct"))
    #expect(rendered.summary?.completedHabits.contains(.workout) == true)
    h.clock.value = instant("2026-10-09T23:01:00Z") // 00:01, 10 October
    let request = try #require(rendered.binding)
    let tick = UUID()
    _ = try h.recorder().perform(WidgetActionRequest(.toggleHabit(.workout), binding: request), invocationID: tick)
    let event = try #require(h.stored().challenge?.allActivities.first { $0.id == tick })
    #expect(event.day == instant("2026-10-09T23:00:00Z"))
    #expect(event.action == .setHabit(.workout, completed: true)) // fresh day, not the rendered tick
    #expect(try h.recorder().perform(WidgetActionRequest(.undoPour, binding: request)) == .unchanged)
    _ = try h.recorder().perform(WidgetActionRequest(.pour, binding: request))
    let yesterday = try h.stored().challenge!.summary(on: instant("2026-10-09T22:00:00Z"), asOf: h.clock.value)
    #expect(yesterday.waterMillilitres == 2_000 && yesterday.completedHabits.contains(.workout))
    #expect(try h.today().waterMillilitres == 450)
}

@Test @MainActor func dietFlipsPendingAndCleanButLeavesAMissedDayForTheApp() throws {
    let h = Harness(); defer { h.cleanup() }
    // Distinct instants, as real taps have: identical timestamps keep the existing
    // (timestamp, device, event ID) order rather than tap order.
    _ = try h.recorder().perform(h.request(.toggleDiet))
    #expect(try h.today().diet == .clean)
    h.clock.value += 1
    _ = try h.recorder().perform(h.request(.toggleDiet))
    #expect(try h.today().diet == .pending)
    h.clock.value += 1
    h.tracker.setDiet(.missed)
    let before = try Data(contentsOf: h.snapshot)
    #expect(try h.recorder().perform(h.request(.toggleDiet)) == .openApp)
    #expect(try h.today().diet == .missed)
    #expect(try Data(contentsOf: h.snapshot) == before)
}

@Test @MainActor func widgetAndAppEditsInterleaveThroughFreshTransactions() throws {
    let h = Harness(); defer { h.cleanup() }
    // Each edit gets its own instant: same-instant events from different devices sort by
    // their random device IDs, which would make the expected order a coin toss.
    h.tracker.toggle(.workout)
    h.clock.value += 1
    _ = try h.recorder().perform(h.request(.toggleHabit(.workout))) // reads the app's tick, unticks
    #expect(h.tracker.summary?.completedHabits.contains(.workout) == true) // app view is stale
    h.clock.value += 1
    h.tracker.toggle(.workout) // and its toggle reads the widget's untick
    #expect(h.tracker.summary?.completedHabits.contains(.workout) == true)
    let request = try h.request(.pour), recorder = h.recorder(), app = h.app, owner = h.owner
    let failures = Box(0)
    DispatchQueue.concurrentPerform(iterations: 40) { index in
        do {
            if index.isMultiple(of: 2) { _ = try recorder.perform(request) }
            else { _ = try app.transaction(ownerID: owner) { try $0.record(.pour(250), on: afternoon, at: afternoon) } }
        } catch { failures.value += 1 }
    }
    #expect(failures.value == 0)
    h.tracker.reload()
    #expect(h.tracker.summary?.waterMillilitres == 20 * 450 + 20 * 250)
    #expect(h.tracker.store?.pending.count == 3 + 40)
}

/// Insert-ignore server; `duringUpload` runs while the app awaits the network.
@MainActor private final class CatchUpServer: ChallengeTransport {
    var challenge: ChallengeRecord?
    var events: [UUID: ChallengeEvent] = [:]
    var hidden: Set<UUID> = []
    var duringUpload: (() -> Void)?
    var reachable = true
    func fetchChallenge(ownerID: UUID) async throws -> ChallengeRecord? {
        guard reachable else { throw URLError(.notConnectedToInternet) }
        return challenge
    }
    func insertChallenge(_ record: ChallengeRecord) async throws { if challenge == nil { challenge = record } }
    func upload(_ events: [ChallengeEvent], ownerID: UUID) async throws {
        guard reachable else { throw URLError(.notConnectedToInternet) }
        duringUpload?(); duringUpload = nil
        for event in events where self.events[event.id] == nil {
            self.events[event.id] = ChallengeEvent(ownerID: event.ownerID, challengeID: event.challengeID,
                                                   activity: event.activity, receivedAt: event.activity.recordedAt.ISO8601Format())
        }
    }
    func fetchEvents(ownerID: UUID, challengeID: UUID) async throws -> RemoteEvents {
        RemoteEvents(events: events.values.filter { !hidden.contains($0.id) })
    }
}

@Test @MainActor func inFlightSyncKeepsWidgetEventsPendingUntilTheirOwnUploadIsFetched() async throws {
    let h = Harness(); defer { h.cleanup() }
    let server = CatchUpServer()
    h.tracker.configureSync(server)
    h.tracker.addWater(450)
    let widgetPour = UUID(), request = try h.request(.pour), recorder = h.recorder()
    server.duringUpload = { _ = try? recorder.perform(request, invocationID: widgetPour) }
    await h.tracker.sync(force: true)
    #expect(h.tracker.syncError == nil)
    #expect(server.events[widgetPour] == nil)
    #expect(h.tracker.store?.pending.map(\.id) == [widgetPour]) // merge kept the widget's event
    #expect(h.tracker.summary?.waterMillilitres == 900)
    // Uploaded but not returned by the fetch: still pending, never acknowledged.
    server.hidden = [widgetPour]
    await h.tracker.sync(force: true)
    #expect(server.events[widgetPour] != nil)
    #expect(h.tracker.store?.pending.map(\.id) == [widgetPour])
    server.hidden = []
    await h.tracker.sync(force: true)
    #expect(h.tracker.store?.pendingCount == 0)
}

@MainActor private final class QueueCenter: WaterNotificationCenter {
    var pending: [Date] = []
    func permission() async -> WaterNotificationPermission { .allowed }
    func requestPermission() async throws {}
    func cancel() { pending = [] }
    func schedule(at date: Date, timeZone: TimeZone) async throws { pending = [date] }
    func schedule(_ dates: [Date], timeZone: TimeZone) async throws { pending = dates }
}

@Test @MainActor func foregroundAndAppRefreshConsumeWidgetEventsAndReconcileReminders() async throws {
    let h = Harness(); defer { h.cleanup() }
    let suite = "widget-actions-\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let center = QueueCenter(), clock = h.clock
    let reminders = WaterReminderController(defaults: defaults, center: center, wording: .iPhone,
                                            policy: .queued, clock: { clock.value })
    let phone = PhoneApp(auth: AuthModel(fixtureOwnerID: h.owner, now: { afternoon }), tracker: h.tracker,
                         reminders: reminders, defaults: defaults, schedulesRefresh: false)
    reminders.update(.init(enabled: true))
    h.tracker.refreshReminders()
    await reminders.settle()
    let tomorrow = Challenge.calendar(for: jersey).date(byAdding: .day, value: 1, to: Challenge.calendar(for: jersey).startOfDay(for: afternoon))!
    #expect(center.pending.contains { $0 < tomorrow })
    // Suspended app; the widget reaches the goal. Queued reminders persist until the app runs.
    for _ in 0..<9 { _ = try h.recorder().perform(h.request(.pour)) }
    #expect(h.tracker.summary?.waterMillilitres == 0)
    phone.becameActive()
    await reminders.settle()
    #expect(h.tracker.summary?.waterMillilitres == 4_050)
    #expect(!center.pending.contains { $0 < tomorrow }) // today's reminders reconciled away
    // An iOS-selected refresh uploads them through the app's transport.
    let server = CatchUpServer()
    h.tracker.configureSync(server)
    _ = try h.recorder().perform(h.request(.toggleHabit(.walk)))
    await phone.backgroundRefresh()
    #expect(h.tracker.store?.pendingCount == 0)
    #expect(h.tracker.summary?.completedHabits.contains(.walk) == true)
    #expect(server.events.values.filter { if case .pour(450) = $0.activity.action { true } else { false } }.count == 9)
}
