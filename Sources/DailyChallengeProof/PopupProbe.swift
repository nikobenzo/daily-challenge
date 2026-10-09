import AppKit
import ChallengeCore
import SwiftUI

/// Developer-only verification of the real menu-bar popup (docs/appearance-verification.md#real-popup-probe).
///
/// Ignored unless `DAILY_CHALLENGE_POPUP_PROBE` names a directory, and refused in the
/// production bundle (`app.daily-challenge.proof`), so an installed app never changes
/// behaviour. In probe mode the app runs on offline fixture models kept in that directory
/// (no Supabase client, Keychain, Sparkle, reminders or production data paths), clicks its
/// own status item at launch, writes the popup window's own rendering (cacheDisplay: no
/// screen-recording or accessibility permission) and geometry to the directory, then quits.
/// Optional section steps switch sections like the header control and record the window
/// and glass frames on every display frame while the height animates.
///
///     DAILY_CHALLENGE_POPUP_PROBE=<directory>                                  required
///     DAILY_CHALLENGE_POPUP_PROBE_SCREEN=sign-in|setup|today|history|account   (today)
///     DAILY_CHALLENGE_POPUP_PROBE_APPEARANCE=light|dark                        (light)
///     DAILY_CHALLENGE_POPUP_PROBE_STEPS=history,account,today                  (none)
@MainActor
struct PopupProbe {
    enum Screen: String { case signIn = "sign-in", setup, today, history, account }

    static let productionBundleID = "app.daily-challenge.proof"
    /// Switches the popup's section (object: TrackerSection) the way the header control does.
    static let selectSection = Notification.Name("DailyChallengePopupProbeSelectSection")
    static let current = PopupProbe(environment: ProcessInfo.processInfo.environment, bundleID: Bundle.main.bundleIdentifier)
    private static let defaultsSuite = "app.daily-challenge.popup-probe.defaults"

    let directory: URL
    let screen: Screen
    let appearance: AppearancePreference
    let steps: [TrackerSection]
    var name: String { "\(screen.rawValue)-\(appearance.rawValue)" }

    init?(environment: [String: String], bundleID: String?) {
        guard let path = environment["DAILY_CHALLENGE_POPUP_PROBE"], !path.isEmpty,
              bundleID != Self.productionBundleID else { return nil }
        directory = URL(fileURLWithPath: path, isDirectory: true)
        screen = environment["DAILY_CHALLENGE_POPUP_PROBE_SCREEN"].flatMap(Screen.init) ?? .today
        appearance = environment["DAILY_CHALLENGE_POPUP_PROBE_APPEARANCE"].flatMap(AppearancePreference.init) ?? .light
        steps = (environment["DAILY_CHALLENGE_POPUP_PROBE_STEPS"] ?? "").split(separator: ",")
            .compactMap { step in TrackerSection.allCases.first { $0.rawValue.lowercased() == step.lowercased() } }
    }

    var section: TrackerSection {
        switch screen {
        case .history: .history
        case .account: .account
        default: .today
        }
    }

    /// The same offline fixtures as the committed renders: 8 October 2026 at noon,
    /// Day 1 with 900 ml, in a fresh data folder inside the probe directory.
    func models() -> (auth: ProofModel, tracker: TrackerModel, appearance: AppAppearance) {
        let data = directory.appendingPathComponent("data-\(name)", isDirectory: true)
        try? FileManager.default.removeItem(at: data)
        let now = ISO8601DateFormatter().date(from: "2026-10-08T12:00:00Z")!
        let owner = UUID(uuidString: "0F1C5000-0000-4000-8000-000000000001")!
        let auth = ProofModel(fixtureOwnerID: screen == .signIn ? nil : owner, directory: data)
        let tracker = TrackerModel(directory: data, clock: { now })
        tracker.activate(ownerID: auth.ownerID)
        if screen != .signIn, screen != .setup {
            tracker.startChallenge(on: now, timeZone: Challenge.legacyTimeZone)
            tracker.addWater()
            tracker.addWater()
        }
        let defaults = UserDefaults(suiteName: Self.defaultsSuite)!
        defaults.removePersistentDomain(forName: Self.defaultsSuite)
        let appearance = AppAppearance(defaults: defaults)
        appearance.preference = self.appearance
        return (auth, tracker, appearance)
    }

    // MARK: Run

