import AppKit
import ChallengeCore
import Foundation
import SwiftUI
import Testing
@testable import DailyChallengeProof

@MainActor private final class FixtureServer: ChallengeTransport {
    var headers: [UUID: ChallengeRecord] = [:]
    var events: [UUID: [UUID: ChallengeEvent]] = [:]
    var unavailable = false
    var loseUploadResponse = false
    var requests = 0
    var fetchHook: (() -> Void)?
    var eventsHook: (() -> Void)?
    let now = Date(timeIntervalSince1970: 1_791_460_800)
    func check() throws { requests += 1; if unavailable { throw URLError(.notConnectedToInternet) } }
    func fetchChallenge(ownerID: UUID) async throws -> ChallengeRecord? {
        try check()
        let hook = fetchHook; fetchHook = nil; hook?()
        return headers[ownerID]
    }
    func insertChallenge(_ record: ChallengeRecord) async throws {
        try check()
        if headers[record.ownerID] == nil { headers[record.ownerID] = record }
    }
    func upload(_ incoming: [ChallengeEvent], ownerID: UUID) async throws {
        try check()
        for event in incoming {
            #expect(event.ownerID == ownerID)
            if events[ownerID]?[event.id] == nil {
                events[ownerID, default: [:]][event.id] = ChallengeEvent(ownerID: ownerID, challengeID: event.challengeID,
                    activity: event.activity, receivedAt: now.ISO8601Format())
            }
        }
        if loseUploadResponse { throw URLError(.networkConnectionLost) }
    }
    func fetchEvents(ownerID: UUID, challengeID: UUID) async throws -> RemoteEvents {
        try check()
        let result = Array(events[ownerID, default: [:]].values)
        let hook = eventsHook; eventsHook = nil; hook?()
        return .init(events: result)
    }
}

@MainActor private struct SyncFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let owner = UUID()
    let server = FixtureServer()
    func model(ownerID: UUID? = nil, directory: URL? = nil) -> TrackerModel {
        let model = TrackerModel(directory: directory ?? self.directory, clock: { server.now })
        model.configureSync(server)
        model.activate(ownerID: ownerID ?? owner)
        return model
    }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

@Test @MainActor func importedHistoryUsesNormalSyncAndRejectsAccountSwitch() async throws {
    let fixture = SyncFixture(); defer { fixture.cleanup() }
    let model = fixture.model()
    await model.sync()
    model.startChallenge(on: fixture.server.now)
    await model.sync(force: true)
    let record = try #require(model.store?.record)
    var source = try #require(model.challenge)
    try source.record(.pour(450), on: fixture.server.now, at: fixture.server.now, deviceID: "export-fixture")
    let data = try ChallengeBackup(settings: record, activities: source.allActivities).encoded()
    #expect(try model.previewImport(data).newCount == 1)
    try model.importData(data)
    #expect(model.summary?.waterMillilitres == 450)
    #expect(model.store?.pendingCount == 1)
    fixture.server.loseUploadResponse = true
    await model.sync(force: true)
    #expect(model.store?.pendingCount == 1)
    fixture.server.loseUploadResponse = false
    await model.sync(force: true)
    #expect(model.store?.pendingCount == 0)
    #expect(fixture.server.events[fixture.owner]?.count == 1)
    try model.importData(data)
    #expect(model.store?.pendingCount == 0)
    model.activate(ownerID: UUID())
    await model.sync(force: true)
    model.startChallenge(on: fixture.server.now)
    #expect(throws: (any Error).self) { try model.importData(data) }
    #expect(model.challenge?.allActivities.isEmpty == true)
}

