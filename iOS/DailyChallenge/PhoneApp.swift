import BackgroundTasks
import ChallengeCore
import ChallengeSyncKit
import Observation
import SwiftUI

enum PhoneTab: Hashable { case today, history, account }

/// Device-local appearance: System follows iOS. Never synced.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The iPhone app's composition root: the shared auth, tracker and reminder models
/// (ChallengeSyncKit), wired to the phone's lifecycle.
@MainActor @Observable
final class PhoneApp {
    static let refreshTaskID = "app.daily-challenge.ios.refresh"
    /// The iPhone's own Keychain items; only session tokens are stored there.
    static let sessionStorage = SessionStorage(keychainService: "app.daily-challenge.ios.auth",
                                               storageKey: "daily-challenge-ios-session")
    static let appearanceKey = "appearancePreference"

    let auth: AuthModel
    let tracker: TrackerModel
    let reminders: WaterReminderController?
    var tab = PhoneTab.today
    var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let schedulesRefresh: Bool

    init(auth: AuthModel, tracker: TrackerModel, reminders: WaterReminderController?,
         defaults: UserDefaults, schedulesRefresh: Bool) {
        self.auth = auth
        self.tracker = tracker
        self.reminders = reminders
        self.defaults = defaults
        self.schedulesRefresh = schedulesRefresh
        appearance = AppearancePreference(rawValue: defaults.string(forKey: Self.appearanceKey) ?? "") ?? .system
        tracker.reminders = reminders
    }

    /// The real app: bundled configuration, the iPhone's Keychain items, local
    /// notifications that stay queued while the app is suspended.
    static func production() -> PhoneApp {
        let auth = AuthModel(storage: sessionStorage, missingConfiguration:
            "This build has no server configuration. Build it with .env.local at the repository root (docs/ios-testflight.md).")
        let reminders = WaterReminderController(defaults: .standard, center: NativeWaterNotificationCenter(),
                                                wording: .iPhone, policy: .queued)
        let app = PhoneApp(auth: auth, tracker: TrackerModel(), reminders: reminders,
                           defaults: .standard, schedulesRefresh: true)
        auth.attachTracker(app.tracker)
        auth.start()
        return app
    }

    /// Foreground: catch up on the day, reminders and the server, as the Mac does when its popup opens.
    func becameActive() {
        tracker.refresh()
        tracker.requestSync()
    }

    /// Leaving the foreground: ask iOS for a later refresh so other devices' entries
    /// (and a goal met elsewhere) reach this phone and its queued reminders.
    func enteredBackground() {
        guard schedulesRefresh, auth.ownerID != nil else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// One background refresh: sync once, re-plan reminders, ask for the next refresh.
    func backgroundRefresh() async {
        enteredBackground()
        tracker.refresh()
        await tracker.sync(force: true)
        tracker.refreshReminders()
        await reminders?.settle()
    }
}
