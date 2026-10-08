import AppKit
import ChallengeCore
import Foundation
import Observation
import SwiftUI
import Testing
@testable import DailyChallengeProof

private let motionDate = ISO8601DateFormatter().date(from: "2026-10-08T12:00:00Z")!

private func complete(_ challenge: inout Challenge, on day: Date, at now: Date) throws {
    try challenge.record(.pour(4_050), on: day, at: now)
    for habit in Challenge.Habit.allCases { try challenge.record(.setHabit(habit, completed: true), on: day, at: now) }
    try challenge.record(.setDiet(.clean), on: day, at: now)
}

@Test func waterMotionHasFiniteWindowAndNoHiddenOrReducedPath() {
    let motion = WaterMotion(from: 3_600, to: 4_050, started: motionDate)
    #expect(!motion.isActive(at: motionDate.addingTimeInterval(-1), visible: true, reduceMotion: false))
    #expect(motion.isActive(at: motionDate, visible: true, reduceMotion: false))
    #expect(!motion.isActive(at: motionDate, visible: false, reduceMotion: false))
    #expect(!motion.isActive(at: motionDate, visible: true, reduceMotion: true))
    #expect(!motion.isActive(at: motionDate.addingTimeInterval(1.2), visible: true, reduceMotion: false))
    #expect(motion.level(at: motionDate) == 0.9)
    #expect(motion.level(at: motionDate.addingTimeInterval(2)) == 1)
    #expect(motion.slosh(at: motionDate.addingTimeInterval(2)) == 0)
    #expect(motion.spills)
    #expect(motion.frameDates.count == 37)
    #expect(motion.frameDates.last == motionDate.addingTimeInterval(WaterMotion.duration))
    for kind in [CompletionCelebration.daily, .milestone] {
        let event = CelebrationEvent(kind: kind, started: motionDate)
        #expect(event.frameDates.last == motionDate.addingTimeInterval(event.duration))
        #expect(event.presentation(at: motionDate, visible: true, reduceMotion: false) == .animated)
        #expect(event.presentation(at: motionDate, visible: true, reduceMotion: true) == .highlight)
        #expect(event.presentation(at: motionDate, visible: false, reduceMotion: false) == .idle)
        #expect(event.presentation(at: motionDate.addingTimeInterval(event.duration), visible: true, reduceMotion: false) == .idle)
    }
    let undo = WaterMotion(from: 4_050, to: 3_600, started: motionDate)
    #expect(!undo.spills)
    #expect(undo.level(at: motionDate.addingTimeInterval(0.3)) < 1)
    #expect(undo.level(at: motionDate.addingTimeInterval(2)) == 0.9)
}

@Test(arguments: [0, 900])
func waterMotionRetargetsRapidUndoAndSuccessivePours(target: Int) {
    let pour = WaterMotion(from: 0, to: 450, started: motionDate)
    let lastFrame = motionDate.addingTimeInterval(0.1)
    let displayed = pour.level(at: lastFrame)
    #expect(displayed > 0 && displayed < 450.0 / 4_000)
    let retargetDate = lastFrame.addingTimeInterval(0.01)
    let next = WaterMotion(from: 450, to: target, started: retargetDate, presentationLevel: displayed)
    #expect(next.level(at: retargetDate) == displayed)
    #expect(next.from == 450)
    #expect(next.to == target)
    let laterLevel = next.level(at: retargetDate.addingTimeInterval(0.1))
    #expect(target == 0 ? laterLevel < displayed : laterLevel > displayed)
    #expect(abs(next.level(at: retargetDate.addingTimeInterval(1.2)) - Double(target) / 4_000) < 0.000001)
    #expect(!next.spills)
    #expect(next.frameDates.count == 37)
    #expect(!next.isActive(at: retargetDate.addingTimeInterval(1.2), visible: true, reduceMotion: false))
    #expect(!next.isActive(at: retargetDate, visible: false, reduceMotion: false))
    #expect(!next.isActive(at: retargetDate, visible: true, reduceMotion: true))
}

@Test func waterMotionRetargetingKeepsSavedOverflowEligibility() {
    let pour = WaterMotion(from: 0, to: 4_500, started: motionDate)
    let interrupted = motionDate.addingTimeInterval(0.1)
    let displayed = pour.level(at: interrupted)
    for target in [4_050, 4_950] {
        let next = WaterMotion(from: 4_500, to: target, started: interrupted, presentationLevel: displayed)
        #expect(next.level(at: interrupted) == displayed)
        #expect(next.spills == (target > 4_500))
        #expect(next.from == 4_500)
        #expect(next.to == target)
        #expect(next.level(at: interrupted.addingTimeInterval(1.2)) == 1)
    }
}

