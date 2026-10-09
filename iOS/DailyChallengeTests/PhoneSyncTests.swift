import ChallengeCore
import ChallengeSyncKit
import Foundation
import Testing
@testable import Daily_Challenge

/// An in-memory server with the hosted schema's rules: one challenge per owner,
/// insert-ignore events, everything returned on read.
@MainActor private final class MemoryServer: ChallengeTransport {
    var challenge: ChallengeRecord?
    var events: [UUID: ChallengeEvent] = [:]
    var reachable = true

    func fetchChallenge(ownerID: UUID) async throws -> ChallengeRecord? {
        guard reachable else { throw URLError(.notConnectedToInternet) }
        return challenge?.ownerID == ownerID ? challenge : nil
    }

    func insertChallenge(_ record: ChallengeRecord) async throws {
        guard reachable else { throw URLError(.notConnectedToInternet) }
        if challenge == nil { challenge = record }
    }

    func upload(_ events: [ChallengeEvent], ownerID: UUID) async throws {
        guard reachable else { throw URLError(.notConnectedToInternet) }
        for event in events where self.events[event.id] == nil {
            self.events[event.id] = ChallengeEvent(ownerID: event.ownerID, challengeID: event.challengeID,
                                                   activity: event.activity, receivedAt: event.activity.recordedAt.ISO8601Format())
        }
    }

    func fetchEvents(ownerID: UUID, challengeID: UUID) async throws -> RemoteEvents {
        guard reachable else { throw URLError(.notConnectedToInternet) }
        return RemoteEvents(events: events.values.filter { $0.ownerID == ownerID && $0.challengeID == challengeID })
    }
}

@MainActor private struct Device {
    let tracker: TrackerModel
    let directory: URL

