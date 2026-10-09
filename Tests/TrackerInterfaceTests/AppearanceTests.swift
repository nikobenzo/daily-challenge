import AppKit
import ChallengeCore
import SwiftUI
import Testing
@testable import DailyChallengeProof

@Suite(.serialized) @MainActor
struct AppearanceTests {
    private func withPreferences(_ body: (AppAppearance, UserDefaults) throws -> Void) throws {
        let suite = "appearance-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let previous = NSApplication.shared.appearance
        defer {
            NSApplication.shared.appearance = previous
            defaults.removePersistentDomain(forName: suite)
        }
        try body(AppAppearance(defaults: defaults), defaults)
    }

    @Test func preferencePersistenceAndLiveNativeMapping() throws {
        try withPreferences { model, defaults in
            #expect(model.preference == .system)
            #expect(NSApplication.shared.appearance == nil)
            for preference in AppearancePreference.allCases {
                model.preference = preference
                #expect(defaults.string(forKey: AppAppearance.storageKey) == preference.rawValue)
                #expect(NSApplication.shared.appearance?.name == preference.appearance(increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)?.name)
                #expect(AppAppearance(defaults: defaults).preference == preference)
            }
            #expect(AppearancePreference.light.appearanceName(increasedContrast: true) == .accessibilityHighContrastAqua)
            #expect(AppearancePreference.dark.appearanceName(increasedContrast: true) == .accessibilityHighContrastDarkAqua)
            #expect(AppearancePreference.system.appearance(increasedContrast: true) == nil)
            defaults.set("invalid", forKey: AppAppearance.storageKey)
            #expect(AppAppearance(defaults: defaults).preference == .system)
            #expect(NSApplication.shared.appearance == nil)
        }
    }

