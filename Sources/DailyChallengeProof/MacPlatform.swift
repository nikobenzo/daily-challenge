import AppKit
import ChallengeSyncKit
import Foundation

/// The Mac's wording for the shared sync state ("Saved on this Mac …").
extension SyncState {
    var plainText: String { plainText(on: .mac) }
    var clockWarningText: String? { clockWarningText(on: .mac) }
}

/// Drives the shared reminder controller from the Mac's lifecycle: system sleep clears
/// the pending reminder, wake plans future slots only, and a 15-second refresh keeps
/// the plan current while the app runs.
@MainActor
final class MacReminderLifecycle {
    private let reminders: WaterReminderController
    private var timer: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(reminders: WaterReminderController) { self.reminders = reminders }

    func start(refresh: @escaping @MainActor () -> Void) {
        guard timer == nil else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reminders.sleep() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reminders.wake(); refresh() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reminders.sleep() }
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
