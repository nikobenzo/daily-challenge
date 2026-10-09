import ChallengeCore
import Foundation
import Testing
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

@Test @MainActor func manageExtrasAddsRenamesArchivesAndExplainsTheCap() throws {
    try withTracker { model, directory, owner, clock in
        #expect(model.addExtra("Stretch") != nil, "No challenge yet: nothing to attach an extra to")
        model.startChallenge(on: clock.now)
        #expect(model.addExtra("   ") == ChallengeError.invalidExtraTitle.localizedDescription)
        #expect(model.addExtra(String(repeating: "x", count: 41)) == ChallengeError.invalidExtraTitle.localizedDescription)
        #expect(model.addExtra("  Stretch  ") == nil)
        let stretch = try #require(model.activeExtras.first)
        #expect(stretch.title == "Stretch")
        #expect(model.renameExtra(stretch.id, to: "Stretch") == nil)
        #expect(model.history.count == 1, "An unchanged name records nothing")
        #expect(model.renameExtra(stretch.id, to: "Stretch 10 min") == nil)
        for index in 2...Challenge.maximumActiveExtras { #expect(model.addExtra("Extra \(index)") == nil) }
        #expect(!model.canAddExtra)
        #expect(model.addExtra("One too many") == ChallengeError.tooManyExtras.localizedDescription)
        #expect(model.archiveExtra(stretch.id) == nil)
        #expect(model.canAddExtra)
        #expect(model.activeExtras.count == Challenge.maximumActiveExtras - 1)
        #expect(model.summary?.extras.contains { $0.id == stretch.id } == false)
        // Pending for sync and durable like every other edit.
        let reopened = TrackerModel(directory: directory, clock: { clock.now })
        reopened.activate(ownerID: owner)
        #expect(reopened.activeExtras == model.activeExtras)
        #expect(reopened.store?.pendingCount == model.store?.pendingCount)
    }
}

@Test @MainActor func extraTicksFollowHabitEditRulesAndNeverCompleteTheDay() throws {
    try withTracker { model, _, _, clock in
        model.startChallenge(on: clock.now.addingTimeInterval(-86_400))
        #expect(model.addExtra("Stretch") == nil)
        let id = try #require(model.activeExtras.first?.id)
        model.toggleExtra(id)
        #expect(model.summary?.completedExtras == [id])
        #expect(model.summary?.allExtrasDone == true)
        #expect(model.summary?.isComplete == false)
        model.toggleExtra(id)
        #expect(model.summary?.completedExtras.isEmpty == true)

        // Yesterday shows today's extra (definitions are not day-bound), locked until Edit this day.
        let yesterday = clock.now.addingTimeInterval(-86_400)
        model.selectHistoryDay(yesterday)
        #expect(model.summary?.extrasTotal == 1)
        model.toggleExtra(id)
        #expect(model.summary?.completedExtras.isEmpty == true)
        #expect(model.errorMessage != nil)
        model.enableCorrections()
        model.toggleExtra(id)
        #expect(model.summary?.completedExtras == [id])
        #expect(model.summary?.status == .missed)
        // Defining is not a correction: it works with a past day selected and records on today.
        #expect(model.addExtra("Read") == nil)
        #expect(model.challenge?.history(on: clock.now).filter {
            if case .defineExtra = $0.action { true } else { false }
        }.count == 2)
        model.showToday()
        #expect(model.summary?.completedExtras.isEmpty == true)
    }
}

@Test @MainActor func allExtrasDoneCelebratesOnceAndNeverReplays() throws {
    try withTracker { model, directory, owner, clock in
        model.startChallenge(on: clock.now)
        #expect(model.addExtra("Stretch") == nil)
        #expect(model.addExtra("Read") == nil)
        let ids = model.activeExtras.map(\.id)
        model.toggleExtra(ids[0])
        #expect(model.celebration == nil, "Only the last open extra celebrates")
        model.toggleExtra(ids[1])
        #expect(model.celebration?.kind == .extras)
        let first = model.celebration
        model.toggleExtra(ids[1])
        model.toggleExtra(ids[1])
        #expect(model.celebration == first, "Undo and re-tick must not replay it")
        // Opening on another launch never celebrates an already-finished day.
        let reopened = TrackerModel(directory: directory, clock: { clock.now })
        reopened.activate(ownerID: owner)
        #expect(reopened.celebration == nil)
        // A new extra reopens the list; finishing it again on the same day stays quiet.
        #expect(model.addExtra("Journal") == nil)
        model.toggleExtra(try #require(model.activeExtras.last?.id))
        #expect(model.celebration == first)
    }
}
