import AppKit
import SwiftUI

@main
struct DailyChallengeProofApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        // The popup is the app's own status item and panel (PopupController); no window scene.
        Settings { EmptyView() }
            .commandsRemoved()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var popup: PopupController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, also when run without the bundle's LSUIElement.
        NSApp.setActivationPolicy(.accessory)
        let auth = ProofModel()
        let tracker = TrackerModel()
        let reminders = WaterReminderController(defaults: .standard, center: NativeWaterNotificationCenter())
        tracker.reminders = reminders
        reminders.start { [weak tracker] in tracker?.refreshReminders() }
        auth.attachTracker(tracker)
        auth.start()
        // The app's single Sparkle updater; it checks daily once started.
        let updates = SoftwareUpdates()
        popup = PopupController(content: TrackerPopup(model: tracker, auth: auth, appearance: AppAppearance())
            .environment(updates))
    }
}
