import ChallengeSyncKit
import SwiftUI

/// Signed out: the auth screens. Signed in: a tab bar (Today, History, Account) in place
/// of the Mac's icon switcher; Account stays reachable before a challenge exists.
struct RootView: View {
    @Bindable var app: PhoneApp
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if !app.auth.configurationReady {
                PhoneScreen {
                    PhoneHeader()
                    NoticeCard(symbol: "gearshape", title: "Configuration unavailable",
                               detail: app.auth.errorMessage ?? "This build cannot reach the server.") { EmptyView() }
                }
            } else if app.auth.ownerID == nil {
                AuthScreen(auth: app.auth, app: app)
            } else {
                tabs
            }
        }
        // Theme's Dynamic Type fonts are resolved when a body runs: rebuild on a size change.
        .id(typeSize)
        // Presentation clocks (jug, celebration) run only while the app is on screen.
        .environment(\.trackerPopupVisible, phase == .active)
        .environment(\.calendar, app.tracker.dates.calendar)
        .environment(\.timeZone, app.tracker.dates.timeZone)
        .onChange(of: app.auth.ownerID) { _, owner in
            app.tracker.activate(ownerID: owner)
            app.tab = .today
        }
        .onChange(of: app.tab) { _, tab in
            if tab == .today { app.tracker.showToday() }
            if tab == .history { app.tracker.selectHistoryDay(app.tracker.today) }
        }
        .task {
            // Midnight in the challenge's zone rolls Today over while the app stays open.
            while !Task.isCancelled {
                let current = Date()
                let midnight = app.tracker.dates.calendar.dateInterval(of: .day, for: current)!.end
                do { try await Task.sleep(for: .seconds(max(0.1, min(30, midnight.timeIntervalSince(current))))) }
                catch { return }
                if phase == .active { app.tracker.refresh() }
            }
        }
    }

    private var tabs: some View {
        TabView(selection: $app.tab) {
            Tab("Today", systemImage: "sun.max", value: PhoneTab.today) {
                TodayTab(app: app)
            }
            .accessibilityIdentifier("tab-today")
            Tab("History", systemImage: "calendar", value: PhoneTab.history) {
                HistoryTab(app: app)
            }
            .accessibilityIdentifier("tab-history")
            Tab("Account", systemImage: "person", value: PhoneTab.account) {
                AccountScreen(app: app)
            }
            .accessibilityIdentifier("tab-account")
        }
        .tint(Theme.accentText)
    }
}

/// Today, or what stands in for it before a challenge: setup, the server check, or an
/// unreadable local history (never reset).
struct TodayTab: View {
    let app: PhoneApp

    var body: some View {
        let tracker = app.tracker
        if tracker.store == nil {
            PhoneScreen {
                PhoneHeader()
                NoticeCard(symbol: "exclamationmark.triangle", title: "History unavailable",
                           detail: tracker.errorMessage ?? "Your saved data has not been reset.") {
                    Button("Try again") { tracker.reload() }.buttonStyle(TintedPillStyle())
                }
            }
        } else if tracker.challenge == nil {
            if tracker.canStartChallenge {
                SetupScreen(tracker: tracker)
            } else {
                CheckingScreen(tracker: tracker)
            }
        } else {
            TodayScreen(tracker: tracker)
        }
    }
}

/// Setup waits for a successful server check, so an existing challenge is adopted, never duplicated.
struct CheckingScreen: View {
    let tracker: TrackerModel

    var body: some View {
        PhoneScreen {
            PhoneHeader { SyncChip(tracker: tracker) }
            NoticeCard(symbol: "icloud.and.arrow.down", title: "Checking for your existing challenge",
                       detail: "Setup needs a successful server check. Your Mac or another device may already have a challenge, and this iPhone will use it.") {
                Button { Task { await tracker.sync(force: true) } } label: {
                    Label("Check again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(TintedPillStyle())
                .disabled(tracker.isSyncing)
            }
            if let error = tracker.syncError {
                Text(error).font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct HistoryTab: View {
    let app: PhoneApp

    var body: some View {
        if app.tracker.challenge == nil {
            PhoneScreen {
                PhoneHeader(title: "History")
                NoticeCard(symbol: "calendar", title: "No history yet",
                           detail: "Your calendar starts once your challenge does. Set it up on Today.") {
                    Button("Go to Today") { app.tab = .today }.buttonStyle(TintedPillStyle())
                }
            }
        } else {
            HistoryScreen(tracker: app.tracker)
        }
    }
}
