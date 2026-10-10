import AppKit
import ChallengeCore
import ChallengeSyncKit
import SwiftUI

/// Developer-only verification of the real menu-bar popup (docs/appearance-verification.md#real-popup-probe).
///
/// Ignored unless `DAILY_CHALLENGE_POPUP_PROBE` names a directory, and refused in the
/// production bundle (`app.daily-challenge.proof`), so an installed app never changes
/// behaviour. In probe mode the app runs on offline fixture models kept in that directory
/// (no Supabase client, Keychain, Sparkle, reminders or production data paths), clicks its
/// own status item at launch, writes the popup window's image and geometry to the
/// directory, then quits. The image is the WindowServer's composite of the popup window
/// alone (`screencapture -l`, which draws Liquid Glass) when the launching terminal may
/// record the screen, else the window's own rendering (cacheDisplay, no permission).
/// Optional steps switch sections like the header control, or (`extras`, on Today with no
/// extras) click the slim Extras row so its add field drops down, and record the window
/// and glass frames on every display frame while the height animates, and, with screen
/// recording, a video of the header switcher while its selection moves or of the Extras
/// row while it expands.
///
///     DAILY_CHALLENGE_POPUP_PROBE=<directory>                                  required
///     DAILY_CHALLENGE_POPUP_PROBE_SCREEN=sign-in|setup|today|today-extras|history|account   (today)
///     DAILY_CHALLENGE_POPUP_PROBE_APPEARANCE=light|dark                        (light)
///     DAILY_CHALLENGE_POPUP_PROBE_STEPS=history,account,today|extras           (none)
@MainActor
struct PopupProbe {
    enum Screen: String { case signIn = "sign-in", setup, today, todayExtras = "today-extras", history, account }
    enum Step: Equatable {
        case section(TrackerSection)
        /// Clicks Today's Extras row (the empty-state one drops its add field down).
        case extras

        init?(_ name: Substring) {
            if name.lowercased() == "extras" { self = .extras; return }
            guard let section = TrackerSection.allCases.first(where: { $0.rawValue.lowercased() == name.lowercased() }) else { return nil }
            self = .section(section)
        }
    }

    static let productionBundleID = "app.daily-challenge.proof"
    /// Switches the popup's section (object: TrackerSection) the way the header control does.
    static let selectSection = Notification.Name("DailyChallengePopupProbeSelectSection")
    /// Clicks Today's Extras row header the way a person does (also used by the interface fixtures).
    static let toggleExtrasRow = Notification.Name("DailyChallengePopupProbeToggleExtrasRow")
    static let current = PopupProbe(environment: ProcessInfo.processInfo.environment, bundleID: Bundle.main.bundleIdentifier)
    private static let defaultsSuite = "app.daily-challenge.popup-probe.defaults"

    let directory: URL
    let screen: Screen
    let appearance: AppearancePreference
    let steps: [Step]
    var name: String { "\(screen.rawValue)-\(appearance.rawValue)" }

    init?(environment: [String: String], bundleID: String?) {
        guard let path = environment["DAILY_CHALLENGE_POPUP_PROBE"], !path.isEmpty,
              bundleID != Self.productionBundleID else { return nil }
        directory = URL(fileURLWithPath: path, isDirectory: true)
        screen = environment["DAILY_CHALLENGE_POPUP_PROBE_SCREEN"].flatMap(Screen.init) ?? .today
        appearance = environment["DAILY_CHALLENGE_POPUP_PROBE_APPEARANCE"].flatMap(AppearancePreference.init) ?? .light
        steps = (environment["DAILY_CHALLENGE_POPUP_PROBE_STEPS"] ?? "").split(separator: ",").compactMap(Step.init)
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
        if screen == .todayExtras { Self.seedExtras(tracker) }
        let defaults = UserDefaults(suiteName: Self.defaultsSuite)!
        defaults.removePersistentDomain(forName: Self.defaultsSuite)
        let appearance = AppAppearance(defaults: defaults)
        appearance.preference = self.appearance
        return (auth, tracker, appearance)
    }

