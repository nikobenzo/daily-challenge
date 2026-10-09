import AppKit
import ChallengeCore
import Foundation
import SwiftUI
import Testing
@testable import ChallengeSyncKit
@testable import DailyChallengeProof

private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

@MainActor private final class Clock {
    var now = date("2026-10-08T12:00:00Z")
}

@MainActor private func withTracker(_ test: (TrackerModel, URL, UUID, Clock) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let owner = UUID(), clock = Clock()
    let model = TrackerModel(directory: directory, clock: { clock.now })
    model.activate(ownerID: owner)
    try test(model, directory, owner, clock)
}

// The model's behaviour is tested in ChallengeSyncKitTests/TrackerModelTests.swift.
@Test @MainActor func nativeTrackerSurfacesRenderAtPopupWidth() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    try withTracker { model, _, _, clock in
        model.startChallenge(on: date("2026-10-07T12:00:00Z"))
        for _ in 0..<9 { model.addWater() }
        model.toggle(.workout)
        model.toggle(.walk)
        model.setDiet(.clean)
        let output = ProcessInfo.processInfo.environment["DAILY_CHALLENGE_SNAPSHOT_DIR"]
        for dark in [false, true] {
            for history in [false, true] {
                if history { model.selectHistoryDay(clock.now) } else { model.showToday() }
                let content = Group {
                    if history { HistoryTrackerView(model: model) }
                    else { TodayTrackerView(model: model) }
                }.padding(16).frame(width: 420)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, dark ? .dark : .light)
                // ImageRenderer cannot draw AppKit-backed ScrollView content.
                // Render an isolated, never-shown native window instead.
                let host = NSHostingView(rootView: content)
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let size = host.fittingSize
                #expect(size.width == 420)
                // History is fixed to the shared History/Account height; Today is shorter.
                #expect(size.height <= Theme.Size.wideSectionHeight + 32)
                let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                defer { window.close() }
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.08))
                host.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                let cached = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: cached)
                let image = try #require(cached.cgImage)
                if let output {
                    let directory = URL(fileURLWithPath: output, isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    let data = try #require(bitmap.representation(using: .png, properties: [:]))
                    try data.write(to: directory.appendingPathComponent("\(history ? "history" : "today")-\(dark ? "dark" : "light").png"))
                }
            }
        }
    }
}
