import AppKit
import SwiftUI
import Testing
@testable import DailyChallengeProof

/// The production root in the production popup panel (PopupPanel). Never ordered on
/// screen; offline fixture auth only. This keeps the popup's geometry from
/// regressing: macOS 27's MenuBarExtra sized its window from the root's minimum size
/// (298 x 10 pt) and filled it with a system backdrop, cutting the sheet on both sides.
@Suite(.serialized) @MainActor
struct PopupResizeTests {
    private let margin = PopupPanel.margin
    private let width = Theme.Size.panelWidth

    private func fixture(_ body: (TrackerModel, ProofModel, AppAppearance, URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "PopupResizeTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let previous = NSApplication.shared.appearance
        defer {
            NSApplication.shared.appearance = previous
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let now = ISO8601DateFormatter().date(from: "2026-10-08T12:00:00Z")!
        let model = TrackerModel(directory: directory, clock: { now })
        let auth = ProofModel(fixtureOwnerID: nil, directory: directory)
        try await body(model, auth, AppAppearance(defaults: defaults), directory)
    }

    private func settle(_ panel: NSPanel, _ seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    /// The minimum size MenuBarExtra sized its window from: it must be the sheet's width.
    @Test func popupRootReportsTheSheetWidth() async throws {
        try await fixture { model, auth, appearance, _ in
            // The window minimum a hosting view derives from the root, as MenuBarExtra's did.
            let host = NSHostingView(rootView: TrackerPopup(model: model, auth: auth, appearance: appearance))
            host.sizingOptions = [.minSize]
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            host.updateConstraintsForSubtreeIfNeeded()
            #expect(abs(window.contentMinSize.width - width) < 0.5, "A zero minimum width let the window shrink to 298 pt")
        }
    }

    @Test func panelIsTransparentAndFitsTheGlassWithoutClipping() async throws {
        try await fixture { model, auth, appearance, directory in
            let panel = PopupPanel(content: TrackerPopup(model: model, auth: auth, appearance: appearance))
            defer { panel.close() }
            panel.setFrameTopLeftPoint(CGPoint(x: 200, y: 1000))
            let top = panel.frame.maxY
            try await settle(panel, 0.4)

            #expect(!panel.isOpaque, "The panel must be transparent outside the glass")
            #expect(panel.backgroundColor == .clear)
            #expect(!panel.hasShadow, "The glass casts its own shadow; a window shadow would lag the animation")
            #expect(panel.foreignMaterials.isEmpty,
                    "No system material may sit behind the glass")
            try expectFitted(panel, top: top, name: "sign-in")

            let host = try #require(panel.contentView)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            func alpha(_ x: CGFloat, _ yFromTop: CGFloat) -> CGFloat {
                bitmap.colorAt(x: Int(x * scale), y: Int(yFromTop * scale))?.alphaComponent ?? 1
            }
            #expect(alpha(margin + 10, 66) > 0.6, "The sheet carries the glass tint")
            #expect(alpha(2, 2) < 0.01 && alpha(host.bounds.width - 2, 2) < 0.01, "Transparent beside the sheet's top corners")
            #expect(alpha(margin + width / 2, host.bounds.height - 2) < 0.01, "Transparent at the bottom of the shadow margin")
            // The shadows fall below the glass, as on the boards: darker under the footer than above the sheet.
            #expect(alpha(margin + width / 2, host.bounds.height - margin + 12) > alpha(margin + width / 2, 2) + 0.02,
                    "The footer's shadow falls below it")

            // Signed in: Today, History and Account keep the full 420 pt sheet (the
            // header with the Day badge once overflowed it by 5 pt).
            let owner = UUID()
            let signedIn = ProofModel(fixtureOwnerID: owner, directory: directory)
            model.activate(ownerID: owner)
            model.startChallenge(on: model.now)
            for section in TrackerSection.allCases {
                let sectionPanel = PopupPanel(content: TrackerPopup(model: model, auth: signedIn, appearance: appearance, section: section))
                defer { sectionPanel.close() }
                sectionPanel.setFrameTopLeftPoint(CGPoint(x: 200, y: 1000))
                try await settle(sectionPanel, 0.4)
                try expectFitted(sectionPanel, top: 1000, name: section.rawValue)
            }
        }
    }

