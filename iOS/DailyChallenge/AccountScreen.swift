import ChallengeCore
import ChallengeSyncKit
import SwiftUI

/// Account: who is signed in and the challenge's progress, sync, the device's water
/// reminders and appearance, and sign out. Reminders and appearance stay on this iPhone.
struct AccountScreen: View {
    @Bindable var app: PhoneApp
    @State private var managingExtras = false
    @State private var confirmingSignOut = false
    @State private var deletingAccount = false
    @State private var signOutError: String?

    private var auth: AuthModel { app.auth }
    private var tracker: TrackerModel { app.tracker }

    var body: some View {
        PhoneScreen {
            PhoneHeader(title: "Account")
            GlassCard {
                you
                    .padding(.horizontal, Theme.Size.sectionHorizontal)
                    .padding(.vertical, Theme.Size.sectionVertical)
                HairlineDivider()
                sync
                    .padding(.horizontal, Theme.Size.sectionHorizontal)
                    .padding(.vertical, Theme.Space.s)
            }
            GlassCard {
                VStack(spacing: 4) {
                    if let reminders = app.reminders { PhoneReminderSettings(model: reminders) }
                    HairlineDivider().padding(.vertical, 6)
                    appearance
                    HairlineDivider().padding(.vertical, 6)
                    Button { managingExtras = true } label: {
                        SettingRow(symbol: "checklist", title: "Extras") {
                            Text("\(tracker.activeExtras.count)/10").font(Theme.Fonts.field)
                            Image(systemName: "chevron.right")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(tracker.challenge == nil)
                    .accessibilityLabel("Manage extras, \(tracker.activeExtras.count) of 10")
                    .accessibilityIdentifier("account-extras")
                    .id("fixture-account-extras")
                }
                .padding(.horizontal, Theme.Size.sectionHorizontal)
                .padding(.vertical, Theme.Space.s)
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 4) {
                    signOut
                    if let signOutError { FieldError(text: "Couldn't sign out. \(signOutError)") }
                    HairlineDivider().padding(.vertical, 6)
                    deleteAccount
                    HairlineDivider().padding(.vertical, 6)
                    SettingRow(symbol: "info.circle", title: "Version") {
                        Text(version).font(Theme.Fonts.field).monospacedDigit().foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                .padding(.horizontal, Theme.Size.sectionHorizontal)
                .padding(.vertical, Theme.Space.s)
            }
        }
        .sheet(isPresented: $managingExtras) { PhoneManageExtrasView(tracker: tracker) }
        .sheet(isPresented: $deletingAccount) { DeleteAccountView(app: app) }
        #if DEBUG
        .onAppear { deletingAccount = PhoneFixtures.showingDeletion }
        #endif
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    // MARK: You

    private var you: some View {
        HStack(spacing: 14) {
            Circle().fill(Theme.appMarkGradient)
                .frame(width: 52, height: 52)
                .overlay { Text(initial).font(Theme.Fonts.streak).foregroundStyle(.white) }
                .shadow(color: Theme.primaryShadow, radius: 8, y: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(auth.signedInEmail ?? "Signed in").font(Theme.Fonts.pill).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).truncationMode(.middle)
                    .accessibilityIdentifier("account-email")
                Label(progress, systemImage: "calendar").font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var initial: String {
        auth.signedInEmail?.first(where: \.isLetter).map { String($0).uppercased() } ?? "?"
    }

    /// "Day 12 of 75 · started Sat 27 Sep", worded as on the Mac.
    private var progress: String {
        guard let challenge = tracker.challenge else { return "Challenge not started yet" }
        let started = "started \(tracker.dates.label(challenge.startDate, format: "EEE d MMM"))"
        let day = tracker.dayNumber
        guard day > 75 else { return "Day \(day) of 75 · \(started)" }
        return "Day \(day)\((tracker.streaks?.best ?? 0) >= 75 ? " · 75 reached" : "") · \(started)"
    }

    // MARK: Sync

    private var sync: some View {
        let state = tracker.syncState
        let synced = if case .synced(_, false) = state { true } else { false }
        let failing = if case .unavailable = state { true } else { false }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: SyncWords.symbol(state)).font(.system(size: 17, weight: .medium))
                    .foregroundStyle(synced ? Theme.done : failing ? Theme.amber : Theme.textPrimary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(state.plainText(on: .iPhone)).font(Theme.Fonts.field).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("account-sync")
                Spacer(minLength: 8)
                if tracker.syncActive {
                    Button { Task { await tracker.sync(force: true) } } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(RoundIconStyle(size: 40))
                    .disabled(tracker.isSyncing)
                    .accessibilityLabel("Sync now")
                }
            }
            if case let .unavailable(pending, error) = state {
                Text("\(pending) change\(pending == 1 ? "" : "s") waiting on this iPhone. Details: \(error)")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.amberText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let warning = state.clockWarningText(on: .iPhone) {
                Label(warning, systemImage: "clock.badge.exclamationmark").font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.amberText).fixedSize(horizontal: false, vertical: true)
            }
            if let skipped = tracker.skippedNotice {
                Label(skipped, systemImage: "exclamationmark.triangle").font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Appearance, sign out and delete account

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingRow(symbol: "circle.lefthalf.filled", title: "Appearance") { EmptyView() }
            Picker("Appearance", selection: $app.appearance) {
                Text("System").tag(AppearancePreference.system)
                Text("Light").tag(AppearancePreference.light)
                Text("Dark").tag(AppearancePreference.dark)
            }
            .pickerStyle(.segmented)
            .accessibilityHint("System follows iOS. Saved only on this iPhone.")
        }
    }

    private var signOut: some View {
        Button { confirmingSignOut = true } label: {
            SettingRow(symbol: "rectangle.portrait.and.arrow.right", title: "Sign out on this iPhone", tint: Theme.danger) {
                if auth.isBusy { ProgressView() }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(auth.isBusy)
        .accessibilityHint("Your other devices stay signed in. Nothing is deleted.")
        .accessibilityIdentifier("account-sign-out")
        .confirmationDialog("Sign out on this iPhone?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task {
                    await auth.signOut()
                    signOutError = auth.ownerID != nil ? auth.errorMessage : nil
                }
            }
        } message: {
            Text("Your entries stay on the server and on your other devices. Entries not yet synced stay on this iPhone until you sign in again.")
        }
    }

    private var deleteAccount: some View {
        Button { deletingAccount = true } label: {
            SettingRow(symbol: "trash", title: "Delete account", tint: Theme.danger) {
                Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(auth.isBusy || auth.accountDeletion == nil)
        .accessibilityHint("Permanently deletes your account and all its challenge history. Asks you to confirm twice.")
        .accessibilityIdentifier("account-delete")
        .id("fixture-account-delete")
    }
}

/// Delete account, step one of two: what is deleted and where, before the final alert.
/// Nothing is deleted anywhere unless the server confirms; a failure keeps the account,
/// this iPhone's session and every local entry, and says so.
struct DeleteAccountView: View {
    let app: PhoneApp
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false
    @State private var failure: String?
    @ScaledMetric(relativeTo: .body) private var iconWidth = 24.0

    private var auth: AuthModel { app.auth }
    private var email: String { auth.signedInEmail ?? "This account" }

    var body: some View {
        NavigationStack {
            PhoneScreen {
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Circle().fill(Theme.dangerTint).frame(width: 60, height: 60)
                            .overlay { Image(systemName: "trash").font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.danger) }
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                        Text("Delete your account?").font(Theme.Fonts.screenTitle).tracking(Theme.Tracking.screenTitle)
                            .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text(email).font(Theme.Fonts.field).foregroundStyle(Theme.textSecondary)
                            .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity)
                            .accessibilityIdentifier("delete-account-email")
                        VStack(alignment: .leading, spacing: 12) {
                            point("person.crop.circle.badge.xmark", "Your account is deleted. You can't sign in to it again.")
                            point("icloud.slash", "All your synced challenge history (every day, pour, habit, diet mark and extra) "
                                  + "is permanently deleted from the server, for every device.")
                            point("iphone", "This iPhone's copy is removed now, \(unsynced).")
                            point("laptopcomputer", "Your other devices can no longer sync it and are signed out.")
                        }
                        Label("This can't be undone.", systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Fonts.rowLabel).foregroundStyle(Theme.danger)
                        if let failure {
                            FieldError(text: failure).accessibilityIdentifier("delete-account-error")
                        }
                        Button(role: .destructive) { failure = nil; confirming = true } label: {
                            HStack(spacing: 8) {
                                if auth.isBusy { ProgressView() }
                                Text(auth.isBusy ? "Deleting account…" : "Delete account…")
                            }
                        }
                        .buttonStyle(TintedPillStyle(fill: Theme.dangerTint, foreground: Theme.danger, expands: true))
                        .disabled(auth.isBusy)
                        .accessibilityIdentifier("delete-account-continue")
                        Button("Keep my account") { dismiss() }
                            .buttonStyle(TintedPillStyle(expands: true))
                            .disabled(auth.isBusy)
                    }
                    .padding(Theme.Size.sectionHorizontal)
                }
            }
            .foregroundStyle(Theme.textPrimary)
            .navigationTitle("Delete account").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(auth.isBusy) }
            }
            .alert("Delete your account permanently?", isPresented: $confirming) {
                Button("Delete account", role: .destructive) {
                    Task {
                        if await app.deleteAccount() { dismiss() } else { failure = auth.errorMessage }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(email) and all its challenge history will be deleted from the server and from this iPhone. "
                     + "This can't be undone.")
            }
        }
        .interactiveDismissDisabled(auth.isBusy)
        #if DEBUG
        // The alert can present only once the sheet has finished presenting.
        .task {
            guard PhoneFixtures.showingDeletionConfirmation else { return }
            try? await Task.sleep(for: .milliseconds(800))
            confirming = true
        }
        #endif
    }

    private var unsynced: String {
        let pending = app.tracker.store?.pendingCount ?? 0
        return switch pending {
        case 0: "including anything not yet synced"
        case 1: "including 1 change not yet synced"
        default: "including \(pending) changes not yet synced"
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(Theme.Fonts.field).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.textSecondary).frame(width: iconWidth)
        }
    }
}

/// Water reminders on this iPhone: on/off, interval and the daily window, in the
/// challenge's zone. Permission is asked only when reminders are turned on.
struct PhoneReminderSettings: View {
    @Bindable var model: WaterReminderController

