import ChallengeCore
import ChallengeSyncKit
import SwiftUI

/// The signed-in Account tab: profile and sync, device settings, your data and account,
/// then About, separated by hairlines. Sign-in itself stays in `ProofView`.
struct AccountView: View {
    @Bindable var auth: ProofModel
    let tracker: TrackerModel
    var version: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    @Environment(\.trackerReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(SoftwareUpdates.self) private var updates: SoftwareUpdates?
    @State var showsAdvanced = false
    @State private var signOutError: String?
    @State var changingPassword = false
    @State private var passwordError: String?
    @State private var passwordSaved = false

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        VStack(spacing: 0) {
            you
                .padding(.horizontal, Theme.Size.sectionHorizontal)
                .padding(.vertical, Theme.Size.sectionVertical)
            HairlineDivider()
            VStack(spacing: 4) {
                if let reminders = tracker.reminders { WaterReminderSettingsView(model: reminders) }
                LaunchAtLoginSettings()
                AppearanceSettings()
            }
            .padding(.horizontal, Theme.Size.sectionHorizontal)
            .padding(.vertical, 10)
            HairlineDivider()
            VStack(spacing: 4) {
                ExtrasSettingRow(model: tracker)
                BackupSettingsView(model: tracker)
                account
            }
            .padding(.horizontal, Theme.Size.sectionHorizontal)
            .padding(.vertical, 10)
            HairlineDivider()
            about
                .padding(.horizontal, Theme.Size.sectionHorizontal)
                .padding(.vertical, Theme.Space.s)
            if showsAdvanced {
                HairlineDivider()
                AdvancedDiagnosticsView(model: auth)
                    .padding(.horizontal, Theme.Size.sectionHorizontal)
                    .padding(.vertical, Theme.Space.s)
            }
        }
        .onChange(of: auth.ownerID) { _, _ in
            showsAdvanced = false
            signOutError = nil
            closePasswordForm()
            passwordSaved = false
        }
    }