@Test @MainActor func finiteFrameDeliveryStopsAtDeadlineAndOnCancellation() async throws {
    var frames = 0
    let start = Date()
    try await renderFiniteFrames([start.addingTimeInterval(0.02), start.addingTimeInterval(0.04)]) { _ in frames += 1 }
    let settledCount = frames
    #expect(settledCount > 0 && settledCount <= 2)
    try await Task.sleep(for: .milliseconds(100))
    #expect(frames == settledCount)
    let cancelled = Task { @MainActor in
        try await renderFiniteFrames([Date().addingTimeInterval(0.1)]) { _ in frames += 1 }
    }
    await Task.yield()
    cancelled.cancel()
    _ = try? await cancelled.value
    try await Task.sleep(for: .milliseconds(150))
    #expect(frames == settledCount)
}

@Test func celebrationsPersistAndConsumeOpenSyncCorrectionAndMidnight() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("celebrations.json")
    let ledger = CelebrationLedger(file: file), id = UUID()
    let today = ChallengeDates.jersey.calendar.startOfDay(for: motionDate)
    let yesterday = ChallengeDates.jersey.calendar.date(byAdding: .day, value: -1, to: today)!
    var challenge = Challenge(ownerID: UUID(), startDate: yesterday)
    try complete(&challenge, on: today, at: motionDate)
    #expect(ledger.observe(challenge, challengeID: id, now: motionDate, localCompletionDay: today) == .daily)
    #expect(ledger.observe(challenge, challengeID: id, now: motionDate) == nil) // popup reopen
    #expect(CelebrationLedger(file: file).observe(challenge, challengeID: id, now: motionDate, localCompletionDay: today) == nil)
    try challenge.record(.setDiet(.pending), on: today, at: motionDate)
    _ = ledger.observe(challenge, challengeID: id, now: motionDate)
    try challenge.record(.setDiet(.clean), on: today, at: motionDate)
    #expect(ledger.observe(challenge, challengeID: id, now: motionDate, localCompletionDay: today) == nil)
    try complete(&challenge, on: yesterday, at: motionDate)
    #expect(ledger.observe(challenge, challengeID: id, now: motionDate, localCompletionDay: yesterday) == nil)
    let tomorrow = ChallengeDates.jersey.calendar.date(byAdding: .day, value: 1, to: today)!
    #expect(ledger.observe(challenge, challengeID: id, now: tomorrow, localCompletionDay: today) == nil)
    try complete(&challenge, on: tomorrow, at: tomorrow)
    #expect(ledger.observe(challenge, challengeID: id, now: tomorrow, localCompletionDay: tomorrow) == .daily)

    let remoteID = UUID()
    #expect(ledger.observe(challenge, challengeID: remoteID, now: tomorrow) == nil) // synced/open/import baseline
    #expect(ledger.observe(challenge, challengeID: remoteID, now: tomorrow, localCompletionDay: tomorrow) == nil)
}

@Test func milestoneUsesDerivedRunAndNeverReplaysAfterCorrection() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let ledger = CelebrationLedger(file: directory.appendingPathComponent("seen.json")), id = UUID()
    let today = ChallengeDates.jersey.calendar.startOfDay(for: motionDate)
    let start = ChallengeDates.jersey.calendar.date(byAdding: .day, value: -74, to: today)!
    var challenge = Challenge(ownerID: UUID(), startDate: start)
    for offset in 0..<74 {
        try complete(&challenge, on: ChallengeDates.jersey.calendar.date(byAdding: .day, value: offset, to: start)!, at: motionDate)
    }
    #expect(ledger.observe(challenge, challengeID: id, now: motionDate) == nil)
    try complete(&challenge, on: today, at: motionDate)
    #expect(ledger.observe(challenge, challengeID: id, now: motionDate, localCompletionDay: today) == .milestone)
    try challenge.record(.setDiet(.missed), on: start, at: motionDate)
    #expect(ledger.observe(challenge, challengeID: id, now: motionDate, localCompletionDay: start) == nil)
    let correctedID = UUID()
    #expect(ledger.observe(challenge, challengeID: correctedID, now: motionDate) == nil)
    try challenge.record(.setDiet(.clean), on: start, at: motionDate)
    #expect(ledger.observe(challenge, challengeID: id, now: motionDate, localCompletionDay: start) == nil)
    // A historical correction newly derives today's milestone, but cannot celebrate it.
    #expect(ledger.observe(challenge, challengeID: correctedID, now: motionDate, localCompletionDay: start) == nil)
    #expect(ledger.observe(challenge, challengeID: correctedID, now: motionDate, localCompletionDay: today) == nil)
    #expect(ledger.observe(challenge, challengeID: id, now: motionDate, localCompletionDay: today) == nil)
}

@Test func corruptOrUnwritableCelebrationMarkersFailClosed() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try Data("not json".utf8).write(to: file)
    var challenge = Challenge(ownerID: UUID(), startDate: motionDate)
    try complete(&challenge, on: motionDate, at: motionDate)
    let today = ChallengeDates.jersey.calendar.startOfDay(for: motionDate)
    #expect(CelebrationLedger(file: file).observe(challenge, challengeID: UUID(), now: motionDate, localCompletionDay: today) == nil)
    #expect(CelebrationLedger(file: file.appendingPathComponent("impossible")).observe(challenge, challengeID: UUID(), now: motionDate, localCompletionDay: today) == nil)
}

