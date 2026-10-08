import AppKit
import ChallengeCore
import Foundation
import SwiftUI
import Testing
@testable import DailyChallengeProof

@MainActor private final class AccountTransport: ChallengeTransport {
    var header: ChallengeRecord?
    var events: [ChallengeEvent] = []
    var failure: Error?
    let receivedAt: String
    init(receivedAt: Date) { self.receivedAt = receivedAt.ISO8601Format() }
    func fetchChallenge(ownerID: UUID) async throws -> ChallengeRecord? {
        if let failure { throw failure }
        return header
    }
    func insertChallenge(_ record: ChallengeRecord) async throws { header = record }
    func upload(_ incoming: [ChallengeEvent], ownerID: UUID) async throws {
        events += incoming.map { ChallengeEvent(ownerID: ownerID, challengeID: $0.challengeID, activity: $0.activity, receivedAt: receivedAt) }
    }
    func fetchEvents(ownerID: UUID, challengeID: UUID) async throws -> [ChallengeEvent] { events }
}

@MainActor private final class SilentWaterCenter: WaterNotificationCenter {
    func permission() async -> WaterNotificationPermission { .allowed }
    func requestPermission() async throws {}
    func cancel() {}
    func schedule(at date: Date) async throws {}
}

@Suite(.serialized) @MainActor
struct AccountViewTests {
    private let checked = ISO8601DateFormatter().date(from: "2026-10-08T19:11:00Z")!
    private var time: String { checked.formatted(date: .omitted, time: .shortened) }

    @Test func footerWordingIsUnchanged() {
        #expect(SyncState.localOnly.footerText == "Local only · Not synced")
        #expect(SyncState.unavailable(pending: 2, error: "Offline").footerText == "Sync unavailable · 2 pending · Offline")
        #expect(SyncState.checking(pending: 1).footerText == "Checking sync · 1 pending")
        #expect(SyncState.savedLocally(pending: 3).footerText == "Saved locally · 3 pending")
        #expect(SyncState.awaitingCheck.footerText == "Waiting for server check")
        #expect(SyncState.synced(at: checked, clockWarning: false).footerText == "Synced · \(time)")
        #expect(SyncState.synced(at: checked, clockWarning: true).footerText == "Synced · \(time) · Clock/delivery delay > 5 min")
    }