    @Test func panelGrowsBeforeAndShrinksAfterTheAnimatedSheet() async throws {
        try await fixture { model, auth, appearance, _ in
            let panel = PopupPanel(content: TrackerPopup(model: model, auth: auth, appearance: appearance))
            defer { panel.close() }
            panel.setFrameTopLeftPoint(CGPoint(x: 200, y: 1000))
            let top = panel.frame.maxY
            try await settle(panel, 0.4)
            let signInHeight = panel.frame.height

            // Growing: the window is enlarged first, so the animating glass is never clipped.
            auth.authStep = .createAccount
            try await settle(panel, 0.08)
            let grown = panel.frame.height
            #expect(grown > signInHeight, "Create account is taller: the window grows before the animation")
            #expect(abs(panel.frame.maxY - top) < 0.5, "The top edge stays under the menu bar")
            try await settle(panel, 0.5)
            try expectFitted(panel, top: top, name: "create account")

            // Shrinking: the window keeps its height while the glass animates, then fits.
            auth.authStep = .signIn
            try await settle(panel, 0.08)
            #expect(abs(panel.frame.height - grown) < 0.5, "Mid-animation the window still holds the taller glass")
            try await settle(panel, 0.6)
            #expect(abs(panel.frame.height - signInHeight) < 1, "After the animation the window fits the shorter sheet")
            #expect(abs(panel.frame.maxY - top) < 0.5)
            try expectFitted(panel, top: top, name: "sign-in again")
        }
    }

    @Test func panelOpensUnderTheStatusItemInsideTheScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let item = CGRect(x: 900, y: 875, width: 32, height: 25)
        let frame = PopupPanel.frame(contentHeight: 500, anchor: item, visibleFrame: visible)
        #expect(frame.minX + margin == item.minX, "The sheet's left edge is under the item")
        #expect(frame.maxY == visible.maxY, "The window starts at the menu bar")
        #expect(frame.height == Theme.Size.menuBarGap + 500 + margin, "The sheet sits 8 pt under it")
        #expect(frame.width == width + 2 * margin)
        let right = PopupPanel.frame(contentHeight: 500, anchor: CGRect(x: 1400, y: 875, width: 32, height: 25), visibleFrame: visible)
        #expect(right.minX + margin + width == visible.maxX - 8, "Near the right edge the sheet stays on screen")
        let left = PopupPanel.frame(contentHeight: 500, anchor: CGRect(x: -4, y: 875, width: 32, height: 25), visibleFrame: visible)
        #expect(left.minX + margin == 8)
    }

    /// The sheet is 420 pt wide at the panel's top edge, the footer 12 pt under it, and
    /// both lie inside the window with the shadow margin to the sides and below.
    private func expectFitted(_ panel: PopupPanel, top: CGFloat, name: String) throws {
        let glass = panel.glassFrames
        try #require(glass.count == 2, "\(name): one sheet and one footer")
        let (sheet, footer) = (glass[0], glass[1])
        let size = panel.frame.size
        #expect(abs(size.width - (width + 2 * margin)) < 0.5, "\(name): window width")
        #expect(abs(sheet.width - width) < 0.5 && abs(sheet.minX - margin) < 0.5, "\(name): the sheet is 420 pt and uncut")
        #expect(abs(size.height - sheet.maxY - Theme.Size.menuBarGap) < 0.5, "\(name): the sheet starts 8 pt under the window's top edge")
        #expect(abs(sheet.minY - footer.maxY - Theme.Size.footerGap) < 0.5, "\(name): the footer floats 12 pt below")
        // AppKit keeps window heights whole points; a half-point sheet leaves 0.5 pt below.
        #expect(abs(footer.height - Theme.Size.footerHeight) < 0.5 && abs(footer.minY - margin) <= 1, "\(name): the footer is whole")
        #expect(abs(panel.frame.maxY - top) < 0.5, "\(name): top edge anchored")
    }
}
