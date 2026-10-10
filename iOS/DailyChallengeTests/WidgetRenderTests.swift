import ChallengeCore
import SwiftUI
import WidgetKit
import XCTest
@testable import Daily_Challenge

/// In-process production view snapshots. These cannot establish Home Screen acceptance.
final class WidgetRenderTests: XCTestCase {
    @MainActor func testWidgetSnapshotMatrix() throws {
        let now = ISO8601DateFormatter().date(from: "2026-10-10T12:00:00Z")!
        for appearance in [ColorScheme.light, .dark] {
            for variant in ["empty", "partial", "full", "overflow", "pending", "complete", "missed", "extras-empty", "extras-ten", "long-names"] {
                var challenge = Challenge(ownerID: UUID(), startDate: now, timeZone: Challenge.legacyTimeZone)
                let amount = ["full", "complete"].contains(variant) ? 4000 : variant == "overflow" ? 4500 : ["empty", "pending", "extras-empty"].contains(variant) ? 0 : 2250
                if amount > 0 { _ = try challenge.record(.pour(amount), on: now, at: now) }
                if !["empty", "pending"].contains(variant) {
                    _ = try challenge.record(.setHabit(.workout, completed: true), on: now, at: now)
                    _ = try challenge.record(.setDiet(variant == "missed" ? .missed : .clean), on: now, at: now)
                }
                if variant == "complete" {
                    for habit in [Challenge.Habit.walk, .bibleReading] { _ = try challenge.record(.setHabit(habit, completed: true), on: now, at: now) }
                }
                if !["empty", "extras-empty"].contains(variant) {
                    let titles = ["Stretch", "Read a chapter", "Prepare tomorrow’s healthy lunch", "Practise gratitude", "Call family", "Tidy desk", "Journal", "Go outside", "Sleep on time", "A readable extra title of forty letters!"]
                    for (index, title) in titles.prefix(["extras-ten", "long-names", "overflow"].contains(variant) ? 10 : 3).enumerated() {
                        let id = UUID()
                        _ = try challenge.record(.defineExtra(id: id, title: title), on: now, at: now)
                        if index == 0 { _ = try challenge.record(.setExtra(id: id, completed: true), on: now, at: now) }
                    }
                }
                let entry = ChallengeWidgetEntry.derive(challenge, at: now)
                if ["empty", "partial", "full", "overflow"].contains(variant) {
                    render(WaterWidgetView(entry: entry, familyOverride: .systemSmall), family: .systemSmall, size: CGSize(width: 170, height: 170), appearance: appearance, name: "water-small-\(variant)")
                    render(WaterWidgetView(entry: entry, familyOverride: .systemMedium), family: .systemMedium, size: CGSize(width: 360, height: 170), appearance: appearance, name: "water-medium-\(variant)")
                }
                if ["pending", "complete", "missed"].contains(variant) {
                    render(RequirementsWidgetView(entry: entry), family: .systemMedium, size: CGSize(width: 360, height: 170), appearance: appearance, name: "requirements-medium-\(variant)")
                }
                if ["extras-empty", "partial", "extras-ten", "long-names", "overflow"].contains(variant) {
                    render(ExtrasWidgetView(entry: entry, familyOverride: .systemMedium), family: .systemMedium, size: CGSize(width: 360, height: 170), appearance: appearance, name: "extras-medium-\(variant)")
                    render(ExtrasWidgetView(entry: entry, familyOverride: .systemLarge), family: .systemLarge, size: CGSize(width: 360, height: 376), appearance: appearance, name: "extras-large-\(variant)")
                    if variant == "extras-ten" {
                        render(ExtrasWidgetView(entry: entry, familyOverride: .systemLarge), family: .systemLarge, size: CGSize(width: 360, height: 376), appearance: appearance, name: "extras-large-accessibility", typeSize: .accessibility3)
                    }
                }
            }
        }
    }

    @MainActor private func render<V: View>(_ content: V, family: WidgetFamily, size: CGSize, appearance: ColorScheme, name: String, typeSize: DynamicTypeSize = .large) {
        let surface = content.padding(16).frame(width: size.width, height: size.height)
            .background(Theme.solidGlass)
            .environment(\.colorScheme, appearance).environment(\.dynamicTypeSize, typeSize)
        let renderer = ImageRenderer(content: surface)
        renderer.scale = 2
        guard let image = renderer.uiImage else { XCTFail("No rendered image for \(name)"); return }
        let attachment = XCTAttachment(image: image)
        attachment.name = "rendered-\(name)-\(appearance == .light ? "light" : "dark")"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
