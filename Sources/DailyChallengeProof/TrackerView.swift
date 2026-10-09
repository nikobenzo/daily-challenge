import AppKit
import ChallengeCore
import SwiftUI

enum TrackerSection: String, CaseIterable { case today = "Today", history = "History", account = "Account" }

struct TrackerView: View {
    @Bindable var model: TrackerModel
    @Bindable var auth: ProofModel
    @State var section = TrackerSection.today
    @State private var setupDate = Date()
    /// Defaults to this Mac's zone; fixtures inject one for deterministic renders.
    @State var setupTimeZone = TimeZone.current
    @State private var isVisible = false
    @State private var choosingStart = false
    @State private var showingRules = false
    @Environment(\.trackerReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    /// Which body the sheet shows; a change cross-fades.
    private enum Content: Hashable { case signedOut, unavailable, checking, setup, today, history, account }

    private var content: Content {
        if auth.ownerID == nil { return .signedOut }
        if section == .account { return .account }
        if model.store == nil { return .unavailable }
        if model.challenge == nil { return model.canStartChallenge ? .setup : .checking }
        return section == .today ? .today : .history
    }

    var body: some View {
        AnimatedPopupStack {
            VStack(spacing: 0) {
                header
                HairlineDivider()
                ZStack(alignment: .top) {
                    sectionBody(content)
                        .id(content)
                        .transition(reduceMotion ? .identity : .opacity)
                }
                if let error = model.errorMessage, auth.ownerID != nil, section != .account {
                    HairlineDivider()
                    errorRow(error)
                }
            }
        } footer: {
            footer
        }
        .environment(\.trackerPopupVisible, isVisible)
        .background { PopupVisibilityReader { isVisible = $0 } }
        .environment(\.calendar, model.dates.calendar)
        .environment(\.timeZone, model.dates.timeZone)
        .onAppear {
            auth.start()
            model.activate(ownerID: auth.ownerID)
            model.refresh()
            model.requestSync()
        }
        .onDisappear { isVisible = false }
        // The popup panel is kept between openings: catch up whenever it is shown again.
        .onChange(of: isVisible) { _, visible in
            guard visible else { return }
            model.refresh()
            model.requestSync()
        }
        .onChange(of: auth.ownerID) { _, owner in
            model.activate(ownerID: owner)
            section = .today
        }
        .onChange(of: section) { _, selection in
            if selection == .today { model.showToday() }
            if selection == .history { model.selectHistoryDay(model.today) }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            model.refresh()
            model.requestSync()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.requestSync()
        }
        .task {
            while !Task.isCancelled {
                let current = Date()
                let midnight = model.dates.calendar.dateInterval(of: .day, for: current)!.end
                let seconds = max(0.1, min(30, midnight.timeIntervalSince(current)))
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                if isVisible { model.refresh() }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        // Two groups pushed apart, as on the boards: with the Day badge the row is full.
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                AppMark()
                Text("Daily Challenge").font(Theme.Fonts.appName).tracking(Theme.Tracking.appName)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).fixedSize()
                if auth.ownerID != nil, model.challenge != nil, model.dayNumber > 0 { dayBadge }
            }
            Spacer(minLength: 0)
            if auth.ownerID != nil {
                IconSegmented(selection: Binding(get: { section }, set: select), options: [
                    .init(value: .today, symbol: "sun.max", label: "Today"),
                    .init(value: .history, symbol: "calendar", label: "History"),
                    .init(value: .account, symbol: "person", label: "Account")
                ])
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Section")
            }
        }
        .padding(.horizontal, Theme.Size.sectionHorizontal)
        .frame(height: Theme.Size.headerHeight)
    }

    private func select(_ value: TrackerSection) {
        withAnimation(reduceMotion ? nil : Theme.Motion.crossFade) { section = value }
    }

    private var dayBadge: some View {
        let today = model.challenge?.summary(on: model.today, asOf: model.now)
        let complete = today?.isComplete == true
        let done = today.map { $0.completedHabits.count + ($0.waterComplete ? 1 : 0) + ($0.diet == .clean ? 1 : 0) } ?? 0
        return Badge(symbol: complete ? "checkmark" : nil, text: "Day \(model.dayNumber)",
                     fill: complete ? Theme.doneTint : Theme.dayBadgeFill,
                     foreground: complete ? Theme.doneText : Theme.dayBadgeText, height: 28)
            .help("\(model.dates.label(model.now)) · \(done) of 5 done")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Day \(model.dayNumber)\(complete ? ", complete" : ", \(done) of 5 done")")
    }

    // MARK: Sections

