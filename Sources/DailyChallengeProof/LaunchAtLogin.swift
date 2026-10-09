import AppKit
import ServiceManagement
import SwiftUI

@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

@MainActor
struct MainAppLoginItemService: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

@MainActor @Observable
final class LaunchAtLoginController {
    private let service: any LoginItemService
    private(set) var status: SMAppService.Status
    private(set) var errorMessage: String?

    init(service: any LoginItemService) {
        self.service = service
        status = service.status
    }

    // Pending approval remains switchable off; it is not reported as enabled.
    var isRequested: Bool { status == .enabled || status == .requiresApproval }
    var statusMessage: String {
        switch status {
        case .enabled: "Enabled on this Mac."
        case .notRegistered: "Off on this Mac."
        case .requiresApproval: "Requires approval in System Settings > General > Login Items."
        case .notFound: "Login item not found. Run the built app bundle and try again."
        @unknown default: "Login item status is unavailable."
        }
    }

    func refresh() { status = service.status }

    // Only the explicit toggle action calls this. No saved preference or startup repair.
    func setRequested(_ requested: Bool) {
        errorMessage = nil
        do {
            if requested { try service.register() }
            else { try service.unregister() }
        } catch {
            errorMessage = "Could not change launch at login: \(error.localizedDescription)"
        }
        refresh()
    }
}

struct LaunchAtLoginSettings: View {
    @State private var model = LaunchAtLoginController(service: MainAppLoginItemService())

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { model.isRequested }, set: { model.setRequested($0) })) {
                HStack(spacing: 12) {
                    Image(systemName: "desktopcomputer").font(.system(size: 17, weight: .medium)).frame(width: 24)
                        .accessibilityHidden(true)
                    Text("Launch at login").font(Theme.Fonts.rowLabel)
                }
                .foregroundStyle(Theme.textPrimary)
            }
            .toggleStyle(GlassToggleStyle())
            .frame(minHeight: 44)
            .help(model.statusMessage)
            .accessibilityLabel("Launch at login on this Mac")
            .accessibilityHint(model.statusMessage)
            // On and off are the switch itself; only states needing action are spelled out.
            if model.status == .requiresApproval || model.status == .notFound {
                Label(model.statusMessage, systemImage: "exclamationmark.circle")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.amberText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 36)
            }
            if let error = model.errorMessage {
                FieldError(text: error).padding(.leading, 36)
            }
        }
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }
}