@Test @MainActor func productionSetupRequiresReachableServerAndAdoptsExistingChallenge() async throws {
    let fixture = SyncFixture(); defer { fixture.cleanup() }
    let model = fixture.model()
    model.startChallenge(on: fixture.server.now)
    #expect(model.challenge == nil)
    fixture.server.unavailable = true
    await model.sync()
    #expect(!model.canStartChallenge && model.syncError != nil)
    fixture.server.unavailable = false
    let header = ChallengeRecord(ownerID: fixture.owner, startDate: Challenge(ownerID: fixture.owner, startDate: fixture.server.now).startDate)
    fixture.server.headers[fixture.owner] = header
    await model.sync(force: true)
    #expect(model.store?.record == header)
    #expect(model.store?.pendingCount == 0)
    #expect(model.syncError == nil)
}

@Test @MainActor func pendingRelaunchLostResponseRetryAndBackendFailureNeverLoseEntries() async throws {
    let fixture = SyncFixture(); defer { fixture.cleanup() }
    let model = fixture.model()
    await model.sync()
    #expect(model.canStartChallenge)
    model.startChallenge(on: fixture.server.now)
    model.addWater(); model.addWater()
    fixture.server.unavailable = true
    await model.sync(force: true)
    #expect(model.summary?.waterMillilitres == 900)
    #expect(model.store?.pendingCount == 3)
    #expect(model.syncStatus.contains("pending"))
    let calls = fixture.server.requests
    await model.sync() // respects backoff
    #expect(fixture.server.requests == calls)
    let relaunched = fixture.model()
    #expect(relaunched.summary?.waterMillilitres == 900)
    fixture.server.unavailable = false
    fixture.server.loseUploadResponse = true
    await relaunched.sync(force: true)
    #expect(fixture.server.events[fixture.owner]?.count == 2)
    #expect(relaunched.store?.pendingCount == 3)
    fixture.server.loseUploadResponse = false
    await relaunched.sync(force: true)
    #expect(fixture.server.events[fixture.owner]?.count == 2)
    #expect(relaunched.store?.pendingCount == 0)
    #expect(relaunched.syncStatus.hasPrefix("Synced"))
}

@Test @MainActor func accountSwitchDuringAwaitDiscardsStaleResponseAndNeverRelabelsQueue() async throws {
    let fixture = SyncFixture(); defer { fixture.cleanup() }
    let model = fixture.model()
    await model.sync()
    model.startChallenge(on: fixture.server.now); model.addWater()
    let other = UUID()
    fixture.server.fetchHook = { model.activate(ownerID: other) }
    await model.sync(force: true)
    #expect(model.ownerID == other && model.challenge == nil)
    #expect(fixture.server.headers[fixture.owner] == nil)
    #expect(fixture.server.events[other] == nil)
    model.activate(ownerID: nil)
    #expect(model.store == nil)
    model.activate(ownerID: fixture.owner)
    #expect(model.summary?.waterMillilitres == 450)
    #expect(model.store?.pendingCount == 2)
    await model.sync(force: true)
    #expect(fixture.server.events[fixture.owner]?.count == 1)
    #expect(fixture.server.events[other] == nil)
}

@Test @MainActor func independentOfflineMacsConvergeHistoryAndStreaksThroughCoordinator() async throws {
    let fixture = SyncFixture(); defer { fixture.cleanup() }
    let a = fixture.model()
    let bDirectory = fixture.directory.appendingPathComponent("MacB")
    let b = fixture.model(directory: bDirectory)
    await a.sync(); a.startChallenge(on: fixture.server.now); a.addWater()
    await a.sync(force: true); await b.sync(force: true)
    fixture.server.unavailable = true
    a.addCustomWater("4000"); b.addCustomWater("300")
    a.toggle(.workout); a.toggle(.walk); a.toggle(.bibleReading); a.setDiet(.clean)
    await a.sync(force: true); await b.sync(force: true)
    fixture.server.unavailable = false
    await b.sync(force: true); await a.sync(force: true); await b.sync(force: true)
    #expect(a.challenge?.allActivities == b.challenge?.allActivities)
    #expect(a.summary?.waterMillilitres == 4750)
    #expect(a.streaks?.current == 1 && b.streaks?.current == 1)
    #expect(a.streaks?.best == b.streaks?.best)
    #expect(a.streaks?.milestones == b.streaks?.milestones)
    #expect(a.store?.pendingCount == 0 && b.store?.pendingCount == 0)
}

