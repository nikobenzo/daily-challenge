import ChallengeCore
import ChallengeSyncKit
import Foundation
import Testing
@testable import Daily_Challenge

@MainActor private func extrasFixture(_ screen: PhoneFixtures.Screen = .today, directory: URL) -> PhoneApp {
    PhoneFixtures.make(screen, defaults: UserDefaults(suiteName: "phone-extras-tests-\(UUID())")!, directory: directory)
}

@Test @MainActor func phoneExtrasAddRenameArchiveAndCapPreserveTheFiveAndStreaks() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("phone-extras-\(UUID())")
    let tracker = extrasFixture(.todayComplete, directory: directory).tracker
    defer { try? FileManager.default.removeItem(at: directory) }
    let before = tracker.streaks
    #expect(tracker.activeExtras.isEmpty)
    #expect(tracker.summary?.extrasTotal == 0)
    #expect(tracker.addExtra("  Stretch  ") == nil)
    let first = try #require(tracker.activeExtras.first)
    #expect(first.title == "Stretch")
    tracker.toggleExtra(first.id)
    #expect(tracker.summary?.extrasDone == 1)
    #expect(tracker.renameExtra(first.id, to: "Stretch gently") == nil)
    #expect(tracker.activeExtras.first?.id == first.id)
    #expect(tracker.summary?.completedExtras.contains(first.id) == true)
    for index in 2...10 { #expect(tracker.addExtra("Extra \(index)") == nil) }
    #expect(tracker.activeExtras.count == 10)
    #expect(!tracker.canAddExtra)
    #expect(tracker.addExtra("Eleventh") != nil)
    #expect(tracker.renameExtra(first.id, to: "Renamed at cap") == nil)
    #expect(tracker.archiveExtra(first.id) == nil)
    #expect(tracker.canAddExtra)
    #expect(tracker.summary?.extrasTotal == 9)
    #expect(tracker.addExtra("Replacement") == nil)
    #expect(tracker.summary?.isComplete == true)
    #expect(tracker.streaks?.current == before?.current)
    #expect(tracker.streaks?.best == before?.best)
    #expect(tracker.streaks?.milestones == before?.milestones)
}

@Test @MainActor func phoneExtrasRejectInvalidAndLongTitlesWithoutSaving() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("phone-extras-\(UUID())")
    let tracker = extrasFixture(directory: directory).tracker
    defer { try? FileManager.default.removeItem(at: directory) }
    let events = tracker.challenge?.allActivities.count
    for title in ["", "   ", "Two\nlines", String(repeating: "a", count: 41)] {
        #expect(tracker.addExtra(title) != nil)
    }
    #expect(tracker.challenge?.allActivities.count == events)
    #expect(tracker.addExtra(String(repeating: "a", count: 40)) == nil)
    let id = try #require(tracker.activeExtras.first?.id)
    #expect(tracker.renameExtra(id, to: "\n") != nil)
    #expect(tracker.activeExtras.first?.title.count == 40)
}

@Test @MainActor func phoneHistoricalExtrasRequireUnlockAndSelectionRelocks() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("phone-extras-\(UUID())")
    let tracker = extrasFixture(.historyExtras, directory: directory).tracker
    defer { try? FileManager.default.removeItem(at: directory) }
    let summary = try #require(tracker.summary)
    #expect(summary.extrasTotal == 3)
    #expect(tracker.activeExtras.count == 2) // Archived today remains visible on older days.
    let extra = try #require(summary.extras.first)
    let before = tracker.streaks
    #expect(!tracker.canEdit)
    tracker.toggleExtra(extra.id)
    #expect(tracker.summary?.completedExtras.contains(extra.id) == false)
    tracker.enableCorrections()
    tracker.toggleExtra(extra.id)
    #expect(tracker.summary?.completedExtras.contains(extra.id) == true)
    let archivedExtra = summary.extras.first { $0.isArchived }
    let archived = try #require(archivedExtra)
    #expect(tracker.summary?.completedExtras.contains(archived.id) == true)
    tracker.toggleExtra(archived.id)
    #expect(tracker.summary?.completedExtras.contains(archived.id) == false)
    #expect(tracker.summary?.isComplete == summary.isComplete)
    #expect(tracker.streaks?.current == before?.current)
    #expect(tracker.streaks?.best == before?.best)
    #expect(tracker.streaks?.milestones == before?.milestones)
    let previous = tracker.dates.calendar.date(byAdding: .day, value: -1, to: tracker.selectedDay)!
    tracker.selectHistoryDay(previous)
    #expect(!tracker.canEdit)
    #expect(!tracker.isEditingHistory)
}
