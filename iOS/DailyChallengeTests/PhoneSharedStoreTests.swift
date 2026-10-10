import ChallengeCore
import ChallengeSyncKit
import Foundation
import Testing
@testable import Daily_Challenge

private struct SharedFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shared-test-\(UUID())")
    let owner = UUID()
    let now = Date(timeIntervalSince1970: 1_791_554_400)
    var root: URL { directory.appendingPathComponent("group") }
    var legacy: URL { directory.appendingPathComponent("private") }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
    func access(legacy: Bool = false) -> PhoneSharedStore { PhoneSharedStore(root: root, legacy: legacy ? self.legacy : nil) }
    @MainActor func model(_ access: PhoneSharedStore) -> TrackerModel {
        let model = TrackerModel(directory: root, clock: { now }, access: access)
        model.activate(ownerID: owner)
        return model
    }
    func oldStore() throws -> ChallengeStore {
        var store = try ChallengeStore(ownerID: owner, directory: legacy)
        try store.start(on: now, timeZone: TimeZone(identifier: "Europe/Jersey")!)
        try store.record(.pour(250), on: now, at: now)
        return store
    }
}

private final class ConcurrentFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func fail() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

@Test @MainActor func independentAccessorsPreserveConcurrentPoursTicksAndUndo() throws {
    let f = SharedFixture(); defer { f.cleanup() }
    let app = f.access(), widget = f.access()
    let tracker = f.model(app)
    tracker.startChallenge(on: f.now, timeZone: PhoneFixtures.zone)
    let account = try #require(widget.readActive()?.0)
    let failures = ConcurrentFailures()
    DispatchQueue.concurrentPerform(iterations: 40) { index in
        do {
            let accessor = index.isMultiple(of: 2) ? app : widget
            _ = try accessor.transaction(account: account) { current in
                try current.record(.pour(index.isMultiple(of: 2) ? 450 : 250), on: f.now, at: f.now)
                let done = current.challenge!.summary(on: f.now, asOf: f.now).completedHabits.contains(.workout)
                try current.record(.setHabit(.workout, completed: !done), on: f.now, at: f.now)
            }
        } catch { failures.fail() }
    }
    #expect(failures.value == 0)
    #expect(tracker.summary?.waterMillilitres == 0) // intentionally stale app
    tracker.addWater(300)
    #expect(tracker.summary?.waterMillilitres == 14_300)
    #expect(tracker.summary?.completedHabits.contains(.workout) == false)
    _ = try widget.transaction(account: account) { try $0.record(.pour(175), on: f.now, at: f.now) }
    tracker.undoWater() // latest committed custom pour, not the app's cached one
    #expect(tracker.summary?.waterMillilitres == 14_300)
    #expect(tracker.store?.pending.count == 83)
    tracker.reload()
    let ids = tracker.challenge!.allActivities.map(\.id)
    #expect(Set(ids).count == 83)
    let relaunched = f.model(f.access())
    #expect(relaunched.challenge?.allActivities.map(\.id) == ids)
    #expect(relaunched.store?.pending.map(\.id) == tracker.store?.pending.map(\.id))
}

@Test @MainActor func staleTogglesExtrasSettingsImportsAndReadReloadUseFreshHistory() throws {
    let f = SharedFixture(); defer { f.cleanup() }
    let tracker = f.model(f.access()), widget = f.access()
    tracker.startChallenge(on: f.now, timeZone: PhoneFixtures.zone)
    #expect(tracker.addExtra("Stretch") == nil)
    let id = try #require(tracker.activeExtras.first?.id), account = try #require(widget.readActive()?.0)
    _ = try widget.transaction(account: account) { current in
        try current.record(.setHabit(.walk, completed: true), on: f.now, at: f.now)
        try current.record(.setExtra(id: id, completed: true), on: f.now, at: f.now)
    }
    tracker.toggle(.walk); tracker.toggleExtra(id)
    #expect(tracker.summary?.completedHabits.contains(.walk) == false)
    #expect(tracker.summary?.completedExtras.contains(id) == false)
    let backup = try tracker.exportData()
    _ = try widget.transaction(account: account) { try $0.record(.pour(700), on: f.now, at: f.now) }
    #expect(try tracker.previewImport(backup).newCount == 0)
    _ = try tracker.importData(backup)
    #expect(tracker.summary?.waterMillilitres == 700)
    _ = try widget.transaction(account: account) { try $0.record(.archiveExtra(id: id), on: f.now, at: f.now) }
    tracker.toggleExtra(id)
    #expect(tracker.errorMessage != nil)
    #expect(tracker.renameExtra(id, to: "Renamed") != nil)
    tracker.reload()
    #expect(tracker.activeExtras.isEmpty)
    tracker.undoWater()
    let count = tracker.challenge!.allActivities.count
    tracker.undoWater()
    #expect(tracker.errorMessage == nil && tracker.challenge!.allActivities.count == count)
}