    private var you: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(initial)
                    .font(.system(size: 18, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.appMarkGradient))
                    .shadow(color: Theme.primaryShadow, radius: 6, y: 3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(auth.signedInEmail ?? "Signed in").font(Theme.Fonts.pill).foregroundStyle(Theme.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                    Label(progress, systemImage: "calendar")
                        .font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 4)
                sync
            }
            if let warning = tracker.syncState.clockWarningText {
                Label(warning, systemImage: "clock.badge.exclamationmark")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.amberText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let skipped = tracker.skippedNotice {
                Label(skipped, systemImage: "exclamationmark.icloud")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var initial: String {
        auth.signedInEmail?.first(where: \.isLetter).map { String($0).uppercased() } ?? "?"
    }

    private var progress: String {
        guard let challenge = tracker.challenge else { return "Challenge not started yet" }
        return Self.progress(day: tracker.dayNumber, startDate: challenge.startDate, bestStreak: tracker.streaks?.best ?? 0,
                             dates: tracker.dates)
    }

    /// "Day 12 of 75 · started Sat 27 Sep". Past 75 the day count keeps going, as
    /// tracking does; "75 reached" only appears once a 75-day streak has happened.
    static func progress(day: Int, startDate: Date, bestStreak: Int, dates: ChallengeDates) -> String {
        let started = "started \(dates.label(startDate, format: "EEE d MMM"))"
        guard day > 75 else { return "Day \(day) of 75 · \(started)" }
        return "Day \(day)\(bestStreak >= 75 ? " · 75 reached" : "") · \(started)"
    }

    /// Sync pill (state glyph + time or short word) and the Sync now icon button.
    private var sync: some View {
        let state = tracker.syncState
        let synced = if case .synced(_, false) = state { true } else { false }
        let failing = if case .unavailable = state { true } else { false }
        return HStack(spacing: 8) {
            Badge(symbol: SyncFooterItem.symbol(state), text: SyncFooterItem.shortText(state),
                  fill: synced ? Theme.doneTint : failing ? Theme.amberTint : Theme.controlFill,
                  foreground: synced ? Theme.doneText : failing ? Theme.amberText : Theme.textSecondary, height: 32)
                .help(errorDetail(state) ?? "\(state.plainText). Your entries are saved on this Mac first, then copied to the server.")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(state.plainText)
            if tracker.syncActive {
                Button { Task { await tracker.sync(force: true) } } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                    .buttonStyle(RoundIconStyle(size: 36))
                    .disabled(tracker.isSyncing)
                    .help("Sync now").accessibilityLabel("Sync now")
            }
        }
    }

    private func errorDetail(_ state: SyncState) -> String? {
        guard case let .unavailable(pending, error) = state else { return nil }
        return "\(state.plainText). \(pending) change\(pending == 1 ? "" : "s") waiting on this Mac. Details: \(error)"
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                if changingPassword { closePasswordForm() } else { openPasswordForm() }
            } label: {
                SettingRow(symbol: "key", title: "Change password") {
                    if passwordSaved && !changingPassword {
                        Badge(symbol: "checkmark", text: "Changed", fill: Theme.doneTint, foreground: Theme.doneText)
                    }
                    Image(systemName: changingPassword ? "chevron.down" : "chevron.right")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(auth.isBusy)
            .accessibilityHint(changingPassword ? "Hides the new password form" : "Shows a form to choose a new password")
            .help("Choose a new password for this account. Your other Macs stay signed in.")
            if changingPassword { passwordForm }
            Button {
                Task {
                    await auth.signOut()
                    if auth.ownerID != nil { signOutError = auth.errorMessage }
                }
            } label: {
                SettingRow(symbol: "rectangle.portrait.and.arrow.right", title: "Sign out on this Mac", tint: Theme.danger) {
                    EmptyView()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(auth.isBusy)
            .help("Your other Macs stay signed in. Nothing is deleted.")
            if let signOutError {
                FieldError(text: "Couldn't sign out. \(signOutError)")
            }
        }
    }

    private enum PasswordField: Hashable { case new, repeated }
    @FocusState private var passwordFocus: PasswordField?

    private var passwordForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassField(symbol: "lock", placeholder: "New password", text: $auth.newPassword, secure: true,
                       contentType: .newPassword, focus: $passwordFocus, equals: .new) { passwordFocus = .repeated }
            GlassField(symbol: "lock.shield", placeholder: "Repeat password", text: $auth.passwordConfirmation, secure: true,
                       invalid: !auth.passwordConfirmation.isEmpty && auth.newPassword != auth.passwordConfirmation,
                       contentType: .newPassword, focus: $passwordFocus, equals: .repeated, onSubmit: savePassword)
            if !auth.passwordConfirmation.isEmpty, auth.newPassword != auth.passwordConfirmation {
                FieldError(text: "The passwords don't match yet.")
            }
            RuleChips(password: auth.newPassword, confirmation: auth.passwordConfirmation)
            if let passwordError {
                FieldError(text: passwordError)
            }
            HStack {
                Button("Cancel", action: closePasswordForm).buttonStyle(TintedPillStyle(height: 36))
                Spacer()
                if auth.isBusy { ProgressView().controlSize(.small) }
                Button("Save password", action: savePassword)
                    .buttonStyle(PrimaryPillStyle(height: 36, expands: false))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSavePassword)
            }
        }
        .disabled(auth.isBusy)
        .padding(.vertical, 6)
        .onAppear { passwordFocus = .new }
    }

    /// Version, update state and the Advanced (wrench) diagnostics toggle.
    private var about: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle").font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.textSecondary)
                .frame(width: 24).accessibilityHidden(true)
            Text(version ?? "Development build").font(Theme.Fonts.pill).foregroundStyle(Theme.textSecondary)
                .help("Daily Challenge \(version.map { "version \($0)" } ?? "development build")")
                .accessibilityLabel("Daily Challenge \(version.map { "Version \($0)" } ?? "Development build")")
            SoftwareUpdateSettings(updates: updates)
            Button {
                withAnimation(reduceMotion ? nil : .default) { showsAdvanced.toggle() }
            } label: { Image(systemName: "wrench.and.screwdriver") }
                .buttonStyle(RoundIconStyle(size: 36, fill: showsAdvanced ? Theme.amberTint : Theme.controlFill,
                                            foreground: showsAdvanced ? Theme.amberText : Theme.textPrimary))
                .help("Advanced: sync diagnostics for troubleshooting")
                .accessibilityLabel("Advanced")
                .accessibilityValue(showsAdvanced ? "Expanded" : "Collapsed")
                .accessibilityHint("Sync diagnostics for troubleshooting")
        }
    }

    private var canSavePassword: Bool {
        ProofModel.passwordProblem(auth.newPassword) == nil && auth.newPassword == auth.passwordConfirmation
    }

    private func openPasswordForm() {
        auth.newPassword = ""
        auth.passwordConfirmation = ""
        passwordError = nil
        passwordSaved = false
        changingPassword = true
    }

    /// Never leaves a typed password behind in the model.
    private func closePasswordForm() {
        auth.newPassword = ""
        auth.passwordConfirmation = ""
        passwordError = nil
        changingPassword = false
    }

    private func savePassword() {
        guard canSavePassword else { return }
        Task {
            if await auth.changePassword(new: auth.newPassword) {
                closePasswordForm()
                passwordSaved = true
            } else {
                passwordError = auth.errorMessage
            }
        }
    }
}
