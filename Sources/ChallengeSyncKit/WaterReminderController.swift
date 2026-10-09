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
    func cancel()
    func schedule(at date: Date, timeZone: TimeZone) async throws
}

/// Owns just one identifier; never removes another feature's notifications.
@MainActor
public final class NativeWaterNotificationCenter: NSObject, WaterNotificationCenter, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let identifier = "daily-challenge.water.next"

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
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    public func schedule(at date: Date, timeZone: TimeZone) async throws {
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

/// Reconciles independently of any window's lifetime. A short rolling horizon
/// keeps at most one pending request. Sleep clears it; wake plans future slots
/// only. The system still owns actual delivery (including Focus and system delays).
/// Each app drives `sleep()`, `wake()` and periodic refreshes from its own lifecycle.
@MainActor @Observable
public final class WaterReminderController {
    public static let defaultsKey = "water-reminders.device.v1"
    public private(set) var settings: WaterReminderSettings
    public private(set) var permission: WaterNotificationPermission = .unknown
    public private(set) var errorMessage: String?
    public private(set) var scheduledDate: Date?
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
                clock: @escaping () -> Date = Date.init) {
        self.wording = wording
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
            scheduledDate = nil
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
            let next = WaterReminderPlanner(timeZone: zone, clock: { now }).upcoming(
                settings: settings, through: now.addingTimeInterval(60),
                waterMillilitres: { waterByDay[$0] }).first
            let desired = !asleep && permission == .allowed ? next : nil
            if desired != scheduledDate || desired == nil {
                center.cancel()
                scheduledDate = nil
                if let desired {
                    do {
                        try await center.schedule(at: desired, timeZone: zone)
                        if token == revision { scheduledDate = desired; errorMessage = nil }
                    } catch { errorMessage = "Could not schedule water reminder: \(error.localizedDescription)" }
                }
            }
            if token == revision { worker = nil; return }
            center.cancel() // A stale async add must not survive a new total/account/settings.
        }
    }
}
