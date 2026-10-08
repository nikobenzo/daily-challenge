import AppKit
import SwiftUI

@main
struct DailyChallengeProofApp: App {
    @State private var model: ProofModel
    @State private var tracker: TrackerModel
    @State private var appearance = AppAppearance()

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
    }

    var body: some Scene {
        MenuBarExtra("Daily Challenge", systemImage: "drop.circle") {
            TrackerPopup(model: tracker, auth: model, appearance: appearance)
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
                Text("Sign in").font(.headline)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
            }
            Text("Sign in to unlock your local tracker.")
                .font(.caption).foregroundStyle(.secondary)

            if model.configurationReady {
                signInContent
            }

            Divider()
            AppearanceSettings()
            LaunchAtLoginSettings()
            Text(model.status).font(.caption)
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private var signInContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Use the same app email and password on both Macs. No email link or code is required.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("App account email", text: $model.email)
                .textFieldStyle(.roundedBorder)
                .disabled(model.isBusy)
            SecureField("App account password", text: $model.password)
                .textFieldStyle(.roundedBorder)
                .disabled(model.isBusy)
                .onSubmit { Task { await model.signIn() } }
            Button("Sign in") { Task { await model.signIn() } }
                .disabled(model.isBusy || model.email.isEmpty || model.password.isEmpty)
            Text("Create or update a confirmed Auth user first. This is not your Supabase dashboard password.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