    func run(_ popup: PopupController) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? await Task.sleep(for: .milliseconds(800))
        // The status item's own action, exactly as a click delivers it.
        popup.statusButton?.performClick(nil)
        try? await Task.sleep(for: .milliseconds(300))
        guard popup.isOpen else { return finish(failure: "Clicking the status item did not open the popup.") }
        try? await Task.sleep(for: .seconds(1.2))
        record(popup, as: name)
        var previous = section
        for step in steps where step != previous {
            NotificationCenter.default.post(name: Self.selectSection, object: step)
            let trace = await Self.trace(popup.panel, seconds: 1.2)
            record(popup, as: "\(name)-\(previous.rawValue.lowercased())-to-\(step.rawValue.lowercased())", trace: trace)
            previous = step
        }
        // Escape closes the popup, as a person would.
        popup.panel.cancelOperation(nil)
        try? await Task.sleep(for: .milliseconds(400))
        finish(failure: popup.isOpen ? "Escape did not close the popup." : nil)
    }

    private func finish(failure: String?) {
        if let failure {
            try? Data((failure + "\n").utf8).write(to: directory.appendingPathComponent("\(name)-FAILED.txt"))
        }
        UserDefaults(suiteName: Self.defaultsSuite)?.removePersistentDomain(forName: Self.defaultsSuite)
        NSApp.terminate(nil)
    }

    /// Window and glass frames about every 8 ms while a section change settles.
    static func trace(_ panel: PopupPanel, seconds: Double) async -> [[String: Double]] {
        let start = Date()
        var samples: [[String: Double]] = []
        while Date().timeIntervalSince(start) < seconds {
            var sample = ["t": Date().timeIntervalSince(start), "windowHeight": panel.frame.height, "windowTop": panel.frame.maxY]
            let glass = panel.glassFrames
            if let sheet = glass.first { sample["sheetHeight"] = sheet.height; sample["sheetTop"] = sheet.maxY }
            if glass.count > 1 { sample["footerTop"] = glass[1].maxY }
            samples.append(sample)
            try? await Task.sleep(for: .milliseconds(8))
        }
        return samples
    }

    // MARK: Report

    private func record(_ popup: PopupController, as label: String, trace: [[String: Double]]? = nil) {
        let panel = popup.panel
        guard let root = panel.contentView else { return }
        root.layoutSubtreeIfNeeded()
        guard let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
        root.cacheDisplay(in: root.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(label).png"))
        let glass = panel.glassFrames
        let screen = panel.screen ?? NSScreen.main
        var report: [String: Any] = [
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "screen": screen.map { Self.rect($0.frame) } ?? [],
            "visibleFrame": screen.map { Self.rect($0.visibleFrame) } ?? [],
            "statusItem": popup.statusButton?.window.map { Self.rect($0.frame) } ?? [],
            "windowClass": NSStringFromClass(type(of: panel)),
            "frame": Self.rect(panel.frame),
            "isOpaque": panel.isOpaque,
            "clearBackground": panel.backgroundColor == .clear,
            "windowShadow": panel.hasShadow,
            "isKey": panel.isKeyWindow,
            "sheet": glass.first.map(Self.rect) ?? [],
            "footer": glass.dropFirst().first.map(Self.rect) ?? [],
            "foreignMaterials": panel.foreignMaterials,
            "pixels": Self.coverage(bitmap, size: root.bounds.size),
        ]
        if let trace { report["trace"] = trace }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("\(label).json"))
        }
    }

    /// In points: the bounding box of pixels with any alpha, and the alpha at the window's corners.
    static func coverage(_ bitmap: NSBitmapImageRep, size: CGSize) -> [String: Any] {
        let width = bitmap.pixelsWide, height = bitmap.pixelsHigh
        let scale = size.width > 0 ? CGFloat(width) / size.width : 1
        func alpha(_ x: Int, _ y: Int) -> Double { Double(bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) }
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) where alpha(x, y) > 0.02 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        func points(_ value: Int) -> Double { Double(CGFloat(value) / scale) }
        return [
            "sizePoints": [Double(size.width), Double(size.height)],
            "coveredBox": [points(minX), points(minY), points(maxX + 1), points(maxY + 1)],
            "cornerAlpha": [alpha(0, 0), alpha(width - 1, 0), alpha(0, height - 1), alpha(width - 1, height - 1)],
        ]
    }

    private static func rect(_ rect: CGRect) -> [Double] { [rect.minX, rect.minY, rect.width, rect.height].map(Double.init) }
}