@Test @MainActor func signOutAndSwitchRefuseStaleActionsWithoutDeletingDormantHistory() throws {
    let f = SharedFixture(); defer { f.cleanup() }
    let access = f.access(), widget = f.access(), tracker = f.model(access)
    tracker.startChallenge(on: f.now, timeZone: PhoneFixtures.zone); tracker.addWater()
    let before = tracker.challenge!.allActivities, account = try #require(widget.readActive()?.0)
    tracker.activate(ownerID: nil)
    #expect(try widget.readActive() == nil)
    #expect(throws: PhoneSharedStoreError.self) {
        try widget.transaction(account: account) { try $0.record(.pour(450), on: f.now, at: f.now) }
    }
    tracker.activate(ownerID: UUID())
    #expect(tracker.challenge == nil)
    #expect(throws: PhoneSharedStoreError.self) { try widget.transaction(account: account) { _ in } }
    tracker.activate(ownerID: f.owner)
    #expect(tracker.challenge?.allActivities == before)
    #expect(try widget.readActive()?.0.generation != account.generation)
    // A signed-out relaunch invalidates visibility even though the model starts nil.
    let signedOut = TrackerModel(directory: f.root, access: f.access())
    signedOut.activate(ownerID: nil)
    #expect(try widget.readActive() == nil)
}

@Test @MainActor func missingGroupProtectedStorageAndCorruptionNeverBecomeEmptySetup() throws {
    let missing = TrackerModel(access: PhoneSharedStore(root: nil))
    missing.activate(ownerID: UUID())
    #expect(missing.store == nil && missing.errorMessage?.contains("App Group") == true)
    #expect(throws: PhoneSharedStoreError.self) { try PhoneSharedStore(root: nil).readActive() }
    let f = SharedFixture(); defer { f.cleanup() }
    let protected = PhoneSharedStore(root: f.root, available: { false })
    #expect(throws: PhoneSharedStoreError.self) { try protected.readActive() }
    let tracker = f.model(f.access())
    tracker.startChallenge(on: f.now, timeZone: PhoneFixtures.zone)
    let file = f.root.appendingPathComponent("challenge-\(f.owner.uuidString.lowercased()).json")
    let corrupt = Data("corrupt fixture".utf8)
    try corrupt.write(to: file)
    tracker.reload()
    #expect(tracker.store == nil && tracker.errorMessage?.contains("not been reset") == true)
    #expect(try Data(contentsOf: file) == corrupt)
    #expect(throws: (any Error).self) { try f.access().readActive() }
    // A failed account open publishes no cached account/title metadata.
    #expect(throws: (any Error).self) { try f.access().activate(ownerID: f.owner) }
    #expect(try f.access().readActive() == nil)
}

@Test @MainActor func relocationRetainsBytesIDsPendingDeviceAndRecoveryFiles() throws {
    let f = SharedFixture(); defer { f.cleanup() }
    let old = try f.oldStore()
    let file = "challenge-\(f.owner.uuidString.lowercased()).json"
    let original = try Data(contentsOf: f.legacy.appendingPathComponent(file))
    try Data("fixture-ledger".utf8).write(to: f.legacy.appendingPathComponent("celebrations-\(f.owner).json"))
    try original.write(to: f.legacy.appendingPathComponent(file + ".backup-fixture"))
    let model = f.model(f.access(legacy: true))
    #expect(model.store?.record == old.record)
    #expect(model.store?.pending.map(\.id) == old.pending.map(\.id))
    #expect(try Data(contentsOf: f.root.appendingPathComponent(file)) == original)
    #expect(try Data(contentsOf: f.legacy.appendingPathComponent(file)) == original)
    #expect(FileManager.default.fileExists(atPath: f.root.appendingPathComponent(file + ".backup-fixture").path))
    model.addWater()
    let relaunched = f.model(f.access(legacy: true))
    #expect(relaunched.summary?.waterMillilitres == 700)
    let attributes = try FileManager.default.attributesOfItem(atPath: f.root.appendingPathComponent(file).path)
    // Simulator filesystems may omit Data Protection attributes. Protection is
    // chosen explicitly by the repository; real pre-first-unlock acceptance is
    // an owner/device check, separate from the injected unavailable-state test.
    #if targetEnvironment(simulator)
    if let protection = attributes[.protectionKey] as? String {
        #expect(protection == FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
    }
    #else
    #expect(attributes[.protectionKey] as? String == FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
    #endif
}

