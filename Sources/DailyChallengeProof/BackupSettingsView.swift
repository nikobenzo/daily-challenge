import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BackupSettingsView: View {
    let model: TrackerModel
    @State private var pendingData: Data?
    @State private var preview = ""
    @State private var message: String?
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Backups").font(.headline)
            Text("Exports contain personal data: your account ID, challenge settings and full activity/correction history. Store and share them carefully. No credentials or session tokens are included.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Export JSON…", action: export)
                Button("Import JSON…", action: selectImport)
            }
            .disabled(model.challenge == nil)
            if let message { Text(message).font(.caption).textSelection(.enabled) }
        }
        .confirmationDialog("Merge this export?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Import and merge") {
                guard let data = pendingData else { return }
                pendingData = nil
                do {
                    let backup = try model.importData(data)
                    message = "Import saved locally and queued for sync. Recovery backup: \(backup.path)"
                } catch { message = "Import rejected: \(error.localizedDescription)" }
            }
            Button("Cancel", role: .cancel) { pendingData = nil }
        } message: {
            Text(preview + " Existing history is preserved. A local recovery backup will be saved before applying.")
        }
        .onChange(of: model.ownerID) { _, _ in
            pendingData = nil
            confirming = false
            message = nil
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "daily-challenge-export.json"
        panel.message = "This file contains personal challenge data. Keep it private. It does not contain login credentials."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportData().write(to: url, options: .atomic)
            message = "Export saved. Keep this personal-data file private."
        } catch { message = error.localizedDescription }
    }

    private func selectImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let plan = try model.previewImport(data)
            preview = "\(plan.newCount) new activities/corrections; \(plan.duplicateCount) duplicates."
            pendingData = data
            confirming = true
            message = nil
        } catch {
            pendingData = nil
            message = "Import rejected: \(error.localizedDescription)"
        }
    }
}