    /// Uses the production root and native application appearance, NOT a test-added
    /// solid background or a forced SwiftUI colorScheme. No real auth/data access.
    /// These never-shown windows draw Liquid Glass controls flat (`trackerLiquidGlassOverride`):
    /// cacheDisplay cannot draw the glass and drops everything it samples.
    /// The popup is a glass sheet plus a detached footer in a transparent window: the
    /// sheet must carry the adaptive glass tint (legible without any desktop blur) and
    /// everything outside the glass must be fully transparent, never a half-filled band.
    @Test func productionPopupSurfacesHaveAdaptiveGlass() throws {
        try withPreferences { appearance, _ in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let owner = UUID()
            let now = ISO8601DateFormatter().date(from: "2026-10-08T12:00:00Z")!
            let model = TrackerModel(directory: directory, clock: { now })
            model.activate(ownerID: owner)
            let auth = ProofModel(fixtureOwnerID: owner, directory: directory)
            let signedOut = ProofModel(fixtureOwnerID: nil, directory: directory)
            // Setup with an injected zone, so the render does not depend on this Mac's.
            try renderLiveModes(
                TrackerView(model: model, auth: auth, setupTimeZone: TimeZone(identifier: "America/New_York")!)
                    .environment(appearance)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top),
                name: "setup-new-york", appearance: appearance
            )
            let york = TimeZone(identifier: "America/New_York")!
            try renderLiveModes(TimeZoneList(selection: .constant(york), now: now, done: {}),
                                name: "time-zone-list", appearance: appearance, surface: .opaque)
            try renderLiveModes(TimeZoneList(selection: .constant(york), now: now, done: {}, query: "syd"),
                                name: "time-zone-search", appearance: appearance, surface: .opaque)
            for setup in [true, false] {
                if !setup {
                    model.startChallenge(on: now)
                    model.addWater()
                    model.addWater()
                }
                for section in TrackerSection.allCases where !setup || section == .today {
                    if section == .history { model.selectHistoryDay(now) }
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .sortedKeys
                    let before = try encoder.encode(model.challenge)
                    try renderLiveModes(
                        TrackerPopup(model: model, auth: auth, appearance: appearance, section: section),
                        name: setup ? "setup" : section.rawValue.lowercased(), appearance: appearance
                    )
                    #expect(try encoder.encode(model.challenge) == before)
                }
            }
            // Enough activity that History's capped Activity list scrolls.
            model.showToday()
            for _ in 0..<4 { model.addWater() }
            try renderRetainedWindowTransitions(model: model, auth: auth, appearance: appearance)
            model.enableCorrections()
            try renderLiveModes(TrackerPopup(model: model, auth: auth, appearance: appearance, section: .history), name: "history-editing", appearance: appearance)
            model.showToday()
            model.addCustomWater("3600")
            try renderLiveModes(TrackerPopup(model: model, auth: auth, appearance: appearance), name: "today-overflow", appearance: appearance)
            try renderLiveModes(TrackerPopup(model: model, auth: signedOut, appearance: appearance), name: "sign-in", appearance: appearance)
            try renderLiveModes(CustomPourView(amount: .constant(""), cancel: {}, submit: {}), name: "custom-disabled", appearance: appearance, surface: .opaque)
            try renderLiveModes(CustomPourView(amount: .constant("250"), cancel: {}, submit: {}), name: "custom-enabled", appearance: appearance, surface: .opaque)
        }
    }

    /// Every signed-out auth screen on the production root, Light and Dark. Offline
    /// fixtures only: no SDK client, Keychain, network or real account.
    @Test func signedOutAuthScreensHaveAdaptiveGlass() throws {
        try withPreferences { appearance, _ in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let now = ISO8601DateFormatter().date(from: "2026-10-08T12:00:00Z")!
            let model = TrackerModel(directory: directory, clock: { now })
            let address = "friend@example.com"
            let screens: [(String, ProofModel)] = [
                ("auth-sign-in", ProofModel(fixtureOwnerID: nil, directory: directory)),
                ("auth-create-account", ProofModel(fixtureOwnerID: nil, directory: directory, authStep: .createAccount)),
                ("auth-forgot-password", ProofModel(fixtureOwnerID: nil, directory: directory, authStep: .forgotPassword)),
                ("auth-confirm-code", ProofModel(
                    fixtureOwnerID: nil, directory: directory, authStep: .confirmSignUp(email: address),
                    notice: "We emailed a code to \(address). Enter it to finish creating your account.",
                    resendAvailableAt: Date().addingTimeInterval(42)
                )),
                ("auth-confirm-expired", ProofModel(
                    fixtureOwnerID: nil, directory: directory, authStep: .confirmSignUp(email: address),
                    errorMessage: "That code is wrong or has expired. Check the latest email, or request a new code."
                )),
                ("auth-reset-password", ProofModel(
                    fixtureOwnerID: nil, directory: directory, authStep: .resetPassword(email: address),
                    notice: "If \(address) has an account, we emailed it a code. Enter it with your new password.",
                    resendAvailableAt: Date().addingTimeInterval(42)
                )),
                ("auth-reset-not-saved", ProofModel(
                    fixtureOwnerID: nil, directory: directory, authStep: .forgotPassword,
                    errorMessage: "The password reset was interrupted and your new password was not saved. Start again to get a new code."
                )),
                ("auth-account-exists", ProofModel(
                    fixtureOwnerID: nil, directory: directory,
                    errorMessage: "An account with this email already exists, try signing in."
                ))
            ]
            for (name, auth) in screens {
                if auth.authStep != .forgotPassword || name == "auth-reset-not-saved" {
                    auth.email = name == "auth-sign-in" ? "" : address
                }
                if name == "auth-create-account" {
                    // Too short and no confirmation yet: the render shows the new-password rule.
                    auth.password = "secret-1"
                }
                if name == "auth-reset-password" { auth.code = "12345678" }
                try renderLiveModes(TrackerPopup(model: model, auth: auth, appearance: appearance), name: name, appearance: appearance)
                #expect(auth.ownerID == nil)
            }
        }
    }

    /// The header switcher marks the selected section, and only it, in Light and Dark: its
    /// cell is lighter than the translucent track under the other cells. Production root,
    /// drawn with the flat fallback, since cacheDisplay cannot draw Liquid Glass.
    @Test func sectionSwitcherMarksTheSelectedSection() throws {
        try withPreferences { appearance, _ in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let owner = UUID()
            let now = ISO8601DateFormatter().date(from: "2026-10-08T12:00:00Z")!
            let model = TrackerModel(directory: directory, clock: { now })
            model.activate(ownerID: owner)
            model.startChallenge(on: now)
            let auth = ProofModel(fixtureOwnerID: owner, directory: directory)
            // The track's right edge sits at the header's right padding; cells are 44 pt
            // with 2 pt gaps inside 3 pt of track padding. Sample beside each glyph.
            let cell = Theme.Size.segmentCell
            let inset = (Theme.Size.segmentTrack - cell.height) / 2
            let sections = TrackerSection.allCases
            let trackWidth = CGFloat(sections.count) * cell.width + CGFloat(sections.count - 1) * 2 + 2 * inset
            let trackMinX = Theme.Size.panelWidth - Theme.Size.sectionHorizontal - trackWidth
            func samplePoint(_ index: Int) -> CGPoint {
                CGPoint(x: trackMinX + inset + CGFloat(index) * (cell.width + 2) + 9, y: Theme.Size.headerHeight / 2 + 8)
            }
            for preference in [AppearancePreference.light, .dark] {
                appearance.preference = preference
                for (selectedIndex, section) in sections.enumerated() {
                    let host = NSHostingView(rootView: TrackerPopup(model: model, auth: auth, appearance: appearance, section: section)
                        .environment(\.trackerLiquidGlassOverride, false))
                    host.sizingOptions = [.intrinsicContentSize]
                    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 640), styleMask: .borderless, backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.contentView = host
                    defer { window.close() }
                    window.setContentSize(host.fittingSize)
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
                    let brightness = try sections.indices.map { index in
                        let point = samplePoint(index)
                        let pixel = try #require(bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.usingColorSpace(.deviceRGB))
                        return (pixel.redComponent + pixel.greenComponent + pixel.blueComponent) / 3
                    }
                    let name = "\(section.rawValue)-\(preference.rawValue)"
                    for index in sections.indices where index != selectedIndex {
                        #expect(brightness[selectedIndex] > brightness[index] + 0.03,
                                "\(name): the selected cell must carry the indicator, not cell \(index) (\(brightness))")
                    }
                    let others = sections.indices.filter { $0 != selectedIndex }.map { brightness[$0] }
                    #expect(abs(others[0] - others[1]) < 0.02, "\(name): unselected cells show only the track (\(brightness))")
                }
            }
        }
    }

    @Test func switcherIndicatorUsesLiquidGlassUnlessTransparencyIsReduced() {
        typealias Indicator = IconSegmented<TrackerSection>.Indicator
        #expect(Indicator.resolve(liquidGlassAvailable: true, reduceTransparency: false, liquidGlassOverride: nil) == .glass)
        #expect(Indicator.resolve(liquidGlassAvailable: true, reduceTransparency: true, liquidGlassOverride: nil) == .opaque)
        #expect(Indicator.resolve(liquidGlassAvailable: false, reduceTransparency: false, liquidGlassOverride: nil) == .opaque)
        #expect(Indicator.resolve(liquidGlassAvailable: true, reduceTransparency: false, liquidGlassOverride: false) == .flat)
        #expect(Indicator.resolve(liquidGlassAvailable: true, reduceTransparency: true, liquidGlassOverride: false) == .opaque)
    }

    private enum Surface { case glass, opaque }

    private func assertFilledEdges(_ bitmap: NSBitmapImageRep, name: String) {
        // Standalone popovers keep an opaque themed surface to every edge.
        for y in [0, 1, bitmap.pixelsHigh - 2, bitmap.pixelsHigh - 1] {
            let filled = (0..<bitmap.pixelsWide).allSatisfy { x in
                (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.99
            }
            #expect(filled, "\(name): unfilled edge at row \(y)")
        }
    }

    /// A point on the glass inside the sheet: left padding, just under the header hairline.
    private func glassPixel(_ bitmap: NSBitmapImageRep, host: NSView) throws -> NSColor {
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        return try #require(bitmap.colorAt(x: Int(10 * scale), y: Int(66 * scale))?.usingColorSpace(.deviceRGB))
    }

    private func assertGlass(_ bitmap: NSBitmapImageRep, host: NSView, name: String, preference: AppearancePreference) throws {
        let pixel = try glassPixel(bitmap, host: host)
        // The tint alone (0.62 Dark, 0.66 Light) keeps text legible over any desktop.
        #expect(pixel.alphaComponent > 0.6, "\(name): the sheet must carry the glass tint")
        if preference == .light { #expect(pixel.redComponent > 0.75, "\(name): Light glass") }
        if preference == .dark { #expect(pixel.redComponent < 0.3, "\(name): Dark glass") }
        // Outside the 28 pt corner only the board's soft sheet shadow shows (dark, faint),
        // never the glass tint or a system material.
        let corner = try #require(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        #expect(corner.alphaComponent < 0.25, "\(name): outside the 28 pt corner is no more than shadow")
        #expect(corner.alphaComponent < 0.01 || corner.redComponent < 0.4, "\(name): outside the 28 pt corner is no glass")
    }

    /// Below the footer, a retained or oversized window is invisible, never a band.
    private func assertTransparentBelowContent(_ bitmap: NSBitmapImageRep, name: String) {
        let row = bitmap.pixelsHigh - 1
        let clear = (0..<bitmap.pixelsWide).allSatisfy { x in (bitmap.colorAt(x: x, y: row)?.alphaComponent ?? 1) < 0.01 }
        #expect(clear, "\(name): retained window space must be transparent")
    }

    private func renderRetainedWindowTransitions(model: TrackerModel, auth: ProofModel, appearance: AppAppearance) throws {
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        host.sizingOptions = [.intrinsicContentSize]
        // Measured failing native sequence: History 653 pt -> Account 623 pt.
        // Keep that same window throughout; never fit it to the new section.
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 653), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        for preference in AppearancePreference.allCases {
            appearance.preference = preference
            for section in [TrackerSection.history, .account, .today, .account] {
                host.rootView = AnyView(
                    TrackerPopup(model: model, auth: auth, appearance: appearance, section: section)
                        .id(section)
                        .environment(\.trackerLiquidGlassOverride, false)
                )
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                host.layoutSubtreeIfNeeded()
                #expect(host.bounds.height == 653, "Retain the measured native window, not a content-sized test render")
                if section == .history {
                    // Exercise History's scrolled Activity list, not just its first
                    // rows; no screen events or OS settings are changed.
                    var didScroll = false
                    func scrollToEnd(_ view: NSView) {
                        if let scroll = view as? NSScrollView, let document = scroll.documentView {
                            document.scroll(NSPoint(x: 0, y: document.bounds.maxY))
                            scroll.reflectScrolledClipView(scroll.contentView)
                            didScroll = didScroll || scroll.contentView.bounds.minY > 0
                        }
                        view.subviews.forEach(scrollToEnd)
                    }
                    scrollToEnd(host)
                    host.layoutSubtreeIfNeeded()
                    #expect(didScroll, "History fixture must exercise a scrolled viewport")
                }
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let name = "retained-\(section.rawValue)-\(preference.rawValue)"
                if preference != .system { try assertGlass(bitmap, host: host, name: name, preference: preference) }
                // Today is far shorter than the retained 653 pt: the rest stays invisible.
                if section == .today { assertTransparentBelowContent(bitmap, name: name) }
            }
        }
    }

    private func renderLiveModes<Content: View>(_ content: Content, name: String, appearance: AppAppearance, surface: Surface = .glass) throws {
        // Changing preference on a retained window tests native live propagation.
        do {
            let host = NSHostingView(rootView: content.environment(\.trackerLiquidGlassOverride, false))
            // MenuBarExtra's retained native size must not be silently clamped
            // to this test host's inferred maximum content size.
            host.sizingOptions = [.intrinsicContentSize]
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 640), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.close() }
            for preference in [AppearancePreference.light, .dark, .system] {
                appearance.preference = preference
                let size = host.fittingSize
                // Reproduce a host taller than the content. Do NOT resize to
                // fittingSize: that hid MenuBarExtra's retained-height bands.
                let oversized = surface == .glass
                let hostHeight = ceil(size.height) + (oversized ? 64 : 0)
                window.setContentSize(NSSize(width: size.width, height: hostHeight))
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                host.layoutSubtreeIfNeeded()
                if oversized {
                    #expect(host.bounds.height == hostHeight, "Keep the oversized test window so gaps cannot be hidden by resizing")
                }
                window.displayIfNeeded()
                #expect(window.appearance == nil)
                #expect(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]))
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                switch surface {
                case .glass:
                    if preference != .system { try assertGlass(bitmap, host: host, name: name, preference: preference) }
                    assertTransparentBelowContent(bitmap, name: name)
                case .opaque:
                    assertFilledEdges(bitmap, name: name)
                    let pixel = try #require(bitmap.colorAt(x: 2, y: 2)?.usingColorSpace(.deviceRGB))
                    #expect(pixel.alphaComponent > 0.99, "\(name): popover surface must be opaque")
                    if preference == .light { #expect(pixel.redComponent > 0.75, "\(name): Light surface") }
                    if preference == .dark { #expect(pixel.redComponent < 0.3, "\(name): Dark surface") }
                }
                if preference != .system, let output = ProcessInfo.processInfo.environment["DAILY_CHALLENGE_SNAPSHOT_DIR"] {
                    let directory = URL(fileURLWithPath: output)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let png = try #require(bitmap.representation(using: .png, properties: [:]))
                    try png.write(to: directory.appendingPathComponent("\(name)-\(preference.rawValue).png"))
                }
            }
        }
    }
}