@Test @MainActor func relocationInterruptionRetriesIdenticalCopiesAndRejectsConflicts() throws {
    let f = SharedFixture(); defer { f.cleanup() }
    let old = try f.oldStore()
    let interrupted = PhoneSharedStore(root: f.root, legacy: f.legacy, afterCopy: { throw URLError(.cancelled) })
    let failed = f.model(interrupted)
    #expect(failed.store == nil && failed.errorMessage != nil)
    #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("relocation-complete.json").path))
    let retried = f.model(f.access(legacy: true))
    #expect(retried.store?.record == old.record && retried.store?.pending.map(\.id) == old.pending.map(\.id))
    let conflict = SharedFixture(); defer { conflict.cleanup() }
    _ = try conflict.oldStore()
    var destination = try ChallengeStore(ownerID: conflict.owner, directory: conflict.root)
    try destination.start(on: conflict.now, timeZone: PhoneFixtures.zone)
    try destination.record(.pour(900), on: conflict.now, at: conflict.now)
    let contents = try destination.exportData()
    let model = conflict.model(conflict.access(legacy: true))
    #expect(model.store == nil && model.errorMessage?.contains("Storage recovery") == true)
    #expect(try ChallengeStore(ownerID: conflict.owner, directory: conflict.root).exportData() == contents)
    #expect(try conflict.access().readActive() == nil)
}

@Test @MainActor func relocationRejectsCorruptLegacyAndChangedOriginalDuringRetry() throws {
    let f = SharedFixture(); defer { f.cleanup() }
    _ = try f.oldStore()
    let interrupted = PhoneSharedStore(root: f.root, legacy: f.legacy, afterCopy: { throw URLError(.cancelled) })
    #expect(f.model(interrupted).store == nil)
    var updated = try ChallengeStore(ownerID: f.owner, directory: f.legacy)
    try updated.record(.pour(99), on: f.now, at: f.now)
    #expect(f.model(f.access(legacy: true)).errorMessage?.contains("Storage recovery") == true)
    let corrupt = SharedFixture(); defer { corrupt.cleanup() }
    _ = try corrupt.oldStore()
    let file = corrupt.legacy.appendingPathComponent("challenge-\(corrupt.owner.uuidString.lowercased()).json")
    try Data("invalid".utf8).write(to: file)
    #expect(corrupt.model(corrupt.access(legacy: true)).store == nil)
    #expect(try Data(contentsOf: file) == Data("invalid".utf8))
}

@MainActor private final class SharedServer: ChallengeTransport {
    var record: ChallengeRecord?
    var events: [ChallengeEvent] = []
    var afterUpload: (() throws -> Void)?
    var switchAccount: (() -> Void)?
    func fetchChallenge(ownerID: UUID) async throws -> ChallengeRecord? { record }
    func insertChallenge(_ record: ChallengeRecord) async throws { self.record = record }
    func upload(_ incoming: [ChallengeEvent], ownerID: UUID) async throws {
        events = incoming.map { ChallengeEvent(ownerID: ownerID, challengeID: $0.challengeID,
                                               activity: $0.activity, receivedAt: PhoneFixtures.now.ISO8601Format()) }
        try afterUpload?()
        switchAccount?()
    }
    func fetchEvents(ownerID: UUID, challengeID: UUID) async throws -> RemoteEvents { .init(events: events) }
}

@Test @MainActor func syncFreshMergeRetainsWidgetEditsAndOnlyFetchedIDsAcknowledge() async throws {
    let f = SharedFixture(); defer { f.cleanup() }
    let tracker = f.model(f.access()), widget = f.access()
    tracker.startChallenge(on: f.now, timeZone: PhoneFixtures.zone); tracker.addWater()
    let account = try #require(widget.readActive()?.0), identity = try #require(tracker.store?.record)
    let server = SharedServer(); server.record = identity
    tracker.configureSync(server)
    server.afterUpload = {
        _ = try widget.transaction(account: account) { try $0.record(.pour(250), on: f.now, at: f.now) }
        // A successful upload still acknowledges nothing that was not fetched.
        server.events = []
    }
    await tracker.sync(force: true)
    #expect(tracker.syncError == nil)
    #expect(tracker.summary?.waterMillilitres == 700)
    #expect(tracker.store?.pending.count == 2)
    server.afterUpload = nil
    await tracker.sync(force: true)
    #expect(tracker.store?.pendingCount == 0 && tracker.store?.record == identity)
    tracker.addWater()
    server.switchAccount = { tracker.activate(ownerID: nil) }
    await tracker.sync(force: true)
    #expect(tracker.store == nil && tracker.ownerID == nil)
    #expect(try widget.readActive() == nil)
    tracker.activate(ownerID: f.owner)
    #expect(tracker.summary?.waterMillilitres == 1150 && tracker.store?.pending.count == 1)
}

