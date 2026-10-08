import AppKit
import ChallengeCore
import SwiftUI

enum TrackerSection: String, CaseIterable { case today = "Today", history = "History", account = "Account" }

struct TrackerView: View {
    @Bindable var model: TrackerModel
    @Bindable var auth: ProofModel
    @State var section = TrackerSection.today
    @State private var setupDate = Date()
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label("Daily Challenge", systemImage: "drop.fill").font(.headline)
                Spacer()
                if model.dayNumber > 0 { Text("Day \(model.dayNumber)").font(.caption).foregroundStyle(.secondary) }
            }
            if auth.ownerID == nil {
                ProofView(model: auth)
            } else {
                Picker("Section", selection: $section) {
                    ForEach(TrackerSection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                if section == .account {
                    ScrollView { AccountView(auth: auth, tracker: model).padding(.trailing, 12) }.frame(height: 480)
                } else if model.store == nil {
                    ContentUnavailableView {
                        Label("History unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("Your saved data has not been reset.")
                    } actions: {
                        Button("Try again") { model.reload() }
                    }.frame(height: 220)
                } else if model.challenge == nil {
                    if model.canStartChallenge { setup }
                    else {
                        VStack(spacing: 12) {
                            Text("Checking for your existing challenge").font(.headline)
                            Text("Setup needs a successful server check. Your other Mac may already have a challenge.")
                                .font(.caption)
                            Button("Check again") { Task { await model.sync(force: true) } }
                                .disabled(model.isSyncing)
                        }.frame(height: 220)
                    }
                } else if section == .today {
                    TodayTrackerView(model: model)
                } else {
                    HistoryTrackerView(model: model)
                }
                if let error = model.errorMessage, section != .account {
                    HStack(alignment: .top) {
                        Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                        Spacer()
                        Button { model.dismissError() } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel("Dismiss error")
                    }
                }
            }
            Divider()
            HStack {
                if auth.ownerID != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(model.syncStatus, systemImage: model.syncActive ? "arrow.triangle.2.circlepath.icloud" : "internaldrive")
                            .font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if model.syncActive {
                            Button("Sync challenge now") { Task { await model.sync(force: true) } }
                                .font(.caption).disabled(model.isSyncing)
                        }
                    }
                    .help("Activity is saved locally first. Synced means the last server check succeeded; another offline Mac may still have pending work. Clock warnings can also mean delayed offline delivery.")
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }.controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 420)
        .environment(\.trackerPopupVisible, isVisible)
        .background { PopupVisibilityReader { isVisible = $0 } }
        .environment(\.calendar, JerseyDates.calendar)
        .environment(\.timeZone, JerseyDates.calendar.timeZone)
        .onAppear {
            auth.start()
            model.activate(ownerID: auth.ownerID)
            model.refresh()
            model.requestSync()
        }
        .onDisappear { isVisible = false }
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
                let midnight = JerseyDates.calendar.dateInterval(of: .day, for: current)!.end
                let seconds = max(0.1, min(30, midnight.timeIntervalSince(current)))
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                if isVisible { model.refresh() }
            }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your next 75 days").font(.title2.bold())
            Text("Start in Jersey time. Every day, complete all five:")
                .font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 9) {
                Label("4 litres of water", systemImage: "drop")
                Label("45-minute workout · home or gym", systemImage: "dumbbell")
                Label("45-minute walk", systemImage: "figure.walk")
                Label("Clean diet · your own rules", systemImage: "leaf")
                Label("10 Bible pages", systemImage: "book")
            }.font(.callout)
            DatePicker("Start date", selection: $setupDate, in: ...model.now, displayedComponents: .date)
            Text("Closed unfinished days break the streak. Earlier days need explicit entries. Tracking continues beyond 75.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Use the same app account on both Macs. Activity saves locally first, then syncs. Appearance stays on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(10).trackerCard(cornerRadius: 10)
            Button("Start challenge") { model.startChallenge(on: setupDate) }
                .buttonStyle(.borderedProminent)
        }.padding(.vertical, 8)
    }
}

struct TodayTrackerView: View {
    @Bindable var model: TrackerModel

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(JerseyDates.label(model.now)).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if model.summary?.isComplete == true {
                    Label("Complete", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                } else { Text("\(completedCount)/5").foregroundStyle(.secondary) }
            }.font(.caption)
            WaterJugView(millilitres: model.summary?.waterMillilitres ?? 0)
                .frame(height: 190)
                .overlay { CompletionEffect(event: model.celebration) }
            WaterControls(model: model)
            HabitControls(model: model)
            HStack {
                Label("\(model.streaks?.current ?? 0) / 75", systemImage: "flame.fill")
                    .font(.title3.bold()).foregroundStyle(.orange)
                    .accessibilityLabel("Current streak: \(model.streaks?.current ?? 0) days. Goal: 75 days.")
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Best \(model.streaks?.best ?? 0)")
                    if let milestones = model.streaks?.milestones, !milestones.isEmpty {
                        Label("\(milestones.count) milestone\(milestones.count == 1 ? "" : "s")", systemImage: "trophy")
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(12).trackerCard()
        }
    }

