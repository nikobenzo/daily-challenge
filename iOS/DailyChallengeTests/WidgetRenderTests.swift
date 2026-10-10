import ChallengeCore
import SwiftUI
import WidgetKit
import XCTest
@testable import Daily_Challenge

/// In-process production view snapshots. These cannot establish Home Screen acceptance:
/// no system compositor, margins, tint or Lock Screen vibrancy.
final class WidgetRenderTests: XCTestCase {
    /// iPhone 17 / iOS 27 widget sizes, measured from placed Home Screen captures.
    static let small = CGSize(width: 163, height: 163)
    static let medium = CGSize(width: 349, height: 163)
    static let large = CGSize(width: 349, height: 365)
    static let circular = CGSize(width: 72, height: 72)
    let now = ISO8601DateFormatter().date(from: "2026-10-10T12:00:00Z")!

    /// The same synthetic variants as the `-widget-fixture` launch (`PhoneFixtures.widgetApp`).
    static func fixture(_ variant: String, at now: Date) throws -> Challenge {
        var challenge = Challenge(ownerID: UUID(), startDate: now, timeZone: Challenge.legacyTimeZone)
        let amount = ["full", "complete"].contains(variant) ? 4000 : variant == "overflow" ? 4500
            : ["empty", "pending", "extras-empty"].contains(variant) ? 0 : 2250
        if amount > 0 { _ = try challenge.record(.pour(amount), on: now, at: now) }
        if !["empty", "pending"].contains(variant) {
            _ = try challenge.record(.setHabit(.workout, completed: true), on: now, at: now)
            _ = try challenge.record(.setDiet(variant == "missed" ? .missed : .clean), on: now, at: now)
        }
        if variant == "complete" {
            for habit in [Challenge.Habit.walk, .bibleReading] { _ = try challenge.record(.setHabit(habit, completed: true), on: now, at: now) }
        }
        if !["empty", "extras-empty"].contains(variant) {
            let count = ["extras-ten", "long-names", "overflow"].contains(variant) ? 10 : 3
            for (index, title) in PhoneFixtures.widgetExtraTitles(longNames: variant == "long-names").prefix(count).enumerated() {
                let id = UUID()
                _ = try challenge.record(.defineExtra(id: id, title: title), on: now, at: now)
                if index == 0 { _ = try challenge.record(.setExtra(id: id, completed: true), on: now, at: now) }
            }
        }
        return challenge
    }

    @MainActor func testMaximumLengthTitlesAreValid() {
        let titles = PhoneFixtures.widgetExtraTitles(longNames: true)
        XCTAssertEqual(titles.count, 10)
        for title in titles { XCTAssertEqual(Challenge.extraTitle(title), title); XCTAssertEqual(title.count, 40) }
    }

    @MainActor func testExtrasRowBudget() {
        XCTAssertEqual(ExtrasWidgetView.visibleRows(large: true, accessibility: false), 10)
        XCTAssertEqual(ExtrasWidgetView.visibleRows(large: false, accessibility: false), 3)
        XCTAssertLessThan(ExtrasWidgetView.visibleRows(large: true, accessibility: true), 10)
        XCTAssertGreaterThanOrEqual(ExtrasWidgetView.visibleRows(large: false, accessibility: true), 1)
    }

    @MainActor func testWidgetSnapshotMatrix() throws {
        for appearance in [ColorScheme.light, .dark] {
            for variant in ["empty", "partial", "full", "overflow", "pending", "complete", "missed", "extras-empty", "extras-ten", "long-names"] {
                let entry = ChallengeWidgetEntry.derive(try Self.fixture(variant, at: now), at: now)
                if ["empty", "partial", "full", "overflow"].contains(variant) {
                    render(WaterWidgetView(entry: entry, familyOverride: .systemSmall), size: Self.small, appearance: appearance, name: "water-small-\(variant)")
                    render(WaterWidgetView(entry: entry, familyOverride: .systemMedium), size: Self.medium, appearance: appearance, name: "water-medium-\(variant)")
                }
                if ["pending", "complete", "missed"].contains(variant) {
                    render(RequirementsWidgetView(entry: entry), size: Self.medium, appearance: appearance, name: "requirements-medium-\(variant)")
                }
                if ["extras-empty", "partial", "extras-ten", "long-names", "overflow"].contains(variant) {
                    render(ExtrasWidgetView(entry: entry, familyOverride: .systemMedium), size: Self.medium, appearance: appearance, name: "extras-medium-\(variant)")
                    render(ExtrasWidgetView(entry: entry, familyOverride: .systemLarge), size: Self.large, appearance: appearance, name: "extras-large-\(variant)")
                }
            }
            // Signed out, signed in without a challenge, unreadable storage: no cached data.
            for state in [ChallengeWidgetEntry.State.signedOut, .noChallenge, .unavailable] {
                let entry = ChallengeWidgetEntry.derive(nil, at: now, state: state)
                render(WidgetStatusView(state: entry.state, compact: true), size: Self.small, appearance: appearance, name: "state-small-\(state.rawValue)")
                render(WidgetStatusView(state: entry.state), size: Self.medium, appearance: appearance, name: "state-medium-\(state.rawValue)")
            }
        }
    }