@Test @MainActor func phoneFixtureSummaryIsUnchangedByRelocationAndForegroundReloads() throws {
    let f = SharedFixture(); defer { f.cleanup() }
    let defaults = UserDefaults(suiteName: "shared-fixture-\(UUID())")!
    let original = PhoneFixtures.make(.todayExtras, defaults: defaults, directory: f.legacy)
    let owner = try #require(original.tracker.ownerID)
    let model = TrackerModel(directory: f.root, clock: { PhoneFixtures.now }, access: f.access(legacy: true))
    model.activate(ownerID: owner)
    #expect(model.summary?.waterMillilitres == original.tracker.summary?.waterMillilitres)
    #expect(model.summary?.completedHabits == original.tracker.summary?.completedHabits)
    #expect(model.summary?.diet == original.tracker.summary?.diet)
    #expect(model.summary?.extrasDone == original.tracker.summary?.extrasDone)
    #expect(model.summary?.extrasTotal == original.tracker.summary?.extrasTotal)
    #expect(model.summary?.isComplete == original.tracker.summary?.isComplete)
    #expect(model.streaks?.current == original.tracker.streaks?.current)
    #expect(model.streaks?.best == original.tracker.streaks?.best)
    #expect(model.streaks?.milestones == original.tracker.streaks?.milestones)
    #expect(model.store?.record == original.tracker.store?.record)
    #expect(model.store?.pending.map(\.id) == original.tracker.store?.pending.map(\.id))
    let app = PhoneApp(auth: AuthModel(fixtureOwnerID: owner), tracker: model, reminders: nil,
                       defaults: defaults, schedulesRefresh: false)
    let widget = f.access(), account = try #require(widget.readActive()?.0)
    _ = try widget.transaction(account: account) { try $0.record(.pour(222), on: PhoneFixtures.now, at: PhoneFixtures.now) }
    app.becameActive()
    #expect(model.summary?.waterMillilitres == 2472)
}

@Test @MainActor func legacyRelocationMigrationRetriesWithStableGeneratedIdentity() throws {
    struct Legacy: Encodable { let version = 1; let challenge: Challenge }
    let f = SharedFixture(); defer { f.cleanup() }
    try FileManager.default.createDirectory(at: f.legacy, withIntermediateDirectories: true)
    var challenge = Challenge(ownerID: f.owner, startDate: f.now, timeZone: PhoneFixtures.zone)
    try challenge.record(.pour(450), on: f.now, at: f.now)
    let name = "challenge-\(f.owner.uuidString.lowercased()).json"
    let original = try JSONEncoder().encode(Legacy(challenge: challenge))
    try original.write(to: f.legacy.appendingPathComponent(name))
    let interrupted = PhoneSharedStore(root: f.root, legacy: f.legacy, afterCopy: { throw URLError(.cancelled) })
    #expect(f.model(interrupted).store == nil)
    let staged = try ChallengeStore(ownerID: f.owner, directory: f.root.appendingPathComponent("relocation-stage"))
    let retried = f.model(f.access(legacy: true))
    #expect(retried.store?.record == staged.record)
    #expect(retried.store?.pending.map(\.id) == staged.pending.map(\.id))
    #expect(retried.challenge?.allActivities.map(\.id) == challenge.allActivities.map(\.id))
    #expect(try Data(contentsOf: f.legacy.appendingPathComponent(name)) == original)
    #expect(retried.summary?.waterMillilitres == 450)
}

@Test @MainActor func signOutRacingAnActionIsSerializedAndCannotWriteAfterInvalidation() throws {
    let f = SharedFixture(); defer { f.cleanup() }
    let app = f.access(), widget = f.access(), tracker = f.model(app)
    tracker.startChallenge(on: f.now, timeZone: PhoneFixtures.zone)
    let account = try #require(widget.readActive()?.0)
    let failures = ConcurrentFailures()
    DispatchQueue.concurrentPerform(iterations: 2) { index in
        do {
            if index == 0 {
                _ = try app.activate(ownerID: nil)
            } else {
                do {
                    _ = try widget.transaction(account: account) { try $0.record(.pour(450), on: f.now, at: f.now) }
                } catch PhoneSharedStoreError.staleAccount { } // sign-out won the lock
            }
        } catch { failures.fail() }
    }
    #expect(failures.value == 0)
    #expect(try widget.readActive() == nil)
    #expect(throws: PhoneSharedStoreError.self) { try widget.transaction(account: account) { _ in } }
    let retained = try ChallengeStore(ownerID: f.owner, directory: f.root)
    #expect((0...1).contains(retained.pending.count))
}
