import AppKit
import SwiftUI

@main
struct DailyChallengeProofApp: App {
    @State private var model: ProofModel
    @State private var tracker: TrackerModel
    @State private var appearance = AppAppearance()
    @State private var updates: SoftwareUpdates

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
        MenuBarExtra("Daily Challenge", systemImage: "drop.circle") {
            TrackerPopup(model: tracker, auth: model, appearance: appearance)
                .environment(updates)
        }
        .menuBarExtraStyle(.window)
    }
}

struct ProofView: View {
    @Bindable var model: ProofModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath.icloud")
                Text(model.authStep.title).font(.headline)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
            }
            Text(model.authStep.subtitle)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.configurationReady {
                AuthView(model: model)
            }

            Divider()
            AppearanceSettings()
            LaunchAtLoginSettings()
            // AuthView shows its own guidance and errors beside the form.
            if !model.configurationReady {
                Text(model.status).font(.caption)
                if let error = model.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
