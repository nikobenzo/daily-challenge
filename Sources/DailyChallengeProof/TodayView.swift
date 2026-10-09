import ChallengeCore
import ChallengeSyncKit
import SwiftUI

/// Today: five ring gauges, the water hero and the streak row, separated by hairlines.
struct TodayTrackerView: View {
    @Bindable var model: TrackerModel
    @Environment(\.trackerReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        let complete = model.summary?.isComplete == true
        VStack(spacing: 0) {
            RingRow(model: model)
                .padding(.horizontal, 12)
                .padding(.vertical, Theme.Size.sectionVertical + 2)
            HairlineDivider()
            if model.summary?.extrasTotal ?? 0 > 0 {
                ExtrasSection(model: model)
                    .padding(.horizontal, Theme.Size.sectionHorizontal)
                    .padding(.vertical, 4)
                HairlineDivider()
            }
            if complete {
                CompletionBand(day: model.dayNumber)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                HairlineDivider()
            }
            WaterSection(model: model)
                .padding(.horizontal, Theme.Size.sectionHorizontal)
                .padding(.vertical, Theme.Size.sectionVertical + 2)
            HairlineDivider()
            StreakRow(streaks: model.streaks)
                .padding(.horizontal, Theme.Size.sectionHorizontal)
                .padding(.vertical, Theme.Size.sectionVertical)
        }
        .animation(reduceMotion ? nil : Theme.Motion.band, value: complete)
    }
}

/// WATER · WORKOUT · WALK · DIET · BIBLE. Water mirrors the jug; the four habit rings
/// are the habit controls (click to toggle; diet cycles and has a context menu).
struct RingRow: View {
    @Bindable var model: TrackerModel

    var body: some View {
        HStack(spacing: 0) {
            water.frame(maxWidth: .infinity)
            habit(.workout, title: "Workout", detail: "45 min · home / gym", icon: "dumbbell").frame(maxWidth: .infinity)
            habit(.walk, title: "Walk", detail: "45 minutes", icon: "figure.walk").frame(maxWidth: .infinity)
            diet.frame(maxWidth: .infinity)
            habit(.bibleReading, title: "Bible", detail: "10 pages", icon: "book").frame(maxWidth: .infinity)
        }
    }

    private var closed: Bool { model.summary?.status == .missed }

    private var water: some View {
        let ml = model.summary?.waterMillilitres ?? 0
        let state: RingGauge.State = model.summary?.waterComplete == true ? .done
            : closed ? .missed : ml == 0 ? .pending : .progress(Double(ml) / 4_000)
        return RingGauge(symbol: "drop.fill", label: "Water", state: state, showsPercent: true)
            .help("Water: \(ml.formatted()) of 4,000 ml")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Water")
            .accessibilityValue("\(ml) of 4,000 millilitres")
    }

    private func habit(_ habit: Challenge.Habit, title: String, detail: String, icon: String) -> some View {
        let complete = model.summary?.completedHabits.contains(habit) ?? false
        return Button { model.toggle(habit) } label: {
            RingGauge(symbol: icon, label: title, state: complete ? .done : closed ? .missed : .pending)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!model.canEdit)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityValue(complete ? "Complete" : "Not complete")
        .accessibilityHint("Press to \(complete ? "undo" : "mark complete")")
        .help("\(title): \(detail). Click to \(complete ? "undo" : "complete").")
    }

    private var diet: some View {
        let state = model.summary?.diet ?? .pending
        let ring: RingGauge.State = state == .clean ? .done : state == .missed || closed ? .missed : .pending
        return Button {
            model.setDiet(state == .pending ? .clean : state == .clean ? .missed : .pending)
        } label: {
            RingGauge(symbol: "leaf", label: "Diet", state: ring).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!model.canEdit)
        .accessibilityLabel("Clean diet, your own rules").accessibilityValue(state.rawValue)
        .accessibilityHint("Press to cycle pending, clean and missed")
        .help("Diet: \(state.rawValue.capitalized). Click to cycle pending → clean → missed. Right-click to choose.")
        .contextMenu { DietMenu(model: model) }
    }
}

struct DietMenu: View {
    let model: TrackerModel

    var body: some View {
        ForEach([Challenge.DietState.pending, .clean, .missed], id: \.self) { value in
            Button(value.rawValue.capitalized) { model.setDiet(value) }.disabled(!model.canEdit)
        }
    }
}

/// "All five complete! / Day 12 counts toward your streak".
struct CompletionBand: View {
    let day: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 30))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Theme.onDone, Theme.done)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("All five complete!").font(Theme.Fonts.appName).foregroundStyle(Theme.textPrimary)
                Text("Day \(day) counts toward your streak").font(Theme.Fonts.caption).foregroundStyle(Theme.doneText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Size.sectionHorizontal)
        .padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity)
        .background(Theme.doneTint)
        .accessibilityElement(children: .combine)
    }
}

struct WaterSection: View {
    @Bindable var model: TrackerModel

