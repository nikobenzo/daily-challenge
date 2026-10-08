import AppKit
import UserNotifications

// Standalone fixture: no tracker, account, network, defaults or Keychain access.
// Run only via test-notification-fixture.sh, never with the production bundle ID.
final class FixtureDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        print("fixture bundle: \(Bundle.main.bundleIdentifier ?? "missing")")
        center.getNotificationSettings { settings in
            print("initial authorization status: \(settings.authorizationStatus.rawValue)")
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                print("authorization granted: \(granted); error: \(String(describing: error))")
                guard granted else { self.finish() ; return }
                let content = UNMutableNotificationContent()
                content.title = "Daily Challenge FIXTURE — notification test"
                content.body = "Isolated delivery test only. No water action is requested."
                let request = UNNotificationRequest(identifier: "fixture-delivery", content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false))
                center.add(request) { error in
                    print("schedule error: \(String(describing: error))")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                        center.getDeliveredNotifications { delivered in
                            print("delivered fixture count: \(delivered.count)")
                            center.removeAllPendingNotificationRequests()
                            center.removeAllDeliveredNotifications()
                            self.finish()
                        }
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            print("Fixture timed out: authorization/delivery not verified; no system settings changed by fixture.")
            center.removeAllPendingNotificationRequests()
            self.finish()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    private func finish() {
        fflush(stdout)
        DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
    }
}

let app = NSApplication.shared
let delegate = FixtureDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