    init(owner: UUID, server: MemoryServer, now: Date) {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("phone-sync-\(UUID().uuidString)")
        tracker = TrackerModel(directory: directory, clock: { now })
        tracker.configureSync(server)
        tracker.activate(ownerID: owner)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private let now = ISO8601DateFormatter().date(from: "2026-10-09T14:00:00Z")!
private let jersey = TimeZone(identifier: "Europe/Jersey")!

@Test @MainActor func aPhoneAdoptsTheMacsChallengeAndTheirEntriesConverge() async throws {
    let server = MemoryServer(), owner = UUID()
    let mac = Device(owner: owner, server: server, now: now), phone = Device(owner: owner, server: server, now: now)
    defer { mac.remove(); phone.remove() }

    await mac.tracker.sync(force: true)
    mac.tracker.startChallenge(on: now, timeZone: jersey)
    mac.tracker.addWater()
    await mac.tracker.sync(force: true)
    #expect(mac.tracker.syncError == nil)

    // The phone never shows setup: the server check finds the Mac's challenge and adopts it.
    #expect(!phone.tracker.canStartChallenge)
    await phone.tracker.sync(force: true)
    #expect(phone.tracker.store?.record == server.challenge)
    #expect(phone.tracker.challenge?.timeZone.identifier == "Europe/Jersey")
    #expect(phone.tracker.summary?.waterMillilitres == 450)

    phone.tracker.addWater()
    phone.tracker.toggle(.workout)
    #expect(phone.tracker.syncState == .savedLocally(pending: 2))
    await phone.tracker.sync(force: true)
    await mac.tracker.sync(force: true)
    #expect(mac.tracker.summary?.waterMillilitres == 900)
    #expect(mac.tracker.summary?.completedHabits.contains(.workout) == true)
    #expect(phone.tracker.store?.pendingCount == 0)
}

@Test @MainActor func offlinePhoneEntriesWaitInTheQueueAndSyncOnTheNextForeground() async throws {
    let server = MemoryServer(), owner = UUID()
    let phone = Device(owner: owner, server: server, now: now)
    defer { phone.remove() }
    await phone.tracker.sync(force: true)
    phone.tracker.startChallenge(on: now, timeZone: jersey)
    await phone.tracker.sync(force: true)

    server.reachable = false
    phone.tracker.addWater()
    phone.tracker.undoWater()
    phone.tracker.addWater(250)
    await phone.tracker.sync(force: true)
    #expect(phone.tracker.syncError != nil)
    #expect(phone.tracker.store?.pendingCount == 3)
    #expect(phone.tracker.summary?.waterMillilitres == 250)

    // Relaunch from disk: the queue survives.
    let relaunched = TrackerModel(directory: phone.directory, clock: { now })
    relaunched.configureSync(server)
    relaunched.activate(ownerID: owner)
    #expect(relaunched.store?.pendingCount == 3)

    server.reachable = true
    await relaunched.sync(force: true)
    #expect(relaunched.syncError == nil)
    #expect(relaunched.store?.pendingCount == 0)
    #expect(server.events.count == 3)
    #expect(relaunched.syncState.plainText(on: .iPhone).hasPrefix("Up to date"))
}

@Test @MainActor func lateEntriesNeedTheExplicitEditUnlockAsOnTheMac() async throws {
    let app = PhoneFixtures.make(.today, defaults: UserDefaults(suiteName: "phone-tests-\(UUID())")!)
    let tracker = app.tracker
    let yesterday = tracker.dates.calendar.date(byAdding: .day, value: -1, to: tracker.today)!
    tracker.selectHistoryDay(yesterday)
    #expect(!tracker.canEdit)
    let before = tracker.summary?.waterMillilitres
    tracker.addWater()
    #expect(tracker.summary?.waterMillilitres == before)
    #expect(tracker.errorMessage == "Select Edit this day before making a historical correction.")
    tracker.enableCorrections()
    tracker.addWater()
    #expect(tracker.summary?.waterMillilitres == (before ?? 0) + 450)
}

@Test @MainActor func todayFixtureShowsDayTwelveInProgressAfterAMissedDay() {
    let app = PhoneFixtures.make(.today, defaults: UserDefaults(suiteName: "phone-tests-\(UUID())")!)
    let tracker = app.tracker
    #expect(tracker.dayNumber == 12)
    #expect(tracker.summary?.waterMillilitres == 2_250)
    #expect(tracker.summary?.completedHabits == [.workout])
    #expect(tracker.summary?.diet == .clean)
    #expect(tracker.summary?.isComplete == false)
    // Day 5 (one week ago) was missed: four complete days before it, six since.
    #expect(tracker.streaks?.current == 6)
    #expect(tracker.streaks?.best == 6)
    tracker.toggle(.walk)
    tracker.toggle(.bibleReading)
    for _ in 0..<4 { tracker.addWater() }
    #expect(tracker.summary?.isComplete == true)
    #expect(tracker.streaks?.current == 7)
    #expect(tracker.streaks?.best == 7)
    tracker.undoWater()
    #expect(tracker.summary?.isComplete == false)
}

@Test @MainActor func iPhoneHistoryReadsActionKindsItDoesNotShow() throws {
    // Extras are a Mac feature for now; their events still sync to the phone and must
    // read as a generic change instead of breaking History.
    let activity = Challenge.Activity(id: UUID(), day: now, recordedAt: now,
                                      action: .setExtra(id: UUID(), completed: true), undonePourID: nil, deviceID: "Mac")
    #expect(ActivityWords.short(activity) == "Changed")
    #expect(ActivityWords.icon(activity).0 == "square.and.pencil")
}

@Test @MainActor func phoneRemindersQueueAheadAndUseTheIPhonesWording() async {
    let app = PhoneFixtures.make(.account, defaults: UserDefaults(suiteName: "phone-tests-\(UUID())")!)
    let reminders = try! #require(app.reminders)
    await reminders.settle()
    #expect(reminders.policy == .queued)
    #expect(reminders.settings.enabled)
    // 15:00 in Jersey with 2,250 ml: 15:00 has passed, so 16:30 … 21:00 today and nine slots tomorrow.
    #expect(reminders.scheduledDates.count == 13)
    #expect(reminders.status.contains("on this iPhone"))
}
