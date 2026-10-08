// Isolated Sparkle update fixture, driven by scripts/test-update-fixture.sh; never part of swift test.
// It runs the app's SoftwareUpdates under its own bundle ID, so no account, Keychain
// item or challenge file is read. Results are appended to result.log beside the bundle.
import AppKit
import Sparkle

@main
enum UpdateFixture {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = FixtureAppDelegate()
            app.delegate = delegate
            app.run()
        }
    }
}

@MainActor
final class FixtureAppDelegate: NSObject, NSApplicationDelegate {
    private let folder = Bundle.main.bundleURL.deletingLastPathComponent()
    private lazy var events = FixtureUpdaterEvents(log: log, foundUpdate: { [weak self] in self?.inspectWindows() })
    private var updates: SoftwareUpdates?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let info = Bundle.main.infoDictionary ?? [:]
        let mode = (try? String(contentsOf: folder.appendingPathComponent("mode"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "interactive"
        log("launched \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?")) mode=\(mode) activationPolicy=\(NSApp.activationPolicy().rawValue)")
        // Silent mode lets Sparkle download, verify and install without a click.
        if mode == "silent" { UserDefaults.standard.set(true, forKey: "SUAutomaticallyUpdate") }
        let updates = SoftwareUpdates(updaterDelegate: events)
        self.updates = updates
        log("configured=\(updates.isConfigured)")
        Task {
            while !updates.canCheck { try? await Task.sleep(for: .milliseconds(100)) }
            if mode == "silent" {
                updates.updater?.checkForUpdatesInBackground()
            } else {
                updates.checkForUpdates()
            }
        }
        // Never leave a fixture running.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.log("timeout")
            exit(2)
        }
    }

    /// Proves Sparkle's update window is on screen although the app has no Dock icon.
    /// Whether it is also frontmost depends on macOS granting activation, which it may
    /// decline while someone is typing in another app, so that is only recorded.
    private func inspectWindows(attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            let shown = NSApp.windows.contains { $0.isVisible && $0.title == "Software Update" }
            guard shown || attempt >= 20 else { return inspectWindows(attempt: attempt + 1) }
            let pid = ProcessInfo.processInfo.processIdentifier
            let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? [])
                .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
            let ids = windows.compactMap { $0[kCGWindowNumber as String] as? Int }
            let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            let titles = NSApp.windows.filter(\.isVisible).map(\.title)
            log("onscreen-windows=\(ids) visible-titles=\(titles) frontmost=\(frontmost) dockIcon=\(NSApp.activationPolicy() == .regular)")
            log("done")
            exit(0)
        }
    }

    private func log(_ line: String) {
        let url = folder.appendingPathComponent("result.log")
        let data = Data("\(Date().formatted(.iso8601)) \(line)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

final class FixtureUpdaterEvents: NSObject, SPUUpdaterDelegate {
    private let log: @MainActor (String) -> Void
    private let foundUpdate: @MainActor () -> Void

    init(log: @escaping @MainActor (String) -> Void, foundUpdate: @escaping @MainActor () -> Void) {
        self.log = log
        self.foundUpdate = foundUpdate
    }

    private func record(_ line: String) { MainActor.assumeIsolated { log(line) } }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        record("found-update \(item.displayVersionString) (\(item.versionString)) url=\(item.fileURL?.absoluteString ?? "-")")
        if !updater.automaticallyDownloadsUpdates { MainActor.assumeIsolated { foundUpdate() } }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        record("no-update \((error as NSError).localizedDescription)")
        DispatchQueue.main.async { exit(0) }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        record("aborted \((error as NSError).domain) \((error as NSError).code) \(error.localizedDescription)")
        if updater.automaticallyDownloadsUpdates { DispatchQueue.main.async { exit(0) } }
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) { record("downloaded \(item.versionString)") }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        // Sparkle validates the EdDSA and code signatures after extraction, before installing.
        record("extracted \(item.versionString)")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) { record("installing \(item.versionString)") }

    func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock: @escaping () -> Void
    ) -> Bool {
        record("install-on-quit \(item.versionString); installing now")
        immediateInstallationBlock()
        return true
    }
}
