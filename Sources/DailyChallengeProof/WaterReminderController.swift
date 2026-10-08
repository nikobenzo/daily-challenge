import AppKit
import ChallengeCore
import Foundation
import Observation
import UserNotifications

enum WaterNotificationPermission: Equatable {
    case notDetermined, denied, allowed, unknown
}

@MainActor
protocol WaterNotificationCenter: AnyObject {
    func permission() async -> WaterNotificationPermission
    func requestPermission() async throws
    func cancel()
    func schedule(at date: Date, timeZone: TimeZone) async throws
}

/// Owns just one identifier; never removes another feature's notifications.
@MainActor
final class NativeWaterNotificationCenter: NSObject, WaterNotificationCenter, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let identifier = "daily-challenge.water.next"

    override init() {
        super.init()
        center.delegate = self
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func permission() async -> WaterNotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .allowed
        @unknown default: .unknown
        }
    }

    func requestPermission() async throws {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func schedule(at date: Date, timeZone: TimeZone) async throws {
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

/// Reconciles independently of the popup's lifetime. A short rolling horizon
/// keeps at most one pending request. Sleep clears it; wake plans future slots
/// only. macOS still owns actual delivery (including Focus and system delays).
@MainActor @Observable
final class WaterReminderController {
    static let defaultsKey = "water-reminders.device.v1"
    private(set) var settings: WaterReminderSettings
    private(set) var permission: WaterNotificationPermission = .unknown
    private(set) var errorMessage: String?
    private(set) var scheduledDate: Date?
    /// The challenge's zone: the reminder window is wall-clock time there.
    private(set) var timeZone: TimeZone = .current
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
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults, center: any WaterNotificationCenter,
         clock: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.center = center
        self.clock = clock
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(WaterReminderSettings.self, from: data), decoded.isValid {
            settings = decoded
        } else { settings = WaterReminderSettings() }
    }

    var status: String {
        switch permission {
        case .notDetermined: return "Permission not determined. Toggle reminders off/on to request notifications."
        case .denied: return "Notifications denied. Open System Settings > Notifications > Daily Challenge."
        case .unknown: return "Checking notification permission."
        case .allowed:
            if !settings.enabled { return "Permission allowed · Reminders off on this Mac." }
            if water == nil { return "Permission allowed · Waiting for a local challenge." }
            if water! >= 4_000 { return "Permission allowed · Today's water goal met." }
            return "Permission allowed · Reminders enabled on this Mac. Delivery depends on macOS and Focus."
        }
    }

    func update(_ settings: WaterReminderSettings) {
        guard settings.isValid else { return }
        let enabling = settings.enabled && !self.settings.enabled
        self.settings = settings
        defaults.set(try? JSONEncoder().encode(settings), forKey: Self.defaultsKey)
        requestAuthorization = settings.enabled && (requestAuthorization || enabling)
        changed()
    }

    func refresh(waterMillilitres: Int?, nextDayWaterMillilitres: Int? = nil, timeZone: TimeZone) {
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

    func sleep() {
        asleep = true
        changed()
    }

    func wake() {
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
    func settle() async { await worker?.value }

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

    func start(refresh: @escaping @MainActor () -> Void) {
        guard timer == nil else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleep() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.wake(); refresh() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleep() }
        })
        timer = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                refresh()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }
}