    var body: some View {
        let ml = model.summary?.waterMillilitres ?? 0
        let complete = model.summary?.waterComplete == true
        HStack(spacing: 18) {
            WaterJugView(millilitres: ml)
                .frame(width: Theme.Size.jug.width + 8, height: Theme.Size.jug.height + 14)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(ml.formatted()) ml").font(Theme.Fonts.hero).tracking(Theme.Tracking.hero)
                        .monospacedDigit().foregroundStyle(Theme.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("/ 4,000").font(Theme.Fonts.caption)
                        .foregroundStyle(complete ? Theme.doneText : Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
                WaterControls(model: model)
            }
        }
        .overlay { CompletionEffect(event: model.celebration) }
    }
}

/// −, + 450 ml and ⋯ (custom pour). Today uses the wide layout; History the compact
/// one with the total between the controls.
struct WaterControls: View {
    @Bindable var model: TrackerModel
    var compact = false
    @State private var showingCustom = false
    @State private var customAmount = ""

    var body: some View {
        let ml = model.summary?.waterMillilitres ?? 0
        HStack(spacing: compact ? 10 : 12) {
            Button { model.undoWater() } label: { Image(systemName: "minus") }
                .buttonStyle(RoundIconStyle(size: compact ? 40 : Theme.Size.pill))
                .disabled(!model.canUndo).accessibilityLabel("Undo latest water pour")
                .help("Undo the most recent active pour on the selected day")
            if compact {
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "drop.fill").font(.system(size: 15)).foregroundStyle(Theme.water)
                    Text(ml.formatted()).font(.system(size: 22, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text("/ 4,000 ml").font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                }
                .lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(ml) of 4,000 millilitres")
                Spacer(minLength: 0)
            }
            add(complete: model.summary?.waterComplete == true)
            Button { customAmount = ""; showingCustom = true } label: { Image(systemName: "ellipsis") }
                .buttonStyle(RoundIconStyle(size: compact ? 40 : Theme.Size.pill))
                .disabled(!model.canEdit)
                .accessibilityLabel("Custom pour").help("Custom pour…")
                .popover(isPresented: $showingCustom) {
                    CustomPourView(amount: $customAmount, cancel: { showingCustom = false }, submit: submitCustom)
                }
        }
    }

    /// Primary until the goal is met, then a quieter tinted pill.
    @ViewBuilder
    private func add(complete: Bool) -> some View {
        let label = Label(compact ? "450" : "450 ml", systemImage: "plus")
        if complete {
            Button { model.addWater() } label: { label }
                .buttonStyle(TintedPillStyle(height: compact ? 40 : Theme.Size.pill, expands: !compact))
                .disabled(!model.canEdit)
                .accessibilityLabel("Add 450 millilitres of water")
        } else {
            Button { model.addWater() } label: { label }
                .buttonStyle(PrimaryPillStyle(height: compact ? 40 : Theme.Size.pill, expands: !compact))
                .disabled(!model.canEdit)
                .accessibilityLabel("Add 450 millilitres of water")
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
    @FocusState private var focus: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Custom pour", systemImage: "drop.fill").font(Theme.Fonts.appName)
                .foregroundStyle(Theme.textPrimary)
            GlassField(symbol: "drop", placeholder: "Amount in ml", text: $amount, focus: $focus, equals: true, onSubmit: submit)
                .onAppear { focus = true }
            HStack {
                Button("Cancel", action: cancel).buttonStyle(TintedPillStyle(height: 36))
                Spacer()
                Button(action: submit) { Label("Add", systemImage: "plus") }
                    .buttonStyle(PrimaryPillStyle(height: 36, expands: false))
                    .keyboardShortcut(.defaultAction)
                    .disabled(Int(amount.trimmingCharacters(in: .whitespacesAndNewlines)).map { $0 > 0 } != true)
            }
        }.padding(16).frame(width: 260).trackerSurface().focusEffectDisabled()
    }
}

/// Flame "12 / 75 days" with the best streak (and any 75-day milestones) as badges.
struct StreakRow: View {
    let streaks: Challenge.StreakSummary?

    var body: some View {
        let current = streaks?.current ?? 0
        let best = streaks?.best ?? 0
        let milestones = streaks?.milestones.count ?? 0
        HStack(spacing: 10) {
            Image(systemName: "flame.fill").font(.system(size: 22))
                .foregroundStyle(LinearGradient(colors: [Theme.amber, Theme.amberText], startPoint: .top, endPoint: .bottom))
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(current)").font(Theme.Fonts.streak).foregroundStyle(Theme.amberText).monospacedDigit()
                Text("/ 75 days").font(Theme.Fonts.link).foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Current streak: \(current) days. Goal: 75 days.")
            Spacer()
            if milestones > 0 {
                Badge(symbol: "rosette", text: "\(milestones)", fill: Theme.doneTint, foreground: Theme.doneText, height: 28)
                    .help("\(milestones) milestone\(milestones == 1 ? "" : "s"): 75 consecutive days")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(milestones) milestone\(milestones == 1 ? "" : "s")")
            }
            Badge(symbol: "trophy.fill", text: "\(best)", fill: Theme.bestBadgeFill, foreground: Theme.bestBadgeText,
                  height: 28, symbolColor: Theme.amber)
                .help("Best streak: \(best) days")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Best streak: \(best) days")
        }
    }
}
