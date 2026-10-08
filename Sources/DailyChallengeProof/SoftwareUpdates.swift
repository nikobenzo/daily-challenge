import AppKit
import Sparkle
import SwiftUI

/// Automatic updates through Sparkle. The feed URL and public EdDSA key are
/// written into Info.plist by scripts/build-proof.sh; a bundle without them
/// (an --adhoc build, `swift run`, tests) never starts the updater, because
/// Sparkle would otherwise report a configuration error on every launch.
@MainActor @Observable
final class SoftwareUpdates: NSObject, SPUStandardUserDriverDelegate {
    /// False when this build carries no update feed.
    let isConfigured: Bool
    private(set) var canCheck = false
    /// A version found by a background check that Sparkle left for us to show
    /// (it will not pop a window over another app once launch has passed).
    private(set) var availableVersion: String?
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    /// `updaterDelegate` only observes; scripts/update-fixture.swift uses it to log progress.
    init(bundle: Bundle = .main, updaterDelegate: (any SPUUpdaterDelegate)? = nil) {
        isConfigured = Self.isConfigured(bundle.infoDictionary ?? [:])
        super.init()
        guard isConfigured else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: updaterDelegate, userDriverDelegate: self)
        self.controller = controller
        canCheck = controller.updater.canCheckForUpdates
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            MainActor.assumeIsolated { self?.canCheck = value }
        }
    }

    /// Renders and tests: a configured-looking updater that never starts Sparkle or contacts a feed.
    init(fixtureAvailableVersion: String?) {
        isConfigured = true
        canCheck = true
        availableVersion = fixtureAvailableVersion
        super.init()
    }

    var updater: SPUUpdater? { controller?.updater }

    static func isConfigured(_ info: [String: Any]) -> Bool {
        [info["SUFeedURL"], info["SUPublicEDKey"]].allSatisfy { ($0 as? String)?.isEmpty == false }
    }

    /// The popup is a borderless panel of a Dock-less app, so Sparkle's windows
    /// would open behind the frontmost app unless this app is activated first.
    func checkForUpdates() {
        guard let controller, canCheck else { return }
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    // MARK: SPUStandardUserDriverDelegate

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Near launch Sparkle shows the update itself; later ones wait in Account › About.
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        MainActor.assumeIsolated {
            if handleShowingUpdate {
                NSApp.activate()
            } else {
                availableVersion = version
            }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { availableVersion = nil }
    }

    nonisolated func standardUserDriverWillShowModalAlert() {
        MainActor.assumeIsolated { NSApp.activate() }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { availableVersion = nil }
    }
}

/// The About group's update row in the Account tab.
struct SoftwareUpdateSettings: View {
    let updates: SoftwareUpdates?

    var body: some View {
        if let updates, updates.isConfigured {
            HStack {
                if let version = updates.availableVersion {
                    Label("Version \(version) is available", systemImage: "arrow.down.circle")
                } else {
                    Text("Updates install from inside the app.").foregroundStyle(.secondary)
                }
                Spacer()
                Button(updates.availableVersion == nil ? "Check for updates" : "Install update") {
                    updates.checkForUpdates()
                }
                .disabled(!updates.canCheck)
            }
            .help("Daily Challenge also checks once a day on its own.")
        } else {
            Text("Updates are off in this development build.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
