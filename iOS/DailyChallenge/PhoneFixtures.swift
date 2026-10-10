#if DEBUG
import ChallengeCore
import ChallengeSyncKit
import Foundation
import WidgetKit

/// Debug builds only: `-fixture <screen>` launches on offline fixture data in a temporary
/// folder, for UI tests and screenshots. No configuration, Keychain, network or
/// notification permission is touched, and Release (TestFlight) builds do not contain it.
@MainActor enum PhoneFixtures {
    enum Screen: String {
        case signIn, createAccount, forgotPassword, confirmCode, resetPassword
        case checking, setup, today, todayComplete, history, account, sharedToday, storageRecovery
        case todayExtras, extrasCap, historyExtras, historyExtrasEditing, accountExtras
    }

    static var isFixtureLaunch: Bool { ProcessInfo.processInfo.arguments.contains("-fixture") }

    static var scrollAnchor: String? {
        guard ProcessInfo.processInfo.arguments.contains("-fixture") else { return nil }
        return value(after: "-fixture-scroll-to", in: ProcessInfo.processInfo.arguments)
    }

    static var showingManagement: Bool {
        ProcessInfo.processInfo.arguments.contains("-fixture")
            && ProcessInfo.processInfo.arguments.contains("-manage-extras")
    }

    /// 9 October 2026, 15:00 in Jersey: a fixed clock keeps renders identical.
    static let now = ISO8601DateFormatter().date(from: "2026-10-09T14:00:00Z")!
    static let zone = TimeZone(identifier: "Europe/Jersey")!

    static func app(arguments: [String] = ProcessInfo.processInfo.arguments) -> PhoneApp? {
        if let variant = value(after: "-widget-fixture", in: arguments) {
            return widgetApp(variant: variant)
        }
        let screen: Screen
        if let index = arguments.firstIndex(of: "-fixture"), index + 1 < arguments.count,
           let requested = Screen(rawValue: arguments[index + 1]) {
            screen = requested
        } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
                    || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil {
            // The hosted unit-test app must also avoid production auth/storage, even
            // before any individual test constructs its own temporary fixture.
            screen = .today
        } else {
            return nil
        }
        let suite = "fixture-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        if let appearance = value(after: "-appearance", in: arguments) {
            defaults.set(appearance, forKey: PhoneApp.appearanceKey)
        }
        return make(screen, defaults: defaults)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static func make(_ screen: Screen, defaults: UserDefaults, directory: URL? = nil) -> PhoneApp {
        let owner = UUID(uuidString: "6F1C2A43-0B55-4B5E-9F3D-2C1A7E9B4D10")!
        let directory = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("daily-challenge-fixture-\(UUID().uuidString)", isDirectory: true)
        if screen == .sharedToday || screen == .storageRecovery {
            let oldRoot = directory.appendingPathComponent("old-phone")
            let groupRoot = directory.appendingPathComponent("fixture-group")
            let before = make(.today, defaults: defaults, directory: oldRoot)
            if screen == .storageRecovery {
                // Two valid, conflicting histories: the recovery UI must never
                // hide this behind empty setup or silently choose a winner.
                var conflicting = try! ChallengeStore(ownerID: owner, directory: groupRoot)
                try! conflicting.start(on: day(-11), timeZone: zone)
                try! conflicting.record(.pour(900), on: now, at: now)
            }
            let tracker = TrackerModel(directory: groupRoot, clock: { now },
                                       access: PhoneSharedStore(root: groupRoot, legacy: oldRoot))
            tracker.activate(ownerID: owner)
            return PhoneApp(auth: before.auth, tracker: tracker, reminders: before.reminders,
                            defaults: defaults, schedulesRefresh: false)
        }
        let auth: AuthModel
        switch screen {
        case .signIn: auth = AuthModel(fixtureOwnerID: nil, now: { now })
        case .createAccount: auth = AuthModel(fixtureOwnerID: nil, authStep: .createAccount, now: { now })
        case .forgotPassword: auth = AuthModel(fixtureOwnerID: nil, authStep: .forgotPassword, now: { now })
        case .confirmCode:
            auth = AuthModel(fixtureOwnerID: nil, authStep: .confirmSignUp(email: "sam@example.com"),
                             notice: "We emailed a code to sam@example.com. Enter it to finish creating your account.",
                             resendAvailableAt: now.addingTimeInterval(42), now: { now })
        case .resetPassword:
            auth = AuthModel(fixtureOwnerID: nil, authStep: .resetPassword(email: "sam@example.com"),
                             notice: "If sam@example.com has an account, we emailed it a code. Enter it with your new password.",
                             now: { now })
        default:
            auth = AuthModel(fixtureOwnerID: owner, email: "sam@example.com", now: { now })
        }
        let reminders = WaterReminderController(defaults: defaults, center: FixtureNotificationCenter(),
                                                wording: .iPhone, policy: .queued, clock: { now })
        let tracker = TrackerModel(directory: directory, clock: { now })
        let app = PhoneApp(auth: auth, tracker: tracker, reminders: reminders, defaults: defaults, schedulesRefresh: false)
        tracker.activate(ownerID: auth.ownerID)
        switch screen {
        case .checking:
            tracker.configureSync(UnreachableTransport())
        case .today, .todayComplete, .history, .account, .todayExtras, .extrasCap, .historyExtras, .historyExtrasEditing, .accountExtras:
            seed(tracker, complete: screen == .todayComplete)
            if [.todayExtras, .extrasCap, .historyExtras, .historyExtrasEditing, .accountExtras].contains(screen) {
                for title in ["Stretch", "Read a chapter", "Prepare tomorrow’s healthy lunch"] {
                    _ = tracker.addExtra(title)
                }
                if screen == .extrasCap {
                    for title in ["Practise gratitude", "Call family", "Tidy desk", "Journal", "Go outside", "Sleep on time", "A readable extra title of forty letters!"] {
                        _ = tracker.addExtra(title)
                    }
                }
                tracker.toggleExtra(tracker.activeExtras[0].id)
                if screen == .historyExtras || screen == .historyExtrasEditing {
                    let archived = tracker.activeExtras[1].id
                    tracker.selectHistoryDay(day(-2)); tracker.enableCorrections()
                    tracker.toggleExtra(archived)
                    _ = tracker.archiveExtra(archived)
                    tracker.selectHistoryDay(day(-2))
                    app.tab = .history
                    if screen == .historyExtrasEditing { tracker.enableCorrections() }
                }
            }
            if screen == .history { app.tab = .history; tracker.selectHistoryDay(day(-2)) }
            if screen == .account || screen == .accountExtras {
                app.tab = .account
                reminders.update(.init(enabled: true))
            }
        default:
            break
        }
        return app
    }