    /// Large text, Increase Contrast and Reduce Transparency on the partial and ten-extras days.
    @MainActor func testWidgetAccessibilityMatrix() throws {
        let partial = ChallengeWidgetEntry.derive(try Self.fixture("partial", at: now), at: now)
        let ten = ChallengeWidgetEntry.derive(try Self.fixture("extras-ten", at: now), at: now)
        for appearance in [ColorScheme.light, .dark] {
            for (label, size) in [("xxxlarge", DynamicTypeSize.xxxLarge), ("accessibility3", .accessibility3)] {
                let options = RenderOptions(typeSize: size)
                render(WaterWidgetView(entry: partial, familyOverride: .systemSmall), size: Self.small, appearance: appearance, name: "water-small-text-\(label)", options: options)
                render(WaterWidgetView(entry: partial, familyOverride: .systemMedium), size: Self.medium, appearance: appearance, name: "water-medium-text-\(label)", options: options)
                render(RequirementsWidgetView(entry: partial), size: Self.medium, appearance: appearance, name: "requirements-medium-text-\(label)", options: options)
                render(ExtrasWidgetView(entry: ten, familyOverride: .systemMedium), size: Self.medium, appearance: appearance, name: "extras-medium-text-\(label)", options: options)
                render(ExtrasWidgetView(entry: ten, familyOverride: .systemLarge), size: Self.large, appearance: appearance, name: "extras-large-text-\(label)", options: options)
            }
            let contrast = RenderOptions(increaseContrast: true)
            render(WaterWidgetView(entry: partial, familyOverride: .systemMedium), size: Self.medium, appearance: appearance, name: "water-medium-increase-contrast", options: contrast)
            render(RequirementsWidgetView(entry: partial), size: Self.medium, appearance: appearance, name: "requirements-medium-increase-contrast", options: contrast)
            render(ExtrasWidgetView(entry: partial, familyOverride: .systemMedium), size: Self.medium, appearance: appearance, name: "extras-medium-increase-contrast", options: contrast)
            let opaque = RenderOptions(reduceTransparency: true)
            render(WaterWidgetView(entry: partial, familyOverride: .systemMedium), size: Self.medium, appearance: appearance, name: "water-medium-reduce-transparency", options: opaque)
            render(WaterWidgetView(entry: partial, familyOverride: .systemSmall), size: Self.small, appearance: appearance, name: "water-small-reduce-transparency", options: opaque)
        }
    }

    /// D-W2 Lock Screen ring: read-only, and fully redacted for the locked (privacy) case.
    @MainActor func testLockScreenWaterRing() throws {
        for variant in ["empty", "partial", "overflow"] {
            let entry = ChallengeWidgetEntry.derive(try Self.fixture(variant, at: now), at: now)
            XCTAssertNil(entry.binding, "The Lock Screen ring never carries an action binding here")
            render(WaterWidgetView(entry: entry, familyOverride: .accessoryCircular), size: Self.circular, appearance: .dark,
                   name: "lock-water-circular-\(variant)", options: RenderOptions(accessory: true))
        }
        let partial = ChallengeWidgetEntry.derive(try Self.fixture("partial", at: now), at: now)
        render(WaterWidgetView(entry: partial, familyOverride: .accessoryCircular), size: Self.circular, appearance: .dark,
               name: "lock-water-circular-redacted", options: RenderOptions(accessory: true, redacted: true))
        render(WaterWidgetView(entry: partial, familyOverride: .systemMedium), size: Self.medium, appearance: .light,
               name: "water-medium-redacted", options: RenderOptions(redacted: true))
    }

    struct RenderOptions {
        var typeSize: DynamicTypeSize = .large
        var increaseContrast = false
        var reduceTransparency = false
        var accessory = false
        var redacted = false
    }

    @MainActor private func render<V: View>(_ content: V, size: CGSize, appearance: ColorScheme, name: String,
                                            options: RenderOptions = RenderOptions()) {
        let shape = RoundedRectangle(cornerRadius: options.accessory ? size.width / 2 : 24, style: .continuous)
        let widget = content
            .foregroundStyle(Theme.textPrimary)
            .padding(options.accessory ? 0 : 16)
            .frame(width: size.width, height: size.height)
            .background(options.accessory ? AnyShapeStyle(Color.black) : AnyShapeStyle(Theme.solidGlass))
            .clipShape(shape)
            .privacySensitive()
            .redacted(reason: options.redacted ? .privacy : [])
        let surface = widget
            .padding(8)
            .background(options.accessory ? Color(white: 0.15) : Color(white: appearance == .light ? 0.82 : 0.12))
            .environment(\.colorScheme, appearance)
            .environment(\.dynamicTypeSize, options.typeSize)
            .environment(\._colorSchemeContrast, options.increaseContrast ? .increased : .standard)
            .environment(\._accessibilityReduceTransparency, options.reduceTransparency)
        let renderer = ImageRenderer(content: surface)
        renderer.scale = 2
        guard let image = renderer.uiImage else { XCTFail("No rendered image for \(name)"); return }
        let attachment = XCTAttachment(image: image)
        let suffix = options.accessory ? "" : "-\(appearance == .light ? "light" : "dark")"
        attachment.name = "rendered-\(name)\(suffix)"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