    @ViewBuilder
    private func sectionBody(_ content: Content) -> some View {
        switch content {
        case .signedOut:
            ProofView(model: auth)
        case .account:
            ScrollView {
                AccountView(auth: auth, tracker: model)
                    .frame(minHeight: Theme.Size.wideSectionHeight, alignment: .top)
            }
            .scrollIndicators(.automatic)
            .frame(height: Theme.Size.wideSectionHeight)
        case .unavailable:
            notice(symbol: "exclamationmark.triangle", title: "History unavailable",
                   detail: "Your saved data has not been reset.") {
                Button("Try again") { model.reload() }.buttonStyle(TintedPillStyle())
            }
        case .checking:
            notice(symbol: "icloud.and.arrow.down", title: "Checking for your existing challenge",
                   detail: "Setup needs a successful server check. Your other Mac may already have a challenge.") {
                Button { Task { await model.sync(force: true) } } label: {
                    Label("Check again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(TintedPillStyle())
                .disabled(model.isSyncing)
            }
        case .setup:
            setup
        case .today:
            TodayTrackerView(model: model)
        case .history:
            HistoryTrackerView(model: model)
        }
    }

    private func notice<Actions: View>(symbol: String, title: String, detail: String,
                                       @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 12) {
            HeroIcon(symbol: symbol)
            Text(title).font(Theme.Fonts.rowLabel).foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(detail).font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            actions()
        }
        .padding(.horizontal, Theme.Size.sectionHorizontal)
        .padding(.vertical, Theme.Space.xl)
        .frame(maxWidth: .infinity)
    }

    private func errorRow(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.danger)
                .accessibilityHidden(true)
            Text(error).font(Theme.Fonts.caption).foregroundStyle(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            Button { model.dismissError() } label: { Image(systemName: "xmark") }
                .buttonStyle(RoundIconStyle(size: 24))
                .accessibilityLabel("Dismiss error").help("Dismiss")
        }
        .padding(.horizontal, Theme.Size.sectionHorizontal)
        .padding(.vertical, Theme.Space.s)
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        FooterBar {
            if auth.ownerID == nil {
                Label("Signed out", systemImage: "icloud.slash")
                    .font(Theme.Fonts.pill).foregroundStyle(Theme.textTertiary)
            } else if content == .setup {
                HStack(spacing: 10) {
                    Button { showingRules = true } label: { Image(systemName: "info.circle") }
                        .buttonStyle(RoundIconStyle(size: 34))
                        .help(setupRules)
                        .accessibilityLabel("Challenge rules")
                        .popover(isPresented: $showingRules, arrowEdge: .top) {
                            Text(setupRules).font(Theme.Fonts.field).foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(16).frame(width: 300).trackerSurface()
                        }
                    SyncFooterItem(model: model, compact: true)
                    Text(auth.signedInEmail ?? "").font(Theme.Fonts.field).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            } else {
                SyncFooterItem(model: model)
            }
        }
    }

    // MARK: Setup

    private var setupRules: String {
        "Days follow \(setupTimeZone.identifier), midnight to midnight, including daylight saving. "
            + "The start date and time zone can't be changed after you start.\n\n"
            + "Closed unfinished days break the streak. Earlier days need explicit entries. Tracking continues beyond 75.\n\n"
            + "Use the same app account on both Macs. Activity saves locally first, then syncs. Appearance stays on this Mac."
    }

    private var setup: some View {
        let setupDates = ChallengeDates(timeZone: setupTimeZone)
        return VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Your next 75 days").font(Theme.Fonts.screenTitle).tracking(Theme.Tracking.screenTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("Every day, midnight to midnight, all five.")
                    .font(Theme.Fonts.link).foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, Theme.Space.xl)
            HStack(spacing: 0) {
                requirement("drop.fill", "4,000 ml", detail: "4 litres of water", tint: Theme.water)
                requirement("dumbbell", "45 min", detail: "45-minute workout · home or gym")
                requirement("figure.walk", "45 min", detail: "45-minute walk")
                requirement("leaf", "Clean diet", detail: "Clean diet · your own rules")
                requirement("book", "10 pages", detail: "10 Bible pages")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, Theme.Space.l)
            HairlineDivider()
            VStack(spacing: 0) {
                SettingRow(symbol: "calendar", title: "Start") {
                    Button { choosingStart = true } label: {
                        chip(setupDates.label(setupDate))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start date")
                    .accessibilityValue(setupDates.label(setupDate, format: "d MMMM yyyy"))
                    .help("The first day of your challenge. It can't be changed after you start.")
                    .popover(isPresented: $choosingStart, arrowEdge: .bottom) {
                        DatePicker("Start date", selection: $setupDate, in: ...model.now, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .padding(12)
                            .environment(\.timeZone, setupTimeZone)
                            .environment(\.calendar, setupDates.calendar)
                            .trackerSurface()
                    }
                }
                .padding(.vertical, 6)
                Theme.hairline.frame(height: 1).padding(.leading, 36)
                TimeZonePicker(selection: $setupTimeZone, now: model.now)
                    .padding(.vertical, 6)
            }
            .padding(.horizontal, Theme.Size.sectionHorizontal)
            HairlineDivider()
            Button { model.startChallenge(on: setupDate, timeZone: setupTimeZone) } label: {
                Label("Start challenge", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryPillStyle(height: Theme.Size.largePill, font: Theme.Fonts.appName))
            .padding(.horizontal, Theme.Size.sectionHorizontal)
            .padding(.vertical, Theme.Space.l)
        }
    }

    private func requirement(_ symbol: String, _ label: String, detail: String, tint: Color = Theme.textPrimary) -> some View {
        VStack(spacing: 8) {
            Circle().stroke(Theme.ringTrack, lineWidth: Theme.Size.ringStroke)
                .padding(Theme.Size.ringStroke / 2)
                .frame(width: Theme.Size.ring, height: Theme.Size.ring)
                .overlay { Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(tint) }
            Eyebrow(text: label, color: Theme.textSecondary, font: Theme.Fonts.ringLabel, tracking: Theme.Tracking.ringLabel)
                .lineLimit(1).fixedSize()
        }
        .frame(maxWidth: .infinity)
        .help(detail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail)
    }
}

/// "Thu 8 Oct ›" value chip used by setup rows.
func chip(_ text: String) -> some View {
    HStack(spacing: 6) {
        Text(text).font(Theme.Fonts.pill).foregroundStyle(Theme.textPrimary).lineLimit(1)
        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textSecondary)
    }
    .padding(.horizontal, 14)
    .frame(height: 34)
    .background(Capsule(style: .circular).fill(Theme.controlFill))
    .contentShape(Capsule(style: .circular))
}

/// The detached 420 × 56 capsule under the sheet: state on the left, Quit on the right.
struct FooterBar<Leading: View>: View {
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        HStack(spacing: 10) {
            leading()
            Spacer(minLength: 8)
            Button { NSApplication.shared.terminate(nil) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "power").font(.system(size: 15, weight: .bold))
                    Text("Quit").font(Theme.Fonts.rowLabel)
                }
                .foregroundStyle(Theme.textPrimary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Quit Daily Challenge")
        }
        .padding(.horizontal, 22)
        .frame(width: Theme.Size.panelWidth, height: Theme.Size.footerHeight)
        .glassSheet(cornerRadius: Theme.Size.footerHeight / 2, style: .circular)
    }
}

