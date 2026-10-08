import ChallengeCore
import SwiftUI

/// The signed-in Account tab: one grouped list a non-technical person can read.
/// Sign-in itself stays in `ProofView`.
struct AccountView: View {
    @Bindable var auth: ProofModel
    let tracker: TrackerModel
    var version: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    @Environment(\.trackerReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State var showsAdvanced = false
    @State private var signOutError: String?

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            group("You", divider: false) { you }
            group("Sync") { sync }
            if let reminders = tracker.reminders {
                group("Reminders") { WaterReminderSettingsView(model: reminders) }
            }
            group("Appearance & startup") {
                AppearanceSettings()
                LaunchAtLoginSettings()
            }
            group("Your data") { BackupSettingsView(model: tracker) }
            group("Account") { account }
            group("About") {
                HStack {
                    Text("Daily Challenge")
                    Spacer()
                    Text(version.map { "Version \($0)" } ?? "Development build").foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            Divider()
            DisclosureGroup(isExpanded: Binding(
                get: { showsAdvanced },
                set: { expanded in withAnimation(reduceMotion ? nil : .default) { showsAdvanced = expanded } }
            )) {
                AdvancedDiagnosticsView(model: auth).padding(.top, 8)
            } label: {
                Text("Advanced").font(.subheadline.weight(.semibold))
            }
            .accessibilityHint("Sync diagnostics for troubleshooting")
        }
        .onChange(of: auth.ownerID) { _, _ in
            showsAdvanced = false
            signOutError = nil
        }
    }

    private func group<Content: View>(_ title: String, divider: Bool = true, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if divider { Divider() }
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private var you: some View {
        HStack(spacing: 10) {
            Text(initial)
                .font(.headline).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.accentColor))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(auth.signedInEmail ?? "Signed in").textSelection(.enabled)
                Text(progress).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var initial: String {
        auth.signedInEmail?.first(where: \.isLetter).map { String($0).uppercased() } ?? "?"
    }

    private var progress: String {
        guard let challenge = tracker.challenge else { return "Challenge not started yet" }
        return Self.progress(day: tracker.dayNumber, startDate: challenge.startDate, bestStreak: tracker.streaks?.best ?? 0)
    }

    /// "Day 12 of 75 · started Sat 27 Sep". Past 75 the day count keeps going, as
    /// tracking does; "75 reached" only appears once a 75-day streak has happened.
    static func progress(day: Int, startDate: Date, bestStreak: Int) -> String {
        let started = "started \(JerseyDates.label(startDate, format: "EEE d MMM"))"
        guard day > 75 else { return "Day \(day) of 75 · \(started)" }
        return "Day \(day)\(bestStreak >= 75 ? " · 75 reached" : "") · \(started)"
    }

    private var sync: some View {
        let state = tracker.syncState
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(state.plainText, systemImage: symbol(for: state))
                    .help(errorDetail(state) ?? "Your entries are saved on this Mac first, then copied to the server.")
                Spacer()
                if tracker.syncActive {
                    Button("Sync now") { Task { await tracker.sync(force: true) } }
                        .disabled(tracker.isSyncing)
                }
            }
            if let warning = state.clockWarningText {
                Label(warning, systemImage: "clock.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func symbol(for state: SyncState) -> String {
        switch state {
        case .synced: "checkmark.icloud"
        case .unavailable: "icloud.slash"
        case .checking: "arrow.triangle.2.circlepath.icloud"
        case .localOnly, .savedLocally, .awaitingCheck: "internaldrive"
        }
    }

    private func errorDetail(_ state: SyncState) -> String? {
        guard case let .unavailable(pending, error) = state else { return nil }
        return "\(pending) change\(pending == 1 ? "" : "s") waiting on this Mac. Details: \(error)"
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Placeholder for the change-password flow; enabled once it exists.
            Button {} label: {
                HStack {
                    Text("Change password")
                    Spacer()
                    Text("Coming soon").font(.caption)
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(true)
            .accessibilityHint("Coming soon")
            .help("Changing your password from the app is coming soon.")
            HStack {
                Text("Sign out on this Mac")
                Spacer()
                Button("Sign out") {
                    Task {
                        await auth.signOut()
                        if auth.ownerID != nil { signOutError = auth.errorMessage }
                    }
                }
                .disabled(auth.isBusy)
            }
            .help("Your other Macs stay signed in. Nothing is deleted.")
            if let signOutError {
                Text("Couldn't sign out. \(signOutError)").font(.caption).foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }
}
