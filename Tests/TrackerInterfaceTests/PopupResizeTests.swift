import AppKit
import SwiftUI
import Testing
@testable import DailyChallengeProof

/// The production root in an NSPanel standing in for the MenuBarExtra window, with a
/// foreign system material behind the hosting view. Never ordered on screen; offline
/// fixture auth only. This checks the plumbing; compositing in the real menu-bar popup
/// stays a manual acceptance check (docs/appearance-verification.md).
@Suite(.serialized) @MainActor
struct PopupResizeTests {
    @Test func menuBarPanelIsTransparentAndNeverCutsTheAnimatedSheet() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "PopupResizeTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let previous = NSApplication.shared.appearance
        defer {
            NSApplication.shared.appearance = previous
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let model = TrackerModel(directory: directory)
        let auth = ProofModel(fixtureOwnerID: nil, directory: directory)
        let appearance = AppAppearance(defaults: defaults)

        let panel = NSPanel(contentRect: CGRect(x: 200, y: 200, width: 420, height: 300),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let material = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: 420, height: 300))
        material.autoresizingMask = [.width, .height]
        let host = NSHostingView(rootView: TrackerPopup(model: model, auth: auth, appearance: appearance))
        host.frame = material.bounds
        host.autoresizingMask = [.width, .height]
        material.addSubview(host)
        panel.contentView = material
        let top = panel.frame.maxY

        func settle(_ seconds: TimeInterval) async throws {
            try await Task.sleep(for: .seconds(seconds))
            host.layoutSubtreeIfNeeded()
        }
        func contentHeight() -> CGFloat { panel.contentRect(forFrameRect: panel.frame).height }

        try await settle(0.4)
        #expect(!panel.isOpaque, "The panel must be transparent outside the glass")
        #expect(panel.backgroundColor == .clear)
        #expect(material.maskImage != nil, "A system material behind the glass must be masked out")
        let signInHeight = contentHeight()
        #expect(signInHeight > 300, "The panel fits the sign-in sheet plus footer")
        #expect(abs(panel.frame.maxY - top) < 0.5, "The top edge stays under the menu bar")

        // Growing: the window is enlarged first, so the animating glass is never clipped.
        auth.authStep = .createAccount
        try await settle(0.08)
        let grown = contentHeight()
        #expect(grown > signInHeight, "Create account is taller: the window grows before the animation")
        #expect(abs(panel.frame.maxY - top) < 0.5)

        // Shrinking: the window keeps its height while the glass animates, then fits.
        auth.authStep = .signIn
        try await settle(0.08)
        #expect(abs(contentHeight() - grown) < 0.5, "Mid-animation the window still holds the taller glass")
        try await settle(0.6)
        #expect(abs(contentHeight() - signInHeight) < 1, "After the animation the window fits the shorter sheet")
        #expect(abs(panel.frame.maxY - top) < 0.5)
    }
}