/// The footer's sync state: a glyph and a short word or time. The full footer wording
/// is the tooltip and accessibility label; clicking syncs the challenge now.
struct SyncFooterItem: View {
    let model: TrackerModel
    var compact = false

    var body: some View {
        let state = model.syncState
        Button {
            guard model.syncActive, !model.isSyncing else { return }
            Task { await model.sync(force: true) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: Self.symbol(state)).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Self.tint(state))
                if !compact {
                    Text(Self.shortText(state)).font(Theme.Fonts.pill).monospacedDigit()
                        .foregroundStyle(Self.textTint(state))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.syncStatus + "\n\nActivity is saved locally first. Synced means the last server check succeeded; another offline Mac may still have pending work. Clock warnings can also mean delayed offline delivery."
            + (model.syncActive ? "\nClick to sync now." : ""))
        .accessibilityLabel(model.syncStatus)
        .accessibilityHint(model.syncActive ? "Sync challenge now" : "")
        .textSelection(.enabled)
    }

    static func symbol(_ state: SyncState) -> String {
        switch state {
        case .synced(_, true): "clock.badge.exclamationmark"
        case .synced: "checkmark.icloud"
        case .checking, .savedLocally: "icloud.and.arrow.up"
        case .awaitingCheck: "icloud"
        case .unavailable: "exclamationmark.icloud"
        case .localOnly: "icloud.slash"
        }
    }

    static func shortText(_ state: SyncState) -> String {
        switch state {
        case let .synced(date, _): date.formatted(date: .omitted, time: .shortened)
        case .checking: "Syncing"
        case let .savedLocally(pending): "\(pending) pending"
        case .awaitingCheck: "Checking"
        case .unavailable: "Retry"
        case .localOnly: "Local only"
        }
    }

    static func tint(_ state: SyncState) -> Color {
        switch state {
        case .synced(_, false): Theme.done
        case .synced(_, true), .unavailable: Theme.amber
        case .checking, .savedLocally, .awaitingCheck: Theme.accentText
        case .localOnly: Theme.textTertiary
        }
    }

    static func textTint(_ state: SyncState) -> Color {
        switch state {
        case .unavailable: Theme.amberText
        case .localOnly: Theme.textTertiary
        default: Theme.textSecondary
        }
    }
}