@Test @MainActor func racedSetupStopsSyncWithoutReplacingEitherHistory() async throws {
    let fixture = SyncFixture(); defer { fixture.cleanup() }
    let a = fixture.model(), b = fixture.model(directory: fixture.directory.appendingPathComponent("MacB"))
    await a.sync(); await b.sync()
    a.startChallenge(on: fixture.server.now); a.addWater()
    b.startChallenge(on: fixture.server.now.addingTimeInterval(-86400)); b.addCustomWater("900")
    await a.sync(force: true); await b.sync(force: true)
    #expect(b.syncError?.contains("Different challenges") == true)
    #expect(b.summary?.waterMillilitres == 900)
    #expect(a.summary?.waterMillilitres == 450)
    #expect(b.store?.pendingCount == 2)
    #expect(fixture.server.headers[fixture.owner] == a.store?.record)
    #expect(fixture.server.events[fixture.owner]?.count == 1)
}

/// Exercises the captain's legacy 900 ml journey through the UI coordinator.
/// Optional artifacts contain only generated fixture history and in-process popup renders.
@Test @MainActor func legacy900mlMigratesAndOfflineCorrectionsConvergeWithVisibleSyncStates() async throws {
    struct Legacy: Encodable { let version = 1; let challenge: Challenge }
    struct Observation: Encodable {
        let stage: String
        let water: Int?
        let pending: Int?
        let status: String
        let currentStreak: Int?
        let bestStreak: Int?
        let activityIDs: [UUID]
    }
    let fixture = SyncFixture(); defer { fixture.cleanup() }
    let now = fixture.server.now
    try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
    var legacy = Challenge(ownerID: fixture.owner, startDate: now)
    try legacy.record(.pour(450), on: now, at: now.addingTimeInterval(-2))
    try legacy.record(.pour(450), on: now, at: now.addingTimeInterval(-1))
    let filename = "challenge-\(fixture.owner.uuidString.lowercased()).json"
    let legacyBytes = try JSONEncoder().encode(Legacy(challenge: legacy))
    try legacyBytes.write(to: fixture.directory.appendingPathComponent(filename))
    let output = ProcessInfo.processInfo.environment["DAILY_CHALLENGE_SYNC_EVIDENCE_DIR"].map { URL(fileURLWithPath: $0) }
    if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
    var observations: [Observation] = []
    func observe(_ model: TrackerModel, _ stage: String) throws {
        observations.append(Observation(stage: stage, water: model.summary?.waterMillilitres,
            pending: model.store?.pendingCount, status: model.syncStatus,
            currentStreak: model.streaks?.current, bestStreak: model.streaks?.best,
            activityIDs: model.challenge?.allActivities.map(\.id) ?? []))
        guard let output else { return }
        let previous = NSApplication.shared.appearance
        defer { NSApplication.shared.appearance = previous }
        // No preference writes, production Keychain, or displayed app windows.
        let appearance = AppAppearance(defaults: UserDefaults(suiteName: "sync-render-\(UUID())")!)
        let auth = ProofModel(fixtureOwnerID: fixture.owner, directory: fixture.directory)
        // cacheDisplay cannot draw Liquid Glass and drops what it samples; draw it flat.
        let host = NSHostingView(rootView: TrackerPopup(model: model, auth: auth, appearance: appearance)
            .environment(\.trackerLiquidGlassOverride, false))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 640),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        window.setContentSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("\(stage).png"))
    }
    let a = fixture.model()
    #expect(a.challenge?.startDate == legacy.startDate)
    #expect(a.summary?.waterMillilitres == 900 && a.store?.pendingCount == 3)
    let backups = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.contains(".backup-") }
    #expect(backups.count == 1)
    #expect(try Data(contentsOf: #require(backups.first)) == legacyBytes)
    try observe(a, "01-migrated-pending-900ml")
    await a.sync(force: true)
    let bDirectory = fixture.directory.appendingPathComponent("MacB")
    let b = fixture.model(directory: bDirectory)
    await b.sync(force: true)
    #expect(b.challenge?.startDate == legacy.startDate)
    #expect(b.summary?.waterMillilitres == 900)
    #expect(a.challenge?.allActivities == b.challenge?.allActivities)
    fixture.server.unavailable = true
    a.undoWater(); b.undoWater() // both target the same shared 450 ml pour
    a.addCustomWater("200"); b.addCustomWater("300")
    await a.sync(force: true); await b.sync(force: true)
    #expect(a.syncError != nil && b.syncError != nil)
    try observe(a, "02-offline-error-local-650ml")
    // Stop using the old models as writers; reopen each account's durable queue.
    let reopenedA = fixture.model(), reopenedB = fixture.model(directory: bDirectory)
    #expect(reopenedA.summary?.waterMillilitres == 650)
    #expect(reopenedB.summary?.waterMillilitres == 750)
    #expect(reopenedA.store?.pendingCount == 2 && reopenedB.store?.pendingCount == 2)
    fixture.server.unavailable = false
    fixture.server.loseUploadResponse = true
    await reopenedA.sync(force: true)
    #expect(reopenedA.store?.pendingCount == 2)
    fixture.server.loseUploadResponse = false
    await reopenedA.sync(force: true); await reopenedB.sync(force: true); await reopenedA.sync(force: true)
    #expect(reopenedA.summary?.waterMillilitres == 950 && reopenedB.summary?.waterMillilitres == 950)
    #expect(reopenedA.challenge?.allActivities == reopenedB.challenge?.allActivities)
    #expect(fixture.server.events[fixture.owner]?.count == 6)
    reopenedA.addCustomWater("4000")
    reopenedA.toggle(.workout); reopenedA.toggle(.walk); reopenedA.toggle(.bibleReading); reopenedA.setDiet(.clean)
    await reopenedA.sync(force: true); await reopenedB.sync(force: true)
    #expect(reopenedA.summary?.waterMillilitres == 4950 && reopenedB.summary?.waterMillilitres == 4950)
    #expect(reopenedA.streaks?.current == 1 && reopenedB.streaks?.current == 1)
    #expect(reopenedA.streaks?.best == reopenedB.streaks?.best)
    #expect(reopenedA.challenge?.allActivities == reopenedB.challenge?.allActivities)
    #expect(reopenedA.store?.pendingCount == 0 && reopenedB.store?.pendingCount == 0)
    #expect(reopenedA.syncStatus.hasPrefix("Synced") && reopenedB.syncStatus.hasPrefix("Synced"))
    try observe(reopenedA, "03-mac-a-synced")
    try observe(reopenedB, "04-mac-b-synced")
    if let output {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(observations).write(to: output.appendingPathComponent("fixture-journey.json"))
        for (name, directory) in [("mac-a-persisted.json", fixture.directory), ("mac-b-persisted.json", bDirectory)] {
            try Data(contentsOf: directory.appendingPathComponent(filename)).write(to: output.appendingPathComponent(name))
        }
        try legacyBytes.write(to: output.appendingPathComponent("legacy-backup.json"))
    }
}

@Test @MainActor func editsDuringNetworkWaitRemainPendingUntilExactServerConfirmation() async throws {
    let fixture = SyncFixture(); defer { fixture.cleanup() }
    let model = fixture.model()
    await model.sync(); model.startChallenge(on: fixture.server.now); model.addWater()
    fixture.server.eventsHook = { model.addCustomWater("250") }
    await model.sync(force: true)
    #expect(model.summary?.waterMillilitres == 700)
    #expect(fixture.server.events[fixture.owner]?.count == 1)
    #expect(model.store?.pendingCount == 1)
    await model.sync(force: true)
    #expect(fixture.server.events[fixture.owner]?.count == 2)
    #expect(model.store?.pendingCount == 0)
}
