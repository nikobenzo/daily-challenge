import AppKit
import ChallengeCore
import Foundation
import Testing
@testable import ChallengeSyncKit
@testable import DailyChallengeProof

/// The first-run welcome window (docs/tracker-interface.md#first-launch). The real
/// windows of a launch, including the empty Settings window regression, are checked by
/// scripts/test-first-launch.sh; these cover the decision behind them.
@MainActor
struct FirstRunTests {
    @Test func newPersonSeesTheMenuBarStepThenTheAccountStep() {
        var state = FirstRunState(sessionRestored: true)
        #expect(state.decision == .show(.menuBar))
        state.openedPopup = true
        #expect(state.decision == .show(.account))
    }

    @Test func nothingIsDecidedBeforeTheSavedSessionIsRead() {
        // Signed out may only mean the Keychain session has not been restored yet.
        #expect(FirstRunState(sessionRestored: false).decision == .wait)
        #expect(FirstRunState(sessionRestored: false, signedIn: false, openedPopup: true).decision == .wait)
    }

    @Test func signedInWithoutAChallengeSeesTheStartDateStep() {
        #expect(FirstRunState(sessionRestored: true, signedIn: true).decision == .show(.startDate))
        #expect(FirstRunState(sessionRestored: true, signedIn: true, openedPopup: true).decision == .show(.startDate))
    }

    @Test func existingUserNeverSeesIt() {
        #expect(FirstRunState(sessionRestored: true, signedIn: true, hasChallenge: true).decision == .finished)
        #expect(FirstRunState(finished: true, sessionRestored: true).decision == .finished)
        #expect(FirstRunState(finished: true, sessionRestored: false).decision == .finished)
    }

    @Test func upgradedInstallWithLocalHistoryNeverSeesIt() {
        // A challenge file on this Mac: decided at once, signed out or not, restored or not.
        #expect(FirstRunState(hasLocalHistory: true, sessionRestored: false).decision == .finished)
        #expect(FirstRunState(hasLocalHistory: true, sessionRestored: true).decision == .finished)
        #expect(FirstRunState(hasLocalHistory: true, sessionRestored: true, signedIn: true).decision == .finished)
    }

    @Test func localHistoryMeansAChallengeFileOfAnyAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(!FirstRunStore.hasLocalHistory(in: directory))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("celebrations-x.json"))
        try Data().write(to: directory.appendingPathComponent("challenge-x.json.backup-1-y"))
        #expect(!FirstRunStore.hasLocalHistory(in: directory))
        try Data().write(to: directory.appendingPathComponent("challenge-\(UUID().uuidString.lowercased()).json"))
        #expect(FirstRunStore.hasLocalHistory(in: directory))
    }

    @Test func finishedIsStoredPerMac() throws {
        let suite = "FirstRunTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FirstRunStore(defaults: defaults)
        #expect(!store.finished)
        store.finished = true
        #expect(FirstRunStore(defaults: defaults).finished)
    }

    @Test func existingUserLaunchOpensNoWindowAndRemembersIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "FirstRunTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let now = ISO8601DateFormatter().date(from: "2026-10-08T12:00:00Z")!
        let owner = UUID()
        let auth = ProofModel(fixtureOwnerID: owner, directory: directory)
        let tracker = TrackerModel(directory: directory, clock: { now })
        tracker.activate(ownerID: owner)
        tracker.startChallenge(on: now, timeZone: Challenge.legacyTimeZone)
        // No popup: a test must not add a status item to the menu bar.
        let welcome = WelcomeController(auth: auth, tracker: tracker, popup: nil, firstRun: FirstRunStore(defaults: defaults),
                                        hasLocalHistory: false)
        welcome.start()
        #expect(welcome.window == nil)
        #expect(welcome.state.decision == .finished)
        #expect(FirstRunStore(defaults: defaults).finished)
    }

    @Test func missingConfigurationCountsAsRestoredWithoutTouchingTheKeychain() {
        // No Configuration.json in the test bundle: no client, so nothing to restore.
        let auth = AuthModel(storage: SessionStorage(keychainService: "FirstRunTests.unused", storageKey: "unused"),
                             bundle: Bundle(for: BundleMarker.self), missingConfiguration: "missing")
        #expect(auth.client == nil)
        #expect(auth.sessionRestored)
        #expect(AuthModel(fixtureOwnerID: nil).sessionRestored)
    }

    @Test func welcomeWindowSitsBesideThePopupUnderTheMenuBar() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 949)
        let size = CGSize(width: 460, height: 700)
        let item = CGRect(x: 1200, y: 949, width: 30, height: 24)
        let frame = WelcomeController.frame(size: size, statusItem: item, visibleFrame: screen)
        #expect(frame.maxX <= item.minX - 24)
        #expect(frame.maxY == screen.maxY - 24)
        #expect(screen.contains(frame))
        // An item far to the left leaves no room beside the popup: centred instead.
        let left = WelcomeController.frame(size: size, statusItem: CGRect(x: 300, y: 949, width: 30, height: 24), visibleFrame: screen)
        #expect(left.midX == screen.midX)
        // No item known: centred, still inside the screen.
        let none = WelcomeController.frame(size: CGSize(width: 460, height: 1200), statusItem: nil, visibleFrame: screen)
        #expect(none.midX == screen.midX && none.minY >= screen.minY)
    }

    @Test func confettiIsOneFiniteBurst() {
        let burst = ConfettiBurst()
        #expect(!burst.pieces.isEmpty)
        // Seeded: every run draws the same burst.
        #expect(ConfettiBurst().pieces.map(\.x) == burst.pieces.map(\.x))
        // Every piece is out by 0.6 s, fades in the last stretch and is gone at the end.
        #expect(burst.pieces.allSatisfy { burst.placement(of: $0, at: 0.6, width: 460) != nil })
        #expect(burst.pieces.allSatisfy { (burst.placement(of: $0, at: ConfettiBurst.duration - 0.05, width: 460)?.opacity ?? 0) < 0.1 })
        #expect(burst.pieces.allSatisfy { burst.placement(of: $0, at: ConfettiBurst.duration, width: 460) == nil })
        #expect(burst.pieces.allSatisfy { burst.placement(of: $0, at: 60, width: 460) == nil })
    }

    @Test func mainMenuKeepsTheEditingShortcuts() {
        // The app has no SwiftUI App (and so no default menu): text fields still need these.
        let menu = AppMenu.make()
        var actions: [String: Selector] = [:]
        for item in menu.items.flatMap({ $0.submenu?.items ?? [] }) where !item.keyEquivalent.isEmpty {
            let shift = item.keyEquivalentModifierMask.contains(.shift) ? "shift-" : ""
            actions[shift + item.keyEquivalent] = item.action
        }
        #expect(actions["x"] == #selector(NSText.cut(_:)))
        #expect(actions["c"] == #selector(NSText.copy(_:)))
        #expect(actions["v"] == #selector(NSText.paste(_:)))
        #expect(actions["a"] == #selector(NSText.selectAll(_:)))
        #expect(actions["z"] == Selector(("undo:")))
        #expect(actions["shift-z"] == Selector(("redo:")))
        #expect(actions["w"] == #selector(NSWindow.performClose(_:)))
        #expect(actions["q"] == #selector(NSApplication.terminate(_:)))
    }
}

private final class BundleMarker {}