    private var completedCount: Int {
        guard let summary = model.summary else { return 0 }
        return summary.completedHabits.count + (summary.waterComplete ? 1 : 0) + (summary.diet == .clean ? 1 : 0)
    }
}

struct WaterControls: View {
    @Bindable var model: TrackerModel
    @State private var showingCustom = false
    @State private var customAmount = ""

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Button { model.undoWater() } label: { Image(systemName: "minus").frame(width: 28, height: 24) }
                    .disabled(!model.canUndo).accessibilityLabel("Undo latest water pour")
                    .help("Undo the most recent active pour on the selected day")
                VStack(spacing: 1) {
                    Text("\((model.summary?.waterMillilitres ?? 0).formatted()) ml").font(.title3.monospacedDigit().bold())
                    Text("of 4,000 ml").font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
                Button { model.addWater() } label: { Label("450 ml", systemImage: "plus").frame(height: 24) }
                    .buttonStyle(.borderedProminent).disabled(!model.canEdit)
                    .accessibilityLabel("Add 450 millilitres of water")
            }
            Button("Custom pour…") { customAmount = ""; showingCustom = true }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).disabled(!model.canEdit)
                .popover(isPresented: $showingCustom) {
                    CustomPourView(amount: $customAmount, cancel: { showingCustom = false }, submit: submitCustom)
                }
        }
    }

    private func submitCustom() {
        model.addCustomWater(customAmount)
        if model.errorMessage == nil { showingCustom = false }
    }
}

struct CustomPourView: View {
    @Binding var amount: String
    let cancel: () -> Void
    let submit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom water pour").font(.headline)
            TextField("Amount in ml", text: $amount).textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            HStack {
                Button("Cancel", action: cancel)
                Spacer()
                Button("Add", action: submit).buttonStyle(.borderedProminent)
                    .disabled(Int(amount.trimmingCharacters(in: .whitespacesAndNewlines)).map { $0 > 0 } != true)
            }
        }.padding(16).frame(width: 250).trackerSurface()
    }
}

struct HabitControls: View {
    @Bindable var model: TrackerModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            habit(.workout, title: "Workout", detail: "45 min · home / gym", icon: "dumbbell")
            habit(.walk, title: "Walk", detail: "45 minutes", icon: "figure.walk")
            diet
            habit(.bibleReading, title: "Bible", detail: "10 pages", icon: "book")
        }
    }

    private func habit(_ habit: Challenge.Habit, title: String, detail: String, icon: String) -> some View {
        let complete = model.summary?.completedHabits.contains(habit) ?? false
        return Button { model.toggle(habit) } label: {
            tile(title, detail: detail, icon: icon, state: complete ? "checkmark.circle.fill" : "circle", color: complete ? .green : .secondary)
        }.buttonStyle(.plain).disabled(!model.canEdit)
            .accessibilityLabel("\(title), \(detail)")
            .accessibilityValue(complete ? "Complete" : "Not complete")
            .accessibilityHint("Press to \(complete ? "undo" : "mark complete")")
            .help("\(title): \(detail). Click to \(complete ? "undo" : "complete").")
    }

    private var diet: some View {
        let state = model.summary?.diet ?? .pending
        return Button {
            model.setDiet(state == .pending ? .clean : state == .clean ? .missed : .pending)
        } label: {
            tile("Diet", detail: state.rawValue.capitalized, icon: "leaf",
                 state: state == .clean ? "checkmark.circle.fill" : state == .missed ? "xmark.circle.fill" : "circle",
                 color: state == .clean ? .green : state == .missed ? .red : .secondary)
        }.buttonStyle(.plain).disabled(!model.canEdit)
            .accessibilityLabel("Clean diet, your own rules").accessibilityValue(state.rawValue)
            .accessibilityHint("Press to cycle pending, clean and missed")
            .help("Click to cycle pending → clean → missed. Right-click to choose.")
            .contextMenu {
                ForEach([Challenge.DietState.pending, .clean, .missed], id: \.self) { value in
                    Button(value.rawValue.capitalized) { model.setDiet(value) }.disabled(!model.canEdit)
                }
            }
    }

    private func tile(_ title: String, detail: String, icon: String, state: String, color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.title3).frame(width: 25)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: state).foregroundStyle(color)
        }.padding(10).frame(maxWidth: .infinity, minHeight: 64)
            .trackerCard()
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
