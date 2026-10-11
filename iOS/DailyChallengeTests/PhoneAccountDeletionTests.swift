import ChallengeCore
import ChallengeSyncKit
import Foundation
import Testing
@testable import Daily_Challenge

/// Delete account on the iPhone, on a fake server and temporary App Group and private
/// folders: no real account, Keychain, group container or network.
@MainActor private final class FakeDeletion: AccountDeletionTransport {
    var calls: [UUID] = []
    var failure: (any Error)?
    func deleteAccount(ownerID: UUID) async throws {
        calls.append(ownerID)
        if let failure { throw failure }
    }
}

@MainActor private struct PhoneDeletionFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("phone-deletion-\(UUID())")
    let owner = UUID(), other = UUID()
    let now = Date(timeIntervalSince1970: 1_791_554_400)
    let deletion = FakeDeletion()
    let app: PhoneApp
    var root: URL { directory.appendingPathComponent("group") }
    var legacy: URL { directory.appendingPathComponent("private") }

    init() throws {
        let zone = TimeZone(identifier: "Europe/Jersey")!
        // Before the App Group: this account's history in the app's private folder,
        // and another account's history that must survive.
        let legacy = directory.appendingPathComponent("private")
        var old = try ChallengeStore(ownerID: owner, directory: legacy)
        try old.start(on: now, timeZone: zone)
        try old.record(.pour(250), on: now, at: now)
        var other = try ChallengeStore(ownerID: other, directory: legacy)
        try other.start(on: now, timeZone: zone)
        let auth = AuthModel(fixtureOwnerID: owner, email: "sam@example.invalid")
        auth.accountDeletion = deletion
        let now = now
        let tracker = TrackerModel(directory: directory.appendingPathComponent("group"), clock: { now },
                                   access: PhoneSharedStore(root: directory.appendingPathComponent("group"), legacy: legacy))
        app = PhoneApp(auth: auth, tracker: tracker, reminders: nil,
                       defaults: UserDefaults(suiteName: "phone-deletion-\(UUID())")!, schedulesRefresh: false)
        auth.attachTracker(tracker)
        tracker.addWater()
    }

    /// The widget extension's view: its own accessor on the same group folder.
    var widget: PhoneSharedStore { PhoneSharedStore(root: root) }

    func files(of owner: UUID, in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.lowercased().contains(owner.uuidString.lowercased()) }
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

@Test @MainActor func deletingTheAccountRemovesThisIPhonesCopiesAndSignsTheWidgetsOut() async throws {
    let f = try PhoneDeletionFixture(); defer { f.cleanup() }
    let account = try #require(try f.widget.readActive()?.0)
    #expect(account.ownerID == f.owner)
    #expect(f.app.tracker.summary?.waterMillilitres == 700)
    #expect(try !f.files(of: f.owner, in: f.root).isEmpty)
    #expect(try !f.files(of: f.owner, in: f.legacy).isEmpty)
    f.app.tab = .account

    #expect(await f.app.deleteAccount())
    #expect(f.deletion.calls == [f.owner])
    #expect(f.app.auth.ownerID == nil)
    #expect(f.app.auth.notice == "Your account and all its challenge history have been deleted.")
    #expect(f.app.tab == .today)
    // Widgets read no account (the signed-out state) and refuse a tap rendered before.
    #expect(try f.widget.readActive() == nil)
    #expect(throws: PhoneSharedStoreError.self) {
        _ = try f.widget.transaction(generation: account.generation, challengeID: try #require(account.challengeID)) {
            try $0.record(.pour(450), on: f.now, at: f.now)
        }
    }
    // App Group and private copies, queue included, are gone; the other account's stay.
    #expect(try f.files(of: f.owner, in: f.root).isEmpty)
    #expect(try f.files(of: f.owner, in: f.legacy).isEmpty)
    #expect(try !f.files(of: f.other, in: f.root).isEmpty)
    #expect(try ChallengeStore(ownerID: f.other, directory: f.root).record != nil)
    // Signing in to another account afterwards still opens normally.
    f.app.tracker.activate(ownerID: f.other)
    #expect(f.app.tracker.store?.record != nil)
}

@Test @MainActor func anOfflineDeletionLeavesTheAccountHistoryAndWidgetsAsTheyWere() async throws {
    let f = try PhoneDeletionFixture(); defer { f.cleanup() }
    let before = try f.files(of: f.owner, in: f.root).sorted()
    let pending = f.app.tracker.store?.pendingCount
    f.deletion.failure = URLError(.notConnectedToInternet)

    #expect(!(await f.app.deleteAccount()))
    #expect(f.app.auth.ownerID == f.owner)
    #expect(f.app.auth.errorMessage?.hasPrefix("Your account was not deleted and nothing was removed.") == true)
    #expect(try f.widget.readActive()?.0.ownerID == f.owner)
    #expect(try f.files(of: f.owner, in: f.root).sorted() == before)
    #expect(try !f.files(of: f.owner, in: f.legacy).isEmpty)
    #expect(f.app.tracker.store?.pendingCount == pending)
    f.app.tracker.addWater()
    #expect(f.app.tracker.summary?.waterMillilitres == 1_150)
}
