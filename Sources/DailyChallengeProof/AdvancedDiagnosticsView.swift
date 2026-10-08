import SwiftUI

/// The test-message diagnostics, moved unchanged from the old Account tab. They use
/// their own durable queue and never carry challenge activity.
struct AdvancedDiagnosticsView: View {
    @Bindable var model: ProofModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sync diagnostics (for troubleshooting)").font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Diagnostics sync test messages only, not your challenge activity.")
                .font(.caption).foregroundStyle(.secondary)
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
                if model.isBusy { ProgressView().controlSize(.small) }
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
            Text(model.status).font(.caption)
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }
}
