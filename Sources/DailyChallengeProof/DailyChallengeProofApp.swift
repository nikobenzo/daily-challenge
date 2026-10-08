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
    var reminders: WaterReminderController? = nil
    var tracker: TrackerModel? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath.icloud")
                Text(model.ownerID == nil ? "Sign in" : "Account · Sync diagnostics").font(.headline)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
            }
            Text(model.ownerID == nil ? "Sign in to unlock your local tracker." : "Diagnostics sync test messages only, not your challenge activity.")
                .font(.caption).foregroundStyle(.secondary)

            if model.ownerID != nil {
                signedInContent
            } else if model.configurationReady {
                signInContent
            }

            Divider()
            AppearanceSettings()
            LaunchAtLoginSettings()
            if let tracker { BackupSettingsView(model: tracker) }
            if let reminders { WaterReminderSettingsView(model: reminders) }
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

    private var signedInContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.signedInEmail ?? "Signed in").font(.caption).textSelection(.enabled)
            HStack {
                Label("\(model.pendingCount) pending", systemImage: "tray.and.arrow.up")
                Spacer()
                Text(model.lastSyncLabel).foregroundStyle(.secondary)
            }.font(.caption)

            TextField("Optional test message", text: $model.message)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.addEntry() }
            HStack {
                Button("Add test entry") { model.addEntry() }
                    .disabled(model.isBusy || model.journal == nil)
                Button("Sync now") { Task { await model.sync() } }
                    .disabled(model.isBusy || model.pauseSync || model.journal == nil)
                Spacer()
            }
            Toggle("Pause sync (test offline queue)", isOn: $model.pauseSync)
                .disabled(model.isBusy)
                .onChange(of: model.pauseSync) { _, paused in
                    if !paused { Task { await model.sync() } }
                }
                .font(.caption)

            if model.entries.isEmpty {
                Text("No test entries yet. Add one on either Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.entries) { entry in
                            HStack(alignment: .top) {
                                Image(systemName: model.isPending(entry.id) ? "clock" : "checkmark.circle")
                                    .accessibilityLabel(model.isPending(entry.id) ? "Pending upload" : "Confirmed on server")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.message).textSelection(.enabled)
                                    Text(String(entry.id.uuidString.prefix(8)))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }.padding(.vertical, 4)
                }.frame(height: 180)
            }
            Button("Sign out on this Mac") { Task { await model.signOut() } }
                .disabled(model.isBusy)
                .font(.caption)
        }
    }
}
