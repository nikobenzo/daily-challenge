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

/// The About row's update state: an amber version chip and Install when an update is
/// waiting, otherwise a check-for-updates icon. The wrench sits after it in AccountView.
struct SoftwareUpdateSettings: View {
    let updates: SoftwareUpdates?

    var body: some View {
        if let updates, updates.isConfigured {
            if let version = updates.availableVersion {
                Badge(symbol: "arrow.down.circle", text: version, fill: Theme.amberTint, foreground: Theme.amberText, height: 30)
                    .help("Version \(version) is available")
                    .accessibilityLabel("Version \(version) is available")
                Spacer(minLength: 4)
                Button("Install") { updates.checkForUpdates() }
                    .buttonStyle(PrimaryPillStyle(height: 36, expands: false))
                    .disabled(!updates.canCheck)
                    .help("Install update. Daily Challenge also checks once a day on its own.")
                    .accessibilityLabel("Install update")
            } else {
                Spacer(minLength: 4)
                Button { updates.checkForUpdates() } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                    .buttonStyle(RoundIconStyle(size: 36))
                    .disabled(!updates.canCheck)
                    .help("Check for updates. Updates install from inside the app; it also checks once a day on its own.")
                    .accessibilityLabel("Check for updates")
            }
        } else {
            Badge(symbol: "slash.circle", text: "Updates off", foreground: Theme.textTertiary, height: 30)
                .help("Updates are off in this development build.")
                .accessibilityLabel("Updates are off in this development build.")
            Spacer(minLength: 4)
        }
    }
}
