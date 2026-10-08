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
    @Test func productionPopupSurfacesHaveOpaqueAdaptiveBacking() throws {
        try withPreferences { appearance, _ in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let owner = UUID()
            let now = ISO8601DateFormatter().date(from: "2026-10-08T12:00:00Z")!
            let model = TrackerModel(directory: directory, clock: { now })
            model.activate(ownerID: owner)
            let auth = ProofModel(fixtureOwnerID: owner, directory: directory)
            let signedOut = ProofModel(fixtureOwnerID: nil, directory: directory)
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
            try renderRetainedWindowTransitions(model: model, auth: auth, appearance: appearance)
            model.enableCorrections()
            try renderLiveModes(TrackerPopup(model: model, auth: auth, appearance: appearance, section: .history), name: "history-editing", appearance: appearance)
            model.showToday()
            model.addCustomWater("3600")
            try renderLiveModes(TrackerPopup(model: model, auth: auth, appearance: appearance), name: "today-overflow", appearance: appearance)
            try renderLiveModes(TrackerPopup(model: model, auth: signedOut, appearance: appearance), name: "sign-in", appearance: appearance)
            try renderLiveModes(CustomPourView(amount: .constant(""), cancel: {}, submit: {}), name: "custom-disabled", appearance: appearance, oversizedHost: false)
            try renderLiveModes(CustomPourView(amount: .constant("250"), cancel: {}, submit: {}), name: "custom-enabled", appearance: appearance, oversizedHost: false)
        }
    }

    private func assertFilledEdges(_ bitmap: NSBitmapImageRep, name: String) {
        // Native rounded-corner compositing is a captain check. In-process,
        // every backing pixel at the window boundary must be opaque.
        for y in [0, 1, bitmap.pixelsHigh - 2, bitmap.pixelsHigh - 1] {
            let filled = (0..<bitmap.pixelsWide).allSatisfy { x in
                (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.99
            }
            #expect(filled, "\(name): unfilled window edge at row \(y)")
        }
        for x in [0, bitmap.pixelsWide - 1] {
            let filled = (0..<bitmap.pixelsHigh).allSatisfy { y in
                (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.99
            }
            #expect(filled, "\(name): unfilled window side at column \(x)")
        }
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
                )
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                host.layoutSubtreeIfNeeded()
                #expect(host.bounds.height == 653, "Retain the measured native window, not a content-sized test render")
                if section == .history {
                    // Exercise the scrolled History viewport, not just its first
                    // screen; no screen events or OS settings are changed.
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
                assertFilledEdges(bitmap, name: "retained-\(section.rawValue)-\(preference.rawValue)")
            }
        }
    }

    private func renderLiveModes<Content: View>(_ content: Content, name: String, appearance: AppAppearance, oversizedHost: Bool = true) throws {
        // Changing preference on a retained window tests native live propagation.
        do {
            let host = NSHostingView(rootView: content)
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
                let hostHeight = ceil(size.height) + (oversizedHost ? 64 : 0)
                window.setContentSize(NSSize(width: size.width, height: hostHeight))
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                host.layoutSubtreeIfNeeded()
                if oversizedHost {
                    #expect(host.bounds.height == hostHeight, "Keep the oversized test window so gaps cannot be hidden by resizing")
                }
                window.displayIfNeeded()
                #expect(window.appearance == nil)
                #expect(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]))
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                assertFilledEdges(bitmap, name: name)
                let pixel = try #require(bitmap.colorAt(x: 2, y: 2)?.usingColorSpace(.deviceRGB))
                #expect(pixel.alphaComponent > 0.99, "\(name): root must obscure the desktop, not rely on the window material")
                if preference == .light { #expect(pixel.redComponent > 0.75, "\(name): Light backing") }
                if preference == .dark { #expect(pixel.redComponent < 0.3, "\(name): Dark backing") }
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
