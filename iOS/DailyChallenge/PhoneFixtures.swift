#if DEBUG
import ChallengeCore
import ChallengeSyncKit
import Foundation

/// Debug builds only: `-fixture <screen>` launches on offline fixture data in a temporary
/// folder, for UI tests and screenshots. No configuration, Keychain, network or
/// notification permission is touched, and Release (TestFlight) builds do not contain it.
@MainActor enum PhoneFixtures {
    enum Screen: String {
        case signIn, createAccount, forgotPassword, confirmCode, resetPassword
        case checking, setup, today, todayComplete, history, account
    }

    /// 9 October 2026, 15:00 in Jersey: a fixed clock keeps renders identical.
    static let now = ISO8601DateFormatter().date(from: "2026-10-09T14:00:00Z")!
    static let zone = TimeZone(identifier: "Europe/Jersey")!

    static func app(arguments: [String] = ProcessInfo.processInfo.arguments) -> PhoneApp? {
        guard let index = arguments.firstIndex(of: "-fixture"), index + 1 < arguments.count,
              let screen = Screen(rawValue: arguments[index + 1]) else { return nil }
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

    static func make(_ screen: Screen, defaults: UserDefaults) -> PhoneApp {
        let owner = UUID(uuidString: "6F1C2A43-0B55-4B5E-9F3D-2C1A7E9B4D10")!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("daily-challenge-fixture-\(UUID().uuidString)", isDirectory: true)
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
        case .today, .todayComplete, .history, .account:
            seed(tracker, complete: screen == .todayComplete)
            if screen == .history { app.tab = .history; tracker.selectHistoryDay(day(-2)) }
            if screen == .account {
                app.tab = .account
                reminders.update(.init(enabled: true))
            }
        default:
            break
        }
        return app
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