    @Test func accountWordingIsPlain() {
        #expect(SyncState.synced(at: checked, clockWarning: false).plainText == "Up to date, checked \(time)")
        #expect(SyncState.savedLocally(pending: 3).plainText == "Saved on this Mac, 3 changes waiting")
        #expect(SyncState.savedLocally(pending: 1).plainText == "Saved on this Mac, 1 change waiting")
        #expect(SyncState.unavailable(pending: 2, error: "Offline").plainText == "Can't reach the server, your entries are safe")
        #expect(SyncState.synced(at: checked, clockWarning: true).clockWarningText
            == "Some entries arrived late; check your Mac's clock if this keeps happening")
        #expect(SyncState.synced(at: checked, clockWarning: false).clockWarningText == nil)
        let all: [SyncState] = [.localOnly, .unavailable(pending: 1, error: "x"), .checking(pending: 0), .checking(pending: 2),
                                .savedLocally(pending: 2), .awaitingCheck, .synced(at: checked, clockWarning: true)]
        for state in all {
            let text = (state.plainText + " " + (state.clockWarningText ?? "")).lowercased()
            for word in ["probe", "queue", "rls", "diagnostic", "pending"] {
                #expect(!text.contains(word), "\(state): internal word \(word)")
            }
        }
    }

    @Test func dayLineFollowsTheChallenge() {
        let start = JerseyDates.calendar.date(from: DateComponents(year: 2026, month: 9, day: 27))!
        #expect(AccountView.progress(day: 12, startDate: start, bestStreak: 11) == "Day 12 of 75 · started Sun 27 Sep")
        #expect(AccountView.progress(day: 75, startDate: start, bestStreak: 75) == "Day 75 of 75 · started Sun 27 Sep")
        #expect(AccountView.progress(day: 80, startDate: start, bestStreak: 75) == "Day 80 · 75 reached · started Sun 27 Sep")
        #expect(AccountView.progress(day: 80, startDate: start, bestStreak: 30) == "Day 80 · started Sun 27 Sep")
    }

    @Test func updatesNeedBothFeedKeys() {
        let key = "FDHqOv6JLXUwHrPD+gIPAntg5PxObLU3Y3RhVGx279g="
        #expect(SoftwareUpdates.isConfigured(["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": key]))
        #expect(!SoftwareUpdates.isConfigured(["SUFeedURL": "https://example.com/appcast.xml"]))
        #expect(!SoftwareUpdates.isConfigured(["SUPublicEDKey": key]))
        #expect(!SoftwareUpdates.isConfigured(["SUFeedURL": "", "SUPublicEDKey": key]))
        #expect(!SoftwareUpdates.isConfigured([:]))
    }

    /// A bundle without a feed (here the test runner) must never start Sparkle.
    @Test func unconfiguredBuildNeverStartsTheUpdater() {
        let updates = SoftwareUpdates(bundle: Bundle(for: SoftwareUpdates.self))
        #expect(!updates.isConfigured)
        #expect(updates.updater == nil)
        #expect(!updates.canCheck)
        updates.checkForUpdates()
        #expect(updates.availableVersion == nil)
    }

    @Test func accountAndFooterShareOneSyncSource() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = TrackerModel(directory: directory, clock: { checked })
        model.activate(ownerID: UUID())
        model.startChallenge(on: checked)
        model.addWater()
        let transport = AccountTransport(receivedAt: checked)
        model.configureSync(transport)
        #expect(model.syncState == .savedLocally(pending: 2))
        await model.sync(force: true)
        #expect(model.syncState == .synced(at: checked, clockWarning: false))
        transport.failure = URLError(.notConnectedToInternet)
        model.addWater()
        await model.sync(force: true)
        guard case .unavailable(pending: 1, _) = model.syncState else {
            Issue.record("Expected unavailable, got \(model.syncState)"); return
        }
        #expect(model.syncStatus == model.syncState.footerText)
        #expect(model.syncState.plainText == "Can't reach the server, your entries are safe")
    }

    /// Offline fixture account, temporary directories and an injected notification
    /// centre; no Keychain, network or real data. Set DAILY_CHALLENGE_SNAPSHOT_DIR to
    /// write the light/dark PNGs kept in docs/screenshots/account-tab/.
    @Test func accountTabRendersInLightAndDark() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "AccountViewTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let previous = NSApplication.shared.appearance
        defer {
            NSApplication.shared.appearance = previous
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let clock = checked
        let owner = UUID()
        let model = TrackerModel(directory: directory, clock: { clock })
        model.activate(ownerID: owner)
        model.startChallenge(on: JerseyDates.calendar.date(from: DateComponents(year: 2026, month: 9, day: 27))!)
        model.addWater()
        let reminders = WaterReminderController(defaults: defaults, center: SilentWaterCenter(), clock: { clock })
        model.reminders = reminders
        model.refreshReminders()
        await reminders.settle()
        model.configureSync(AccountTransport(receivedAt: checked))
        await model.sync(force: true)
        #expect(model.dayNumber == 12)
        let auth = ProofModel(fixtureOwnerID: owner, directory: directory)
        let appearance = AppAppearance(defaults: defaults)
        let version = try Self.shippedVersion()
        let updates = SoftwareUpdates(fixtureAvailableVersion: nil)

        for expanded in [false, true] {
            let view = AccountView(auth: auth, tracker: model, version: version, showsAdvanced: expanded)
                .padding(16).frame(width: 420)
                .environment(appearance)
                .environment(updates)
                .environment(\.calendar, JerseyDates.calendar)
                .environment(\.timeZone, JerseyDates.calendar.timeZone)
                .trackerSurface()
            try render(view, name: expanded ? "account-tab-advanced" : "account-tab", appearance: appearance)
        }
        // The Change password row opened, with a mismatch the form explains.
        auth.newPassword = "secret-1"
        auth.passwordConfirmation = "secret-2"
        let passwordForm = AccountView(auth: auth, tracker: model, version: version, changingPassword: true)
            .padding(16).frame(width: 420)
            .environment(appearance)
            .environment(updates)
            .environment(\.calendar, JerseyDates.calendar)
            .environment(\.timeZone, JerseyDates.calendar.timeZone)
            .trackerSurface()
        try render(passwordForm, name: "account-tab-change-password", appearance: appearance)
        // A background check found a version Sparkle left waiting in About.
        let updateWaiting = AccountView(auth: auth, tracker: model, version: version)
            .padding(16).frame(width: 420)
            .environment(appearance)
            .environment(SoftwareUpdates(fixtureAvailableVersion: "0.3.0"))
            .environment(\.calendar, JerseyDates.calendar)
            .environment(\.timeZone, JerseyDates.calendar.timeZone)
            .trackerSurface()
        try render(updateWaiting, name: "account-tab-update-available", appearance: appearance)
        auth.newPassword = ""
        auth.passwordConfirmation = ""
        try render(TrackerPopup(model: model, auth: auth, appearance: appearance, section: .account).environment(updates),
                   name: "account-tab-popup", appearance: appearance)
    }

    private static func shippedVersion() throws -> String {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("VERSION")
        let line = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
            .first { $0.hasPrefix("CFBundleShortVersionString=") }
        return String(try #require(line).split(separator: "=")[1])
    }

    private func render<Content: View>(_ content: Content, name: String, appearance: AppAppearance) throws {
        let host = NSHostingView(rootView: content)
        host.sizingOptions = [.intrinsicContentSize]
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 640), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        for preference in [AppearancePreference.light, .dark] {
            appearance.preference = preference
            window.setContentSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let pixel = try #require(bitmap.colorAt(x: 2, y: 2)?.usingColorSpace(.deviceRGB))
            #expect(pixel.alphaComponent > 0.99, "\(name): opaque backing")
            if preference == .light { #expect(pixel.redComponent > 0.75, "\(name): Light backing") }
            if preference == .dark { #expect(pixel.redComponent < 0.3, "\(name): Dark backing") }
            guard let output = ProcessInfo.processInfo.environment["DAILY_CHALLENGE_SNAPSHOT_DIR"] else { continue }
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(name)-\(preference.rawValue).png"))
        }
    }
}
