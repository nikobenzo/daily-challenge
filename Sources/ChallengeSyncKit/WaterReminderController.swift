import ChallengeCore
import Foundation
import Observation
import UserNotifications

public enum WaterNotificationPermission: Equatable, Sendable {
    case notDetermined, denied, allowed, unknown
}

@MainActor
public protocol WaterNotificationCenter: AnyObject {
    func permission() async -> WaterNotificationPermission
    func requestPermission() async throws
    /// Removes every pending water reminder this app scheduled.
    func cancel()
    func schedule(at date: Date, timeZone: TimeZone) async throws
    /// Queues several reminders at once (`ReminderPolicy.queued`); `cancel()` removes them all.
    func schedule(_ dates: [Date], timeZone: TimeZone) async throws
}

extension WaterNotificationCenter {
    /// A centre that holds one request at a time keeps only the earliest date.
    public func schedule(_ dates: [Date], timeZone: TimeZone) async throws {
        if let first = dates.first { try await schedule(at: first, timeZone: timeZone) }
    }
}

/// Owns only its own identifiers; never removes another feature's notifications.
@MainActor
public final class NativeWaterNotificationCenter: NSObject, WaterNotificationCenter, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let identifier = "daily-challenge.water.next"
    /// Queued reminders use numbered identifiers below this bound (iOS keeps at most 64 pending).
    private static let queuedLimit = ReminderPolicy.queuedLimit

    override public init() {
        super.init()
        center.delegate = self
    }

    public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    public func permission() async -> WaterNotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .allowed
        @unknown default: .unknown
        }
    }

    public func requestPermission() async throws {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
    }

    public func cancel() {
        center.removePendingNotificationRequests(
            withIdentifiers: [identifier] + (0..<Self.queuedLimit).map { "\(identifier).\($0)" })
    }

    public func schedule(at date: Date, timeZone: TimeZone) async throws {
        try await add(identifier: identifier, at: date, timeZone: timeZone)
    }

    public func schedule(_ dates: [Date], timeZone: TimeZone) async throws {
        for (index, date) in dates.prefix(Self.queuedLimit).enumerated() {
            try await add(identifier: "\(identifier).\(index)", at: date, timeZone: timeZone)
        }
    }

    private func add(identifier: String, at date: Date, timeZone: TimeZone) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Water check-in"
        content.body = "Check today's water log. If you're below 4,000 ml, drink only what you still need toward your goal."
        content.sound = .default
        let calendar = Challenge.calendar(for: timeZone)
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        components.timeZone = timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}

/// How far ahead reminders are handed to the system.
public enum ReminderPolicy: Sendable, Equatable {
    /// At most one request within the next minute, re-planned every few seconds while
    /// the app runs (the Mac: a menu-bar app that stays running and awake).
    case nextSlot
    /// Every remaining slot today and tomorrow, so reminders still arrive while the
    /// app is suspended (iOS). Re-planned whenever the app learns a new total.
    case queued

    static let queuedLimit = 48

    func horizon(from now: Date) -> Date {
        switch self {
        case .nextSlot: now.addingTimeInterval(60)
        case .queued: now.addingTimeInterval(48 * 3_600)
        }
    }
}

/// Reconciles independently of any window's lifetime. With `.nextSlot`, a short rolling
/// horizon keeps at most one pending request; with `.queued`, the remaining slots of
/// today and tomorrow are pending. Sleep clears them; wake plans future slots only.
/// The system still owns actual delivery (including Focus and system delays).
/// Each app drives `sleep()`, `wake()` and periodic refreshes from its own lifecycle.
@MainActor @Observable
public final class WaterReminderController {
    public static let defaultsKey = "water-reminders.device.v1"
    public private(set) var settings: WaterReminderSettings
    public private(set) var permission: WaterNotificationPermission = .unknown
    public private(set) var errorMessage: String?
    /// The earliest pending reminder.
    public var scheduledDate: Date? { scheduledDates.first }
    public private(set) var scheduledDates: [Date] = []
    public let policy: ReminderPolicy
    /// The challenge's zone: the reminder window is wall-clock time there.
    public private(set) var timeZone: TimeZone = .current
    public let wording: DeviceWording
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let center: any WaterNotificationCenter
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var waterByDay: [Date: Int] = [:]
    private var calendar: Calendar { Challenge.calendar(for: timeZone) }
    private var water: Int? { waterByDay[calendar.startOfDay(for: clock())] }
    @ObservationIgnored private var asleep = false
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var requestAuthorization = false
    @ObservationIgnored private var worker: Task<Void, Never>?