    /// Three extras, one ticked: Today's Extras section in the same fixture as the renders.
    static func seedExtras(_ tracker: TrackerModel) {
        for title in ["Stretch for ten minutes", "No phone after 10 pm", "Journal one page"] { _ = tracker.addExtra(title) }
        if let first = tracker.activeExtras.first { tracker.toggleExtra(first.id) }
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
        await record(popup, as: name)
        var previous = section
        for step in steps where step != .section(previous) {
            let label: String
            let video: Process?
            let notification: Notification.Name
            var object: Any?
            switch step {
            case .section(let target):
                label = "\(name)-\(previous.rawValue.lowercased())-to-\(target.rawValue.lowercased())"
                video = recordHeader(popup.panel, to: label)
                notification = Self.selectSection
                object = target
                previous = target
            case .extras:
                label = "\(name)-extras-expanded"
                video = recordExtrasRow(popup.panel, to: label)
                notification = Self.toggleExtrasRow
            }
            // Screen recording takes a moment to start; the change happens inside the video.
            if video != nil { try? await Task.sleep(for: .milliseconds(700)) }
            NotificationCenter.default.post(name: notification, object: object)
            let trace = await Self.trace(popup.panel, seconds: 1.2)
            if let video { await Self.wait(for: video) }
            await record(popup, as: label, trace: trace)
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

    // MARK: Screen capture

    /// Runs /usr/sbin/screencapture; it may record the screen only when the terminal that
    /// launched the probe may (Privacy & Security > Screen Recording).
    private static func screencapture(_ arguments: [String]) -> Process? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x"] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        return process
    }

    private static func wait(for process: Process) async {
        while process.isRunning { try? await Task.sleep(for: .milliseconds(20)) }
    }

    /// The WindowServer's composite of the popup window alone, without its desktop.
    private func captureWindow(_ panel: PopupPanel, to url: URL) async -> NSBitmapImageRep? {
        try? FileManager.default.removeItem(at: url)
        guard let process = Self.screencapture(["-o", "-l\(panel.windowNumber)", url.path]) else { return nil }
        await Self.wait(for: process)
        guard process.terminationStatus == 0, let data = try? Data(contentsOf: url),
              let bitmap = NSBitmapImageRep(data: data), bitmap.pixelsWide > 0 else { return nil }
        return bitmap
    }

    /// A two-second video of the header's section switcher (on the glass, 4 pt around its
    /// track) while a section changes. Only that part of the screen is recorded.
    private func recordHeader(_ panel: PopupPanel, to label: String) -> Process? {
        guard let sheet = panel.glassFrames.first else { return nil }
        let cells = CGFloat(TrackerSection.allCases.count), cell = Theme.Size.segmentCell
        let track = CGSize(width: cells * cell.width + (cells - 1) * 2 + Theme.Size.segmentTrack - cell.height,
                           height: Theme.Size.segmentTrack)
        let switcher = CGRect(x: panel.frame.minX + sheet.maxX - Theme.Size.sectionHorizontal - track.width,
                              y: panel.frame.minY + sheet.maxY - (Theme.Size.headerHeight + track.height) / 2,
                              width: track.width, height: track.height).insetBy(dx: -4, dy: -4)
        return recordScreen(switcher, to: label)
    }

    /// A two-second video of the band of the sheet below the rings (its full width, 230 pt
    /// from just above the Extras row) while the row's add field drops down.
    private func recordExtrasRow(_ panel: PopupPanel, to label: String) -> Process? {
        guard let sheet = panel.glassFrames.first else { return nil }
        let ringsBottom = sheet.maxY - Theme.Size.headerHeight - 1 - Theme.Size.ring - 24 - 2 * (Theme.Size.sectionVertical + 2)
        let band = CGRect(x: panel.frame.minX + sheet.minX, y: panel.frame.minY + ringsBottom - 230,
                          width: sheet.width, height: 230)
        return recordScreen(band, to: label)
    }

    private func recordScreen(_ region: CGRect, to label: String) -> Process? {
        guard let primary = NSScreen.screens.first else { return nil }
        // screencapture -R takes top-left global coordinates.
        let top = primary.frame.maxY - region.maxY
        let url = directory.appendingPathComponent("\(label).mov")
        try? FileManager.default.removeItem(at: url)
        return Self.screencapture(["-v", "-V2", "-R\(Int(region.minX)),\(Int(top)),\(Int(region.width)),\(Int(region.height))", url.path])
    }

    // MARK: Report

    private func record(_ popup: PopupController, as label: String, trace: [[String: Double]]? = nil) async {
        let panel = popup.panel
        guard let root = panel.contentView else { return }
        root.layoutSubtreeIfNeeded()
        let png = directory.appendingPathComponent("\(label).png")
        let capture: String
        let bitmap: NSBitmapImageRep
        if let window = await captureWindow(panel, to: png) {
            capture = "window-server"
            bitmap = window
        } else {
            // cacheDisplay draws neither Liquid Glass nor what the glass samples behind it.
            guard let cached = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
            root.cacheDisplay(in: root.bounds, to: cached)
            try? cached.representation(using: .png, properties: [:])?.write(to: png)
            capture = "cacheDisplay"
            bitmap = cached
        }
        let glass = panel.glassFrames
        let screen = panel.screen ?? NSScreen.main
        var report: [String: Any] = [
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "screen": screen.map { Self.rect($0.frame) } ?? [],
            "visibleFrame": screen.map { Self.rect($0.visibleFrame) } ?? [],
            "statusItem": popup.statusButton?.window.map { Self.rect($0.frame) } ?? [],
            "windowClass": NSStringFromClass(type(of: panel)),
            "capture": capture,
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