    /// Explicit Debug launch publishes synthetic data in a separate group root.
    /// `reopen` relaunches on the existing fixture history (for example after widget
    /// taps while the app was terminated) instead of reseeding it.
    private static func widgetApp(variant: String) -> PhoneApp {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PhoneSharedStore.groupID)!
        let root = container.appendingPathComponent("WidgetFixtures")
        let reopen = variant == "reopen"
        if !reopen, FileManager.default.fileExists(atPath: root.path) { try! FileManager.default.removeItem(at: root) }
        let shared = PhoneSharedStore(root: root)
        shared.onCommitted = { WidgetCenter.shared.reloadAllTimelines() }
        let owner = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let auth = { (now: Date) in AuthModel(fixtureOwnerID: owner, now: { now }) }
        if reopen {
            let tracker = TrackerModel(directory: root, access: shared)
            tracker.activate(ownerID: owner)
            return PhoneApp(auth: auth(Date()), tracker: tracker, reminders: nil,
                            defaults: UserDefaults(suiteName: "widget-fixture-\(UUID())")!, schedulesRefresh: false)
        }
        let now = Date()
        let tracker = TrackerModel(directory: root, clock: { now }, access: shared)
        // Widget account states (phase 5): signed out publishes no account; setup publishes
        // the account without a challenge; unavailable leaves unreadable account metadata.
        if variant == "signed-out" || variant == "setup" {
            tracker.activate(ownerID: variant == "setup" ? owner : nil)
            try! Data("synthetic Debug fixtures only".utf8).write(to: container.appendingPathComponent("widget-fixture-enabled"), options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
            return PhoneApp(auth: AuthModel(fixtureOwnerID: variant == "setup" ? owner : nil, now: { now }), tracker: tracker,
                            reminders: nil, defaults: UserDefaults(suiteName: "widget-fixture-\(UUID())")!, schedulesRefresh: false)
        }
        tracker.activate(ownerID: owner)
        tracker.startChallenge(on: now, timeZone: zone)
        let amount: Int = switch variant {
        case "empty", "pending", "extras-empty": 0
        case "full", "complete": 4_000
        case "overflow": 4_500
        default: 2_250
        }
        if amount > 0 { tracker.addWater(amount) }
        if variant != "pending" && variant != "empty" {
            tracker.toggle(.workout)
            tracker.setDiet(variant == "missed" ? .missed : .clean)
        }
        if variant == "complete" { tracker.toggle(.walk); tracker.toggle(.bibleReading) }
        if variant != "extras-empty" && variant != "empty" {
            let count = ["extras-ten", "long-names", "overflow"].contains(variant) ? 10 : 3
            for title in widgetExtraTitles(longNames: variant == "long-names").prefix(count) { _ = tracker.addExtra(title) }
            if let first = tracker.activeExtras.first { tracker.toggleExtra(first.id) }
        }
        if variant == "unavailable" {
            try! Data("not account metadata".utf8).write(to: root.appendingPathComponent("active-account.json"), options: .atomic)
        }
        try! Data("synthetic Debug fixtures only".utf8).write(to: container.appendingPathComponent("widget-fixture-enabled"), options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
        return PhoneApp(auth: auth(now), tracker: tracker,
                        reminders: nil, defaults: UserDefaults(suiteName: "widget-fixture-\(UUID())")!, schedulesRefresh: false)
    }

    /// Synthetic extras for widget fixtures; `longNames` gives ten maximum-length (40) titles.
    nonisolated static func widgetExtraTitles(longNames: Bool) -> [String] {
        guard longNames else {
            return ["Stretch", "Read a chapter", "Prepare tomorrow’s healthy lunch", "Practise gratitude", "Call family",
                    "Tidy desk", "Journal", "Go outside", "Sleep on time", "A readable extra title of forty letters!"]
        }
        return (1...10).map { "\($0). Prepare tomorrow’s healthy lunch box".padding(toLength: 40, withPad: "!", startingAt: 0) }
    }

    private static func day(_ offset: Int) -> Date {
        let calendar = Challenge.calendar(for: zone)
        return calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
            .addingTimeInterval(12 * 3_600)
    }

    /// Twelve days in: ten complete, one missed, and today in progress (or complete).
    private static func seed(_ tracker: TrackerModel, complete: Bool) {
        tracker.startChallenge(on: day(-11), timeZone: zone)
        for offset in -11 ... -1 where offset != -7 {
            tracker.selectHistoryDay(day(offset))
            tracker.enableCorrections()
            for _ in 0..<9 { tracker.addWater() }
            tracker.toggle(.workout)
            tracker.toggle(.walk)
            tracker.setDiet(.clean)
            tracker.toggle(.bibleReading)
        }
        tracker.selectHistoryDay(day(-7))
        tracker.enableCorrections()
        tracker.addWater(1_800)
        tracker.toggle(.workout)
        tracker.showToday()
        for _ in 0..<(complete ? 9 : 5) { tracker.addWater() }
        tracker.toggle(.workout)
        tracker.setDiet(.clean)
        if complete {
            tracker.toggle(.walk)
            tracker.toggle(.bibleReading)
        }
    }
}

/// Reports permission as allowed and keeps requests in memory only.
@MainActor final class FixtureNotificationCenter: WaterNotificationCenter {
    func permission() async -> WaterNotificationPermission { .allowed }
    func requestPermission() async throws {}
    func cancel() {}
    func schedule(at date: Date, timeZone: TimeZone) async throws {}
}

/// A server that cannot be reached, so setup waits on "Checking for your existing challenge".
@MainActor final class UnreachableTransport: ChallengeTransport {
    func fetchChallenge(ownerID: UUID) async throws -> ChallengeRecord? { throw URLError(.notConnectedToInternet) }
    func insertChallenge(_ record: ChallengeRecord) async throws { throw URLError(.notConnectedToInternet) }
    func upload(_ events: [ChallengeEvent], ownerID: UUID) async throws { throw URLError(.notConnectedToInternet) }
    func fetchEvents(ownerID: UUID, challengeID: UUID) async throws -> RemoteEvents { throw URLError(.notConnectedToInternet) }
}
#endif