    var body: some View {
        let interval = model.settings.intervalMinutes
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: setting(\.enabled)) {
                HStack(spacing: 12) {
                    Image(systemName: "bell").font(.system(size: 17, weight: .medium)).frame(width: 24)
                        .accessibilityHidden(true)
                    Text("Water reminders").font(Theme.Fonts.rowLabel)
                }
                .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.toggleOn)
            .frame(minHeight: 44)
            .accessibilityHint(Self.details(timeZone: model.timeZone))
            .accessibilityIdentifier("reminders-toggle")
            if model.settings.enabled {
                Stepper(value: setting(\.intervalMinutes), in: 15...240, step: 15) {
                    Text("Every \(interval) min").font(Theme.Fonts.field).foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                }
                .accessibilityValue("Every \(interval) minutes")
                DatePicker(selection: time(\.startMinute), displayedComponents: .hourAndMinute) {
                    Text("From").font(Theme.Fonts.field).foregroundStyle(Theme.textPrimary)
                }
                DatePicker(selection: time(\.endMinute), displayedComponents: .hourAndMinute) {
                    Text("Until").font(Theme.Fonts.field).foregroundStyle(Theme.textPrimary)
                }
            }
            Text(model.status).font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reminders-status")
            Text(Self.details(timeZone: model.timeZone)).font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = model.errorMessage { FieldError(text: error) }
        }
        .environment(\.timeZone, model.timeZone)
        .environment(\.calendar, Challenge.calendar(for: model.timeZone))
    }

    static func details(timeZone: TimeZone) -> String {
        "Times are \(ChallengeDates.city(timeZone)) time, your challenge's time zone. Reminders stop for the day at "
            + "4,000 ml; a goal met on another device stops them here once this iPhone syncs. This setting stays on this iPhone."
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<WaterReminderSettings, Value>) -> Binding<Value> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { value in
            var settings = model.settings
            settings[keyPath: keyPath] = value
            model.update(settings)
        })
    }

    private func time(_ keyPath: WritableKeyPath<WaterReminderSettings, Int>) -> Binding<Date> {
        // A fixed day without a transition in the zone represents a wall-clock preference.
        let calendar = Challenge.calendar(for: model.timeZone)
        let day = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        return Binding(get: {
            calendar.date(byAdding: .minute, value: model.settings[keyPath: keyPath], to: day)!
        }, set: { date in
            let components = calendar.dateComponents([.hour, .minute], from: date)
            var settings = model.settings
            settings[keyPath: keyPath] = components.hour! * 60 + components.minute!
            model.update(settings)
        })
    }
}