@Test @MainActor func modelOnlyEmitsForNewLocalTodayCompletion() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let owner = UUID()
    let model = TrackerModel(directory: directory, clock: { motionDate })
    model.activate(ownerID: owner)
    model.startChallenge(on: motionDate)
    model.addWater(4_000)
    for habit in Challenge.Habit.allCases { model.toggle(habit) }
    #expect(model.celebration == nil)
    model.setDiet(.clean)
    #expect(model.celebration?.kind == .daily)
    let event = model.celebration
    model.setDiet(.pending)
    model.setDiet(.clean)
    #expect(model.celebration == event)
    let reopened = TrackerModel(directory: directory, clock: { motionDate })
    reopened.activate(ownerID: owner)
    #expect(reopened.celebration == nil)
    reopened.setDiet(.pending)
    reopened.setDiet(.clean)
    #expect(reopened.celebration == nil)
}

private struct HitTarget: NSViewRepresentable {
    let button: NSButton
    func makeNSView(context: Context) -> NSButton { button }
    func updateNSView(_ view: NSButton, context: Context) {}
}

@MainActor @Observable private final class MotionTestState {
    var amount = 3_600
    var event: CelebrationEvent?
    var reduced = false
    var visible = true
}

private struct MotionTestSurface: View {
    let button: NSButton
    let state: MotionTestState
    var body: some View {
        HitTarget(button: button)
            .overlay { WaterJugView(millilitres: state.amount) }
            .overlay { CompletionEffect(event: state.event) }
            .environment(\.trackerPopupVisible, true)
            .environment(\.trackerReduceMotionOverride, state.reduced)
            .frame(width: 380, height: 190)
    }
}

/// In-process renders of production Today controls and effects, not MenuBarExtra
/// compositor acceptance. All commands persist only to an isolated fixture account.
@Test @MainActor func todayMotionRendersLocalCommandsAndSettles() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = TrackerModel(directory: directory)
    model.activate(ownerID: UUID())
    model.startChallenge(on: Date())
    let policy = MotionTestState()
    struct Surface: View {
        let model: TrackerModel
        let policy: MotionTestState
        var body: some View {
            TodayTrackerView(model: model)
                .padding(16).frame(width: 420).trackerSurface()
                .environment(\.trackerPopupVisible, policy.visible)
                .environment(\.trackerReduceMotionOverride, policy.reduced)
        }
    }
    let host = NSHostingView(rootView: Surface(model: model, policy: policy))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 600),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    window.setContentSize(host.fittingSize)
    func capture(_ stage: String, wait: TimeInterval = 0.1) async throws {
        try await Task.sleep(for: .seconds(wait))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            Issue.record("Unable to render the production Today surface")
            return
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
        if let output = ProcessInfo.processInfo.environment["DAILY_CHALLENGE_SNAPSHOT_DIR"] {
            let outputDirectory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: outputDirectory.appendingPathComponent("motion-\(stage).png"))
        }
    }
    try await capture("empty")
    model.addWater()
    try await capture("pour")
    model.undoWater()
    try await capture("rapid-undo")
    #expect(model.summary?.waterMillilitres == 0)
    model.addWater()
    try await capture("restart-pour")
    model.addWater()
    try await capture("successive-pour")
    #expect(model.summary?.waterMillilitres == 900)
    model.addWater(3_600)
    try await capture("overflow")
    #expect(model.summary?.waterMillilitres == 4_500)
    for habit in Challenge.Habit.allCases { model.toggle(habit) }
    model.setDiet(.clean)
    #expect(model.celebration?.kind == .daily)
    try await capture("daily")
    policy.reduced = true
    try await capture("reduce-motion")
    policy.visible = false
    try await capture("hidden")
    policy.visible = true
    try await capture("reopened")
    try await capture("settled", wait: 2)
    #expect(model.summary?.isComplete == true)
    let reopened = TrackerModel(directory: directory)
    reopened.activate(ownerID: try #require(model.challenge).ownerID)
    #expect(reopened.summary?.waterMillilitres == 4_500)
    #expect(reopened.celebration == nil)
}

@Test @MainActor func overflowingJugAndCelebrationDoNotInterceptControls() {
    let button = NSButton(title: "Underlying control", target: nil, action: nil)
    let state = MotionTestState()
    let host = NSHostingView(rootView: MotionTestSurface(button: button, state: state))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 190),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.08))
    host.layoutSubtreeIfNeeded()
    // Trigger live spill + milestone overlays, then change the injected system
    // policy while active. Neither animated nor static paths may eat the click.
    state.amount = 4_500
    state.event = CelebrationEvent(kind: .milestone, started: Date())
    for reduced in [false, true] {
        state.reduced = reduced
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        let hit = host.hitTest(host.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), from: button))
        #expect(hit === button || hit?.isDescendant(of: button) == true)
    }
}
