import AppKit
import SwiftUI

@main
struct DailyChallengeProofApp: App {
    @State private var model: ProofModel
    @State private var tracker: TrackerModel
    @State private var appearance = AppAppearance()
    @State private var updates: SoftwareUpdates
    @State private var presence = PopupPresence()

    init() {
        let auth = ProofModel()
        let tracker = TrackerModel()
        let reminders = WaterReminderController(defaults: .standard, center: NativeWaterNotificationCenter())
        tracker.reminders = reminders
        reminders.start { [weak tracker] in tracker?.refreshReminders() }
        auth.attachTracker(tracker)
        auth.start()
        _model = State(initialValue: auth)
        _tracker = State(initialValue: tracker)
        // The app's single Sparkle updater; it checks daily once started.
        _updates = State(initialValue: SoftwareUpdates())
    }

    var body: some Scene {
        MenuBarExtra {
            TrackerPopup(model: tracker, auth: model, appearance: appearance)
                .environment(updates)
                .environment(presence)
        } label: {
            // drop.circle at rest, drop.circle.fill while the popup is open.
            Image(systemName: presence.isOpen ? "drop.circle.fill" : "drop.circle")
                .accessibilityLabel("Daily Challenge")
        }
        .menuBarExtraStyle(.window)
    }
}