    public init(defaults: UserDefaults, center: any WaterNotificationCenter, wording: DeviceWording,
                policy: ReminderPolicy = .nextSlot, clock: @escaping () -> Date = Date.init) {
        self.wording = wording
        self.policy = policy
        self.defaults = defaults
        self.center = center
        self.clock = clock
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(WaterReminderSettings.self, from: data), decoded.isValid {
            settings = decoded
        } else { settings = WaterReminderSettings() }
    }

    public var status: String {
        switch permission {
        case .notDetermined: return "Permission not determined. Toggle reminders off/on to request notifications."
        case .denied: return "Notifications denied. Open \(wording.notificationSettings)."
        case .unknown: return "Checking notification permission."
        case .allowed:
            if !settings.enabled { return "Permission allowed · Reminders off on this \(wording.device)." }
            if water == nil { return "Permission allowed · Waiting for a local challenge." }
            if water! >= 4_000 { return "Permission allowed · Today's water goal met." }
            return "Permission allowed · Reminders enabled on this \(wording.device). Delivery depends on \(wording.system) and Focus."
        }
    }

    public func update(_ settings: WaterReminderSettings) {
        guard settings.isValid else { return }
        let enabling = settings.enabled && !self.settings.enabled
        self.settings = settings
        defaults.set(try? JSONEncoder().encode(settings), forKey: Self.defaultsKey)
        requestAuthorization = settings.enabled && (requestAuthorization || enabling)
        changed()
    }

    public func refresh(waterMillilitres: Int?, nextDayWaterMillilitres: Int? = nil, timeZone: TimeZone) {
        let zoneChanged = self.timeZone != timeZone
        self.timeZone = timeZone
        let day = calendar.startOfDay(for: clock())
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        var totals: [Date: Int] = [:]
        totals[day] = waterMillilitres
        totals[nextDay] = nextDayWaterMillilitres
        let totalsChanged = waterByDay != totals || zoneChanged
        waterByDay = totals
        changed(cancel: totalsChanged)
    }

    public func sleep() {
        asleep = true
        changed()
    }

    public func wake() {
        asleep = false
        changed()
    }

    private func changed(cancel: Bool = true) {
        revision += 1
        // Synchronous cancellation even if a previous async add is still in flight.
        if cancel {
            center.cancel()
            scheduledDates = []
        }
        guard worker == nil else { return }
        worker = Task { await reconcile() }
    }

    /// Exposed to fixture tests so they can wait for all serialized work.
    public func settle() async { await worker?.value }

    private func reconcile() async {
        while true {
            let token = revision
            if requestAuthorization {
                requestAuthorization = false
                do { try await center.requestPermission(); errorMessage = nil }
                catch { errorMessage = "Notification permission failed: \(error.localizedDescription)" }
            }
            permission = await center.permission()
            guard token == revision else { continue }
            let now = clock()
            let zone = timeZone
            let upcoming = WaterReminderPlanner(timeZone: zone, clock: { now }).upcoming(
                settings: settings, through: policy.horizon(from: now),
                waterMillilitres: { waterByDay[$0] })
            let planned = policy == .nextSlot ? Array(upcoming.prefix(1)) : Array(upcoming.prefix(ReminderPolicy.queuedLimit))
            let desired = !asleep && permission == .allowed ? planned : []
            if desired != scheduledDates || desired.isEmpty {
                center.cancel()
                scheduledDates = []
                if !desired.isEmpty {
                    do {
                        if policy == .nextSlot {
                            try await center.schedule(at: desired[0], timeZone: zone)
                        } else {
                            try await center.schedule(desired, timeZone: zone)
                        }
                        if token == revision { scheduledDates = desired; errorMessage = nil }
                    } catch { errorMessage = "Could not schedule water reminder: \(error.localizedDescription)" }
                }
            }
            if token == revision { worker = nil; return }
            center.cancel() // A stale async add must not survive a new total/account/settings.
        }
    }
}
