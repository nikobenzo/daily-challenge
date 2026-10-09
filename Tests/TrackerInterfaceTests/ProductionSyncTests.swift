import AppKit
import ChallengeCore
import Foundation
import SwiftUI
import Testing
@testable import ChallengeSyncKit
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

// The coordinator's behaviour is tested in ChallengeSyncKitTests/SyncCoordinatorTests.swift;
// this journey also renders the Mac popup at each stage.
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
