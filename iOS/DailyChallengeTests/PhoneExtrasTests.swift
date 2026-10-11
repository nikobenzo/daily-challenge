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
    #expect(tracker.activeExtras.isEmpty, "Ticked today, it is no longer open")
    #expect(tracker.renameExtra(first.id, to: "Stretch gently") == nil)
    #expect(tracker.summary?.extras.first?.title == "Stretch gently")
    #expect(tracker.summary?.completedExtras.contains(first.id) == true)
    for index in 2...11 { #expect(tracker.addExtra("Extra \(index)") == nil) }
    #expect(tracker.activeExtras.count == 10)
    #expect(tracker.summary?.extrasTotal == 11)
    #expect(!tracker.canAddExtra)
    #expect(tracker.addExtra("Twelfth") != nil)
    let open = try #require(tracker.activeExtras.first)
    #expect(tracker.renameExtra(open.id, to: "Renamed at cap") == nil)
    #expect(tracker.archiveExtra(open.id) == nil)
    #expect(tracker.canAddExtra)
    #expect(tracker.summary?.extrasTotal == 10)
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
    // Read a chapter, done that day, is archived today but remains visible on that day.
    #expect(summary.extras.map(\.title) == ["Stretch", "Read a chapter", "Call family"])
    #expect(tracker.activeExtras.map(\.title) == ["Stretch"])
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

@Test @MainActor func phoneCarryOverMarksOpenExtrasLateAndDropsCompletedOnes() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("phone-extras-\(UUID())")
    let tracker = extrasFixture(.todayExtras, directory: directory).tracker
    defer { try? FileManager.default.removeItem(at: directory) }
    func rows() -> [String] {
        let summary = tracker.summary!
        return summary.extras.map { $0.title + (summary.completedExtras.contains($0.id) ? " ✓" : "") + (summary.isLate($0) ? " late" : "") }
    }
    #expect(rows() == ["Stretch late", "Read a chapter late", "Prepare tomorrow’s healthy lunch ✓"])
    #expect(tracker.activeExtras.map(\.title) == ["Stretch", "Read a chapter"])
    let calendar = tracker.dates.calendar
    tracker.selectHistoryDay(calendar.date(byAdding: .day, value: -2, to: tracker.today)!)
    #expect(rows() == ["Stretch", "Read a chapter", "Call family ✓"])
    tracker.selectHistoryDay(calendar.date(byAdding: .day, value: -1, to: tracker.today)!)
    #expect(rows() == ["Stretch late", "Read a chapter late"])
    #expect(tracker.summary?.isComplete == true, "Extras never change a complete day")
}
