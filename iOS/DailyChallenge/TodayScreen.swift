import ChallengeCore
import ChallengeSyncKit
import SwiftUI

/// Today: the five ring gauges, the water jug and its controls, and the streak, in one
/// glass card separated by hairlines, as on the Mac.
struct TodayScreen: View {
    @Bindable var tracker: TrackerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let complete = tracker.summary?.isComplete == true
        PhoneScreen {
            PhoneHeader {
                if tracker.dayNumber > 0 { DayBadge(tracker: tracker) }
            }
            HStack {
                Text(tracker.dates.label(tracker.today, format: "EEEE d MMMM"))
                    .font(Theme.Fonts.link).foregroundStyle(Theme.textSecondary)
                Spacer()
                SyncChip(tracker: tracker)
            }
            GlassCard {
                PhoneRingRow(tracker: tracker)
                    .padding(.horizontal, Theme.Space.xs)
                    .padding(.vertical, Theme.Size.sectionVertical + 2)
                HairlineDivider()
                if complete {
                    CompletionBand(day: tracker.dayNumber)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    HairlineDivider()
                }
                PhoneWaterSection(tracker: tracker)
                    .padding(.horizontal, Theme.Size.sectionHorizontal)
                    .padding(.vertical, Theme.Size.sectionVertical + 2)
                HairlineDivider()
                PhoneStreakRow(streaks: tracker.streaks)
                    .padding(.horizontal, Theme.Size.sectionHorizontal)
                    .padding(.vertical, Theme.Size.sectionVertical)
            }
            .animation(reduceMotion ? nil : Theme.Motion.band, value: complete)
            ErrorBanner(tracker: tracker)
        }
    }
}

/// WATER · WORKOUT · WALK · DIET · BIBLE. Water mirrors the jug; the four habit rings are
/// the habit controls (tap to toggle; diet cycles, and a long press chooses directly).
/// At accessibility text sizes the rings wrap onto two rows.
struct PhoneRingRow: View {
    @Bindable var tracker: TrackerModel
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                    GridRow { water; habit(.workout, "Workout", "45 min · home / gym", "dumbbell"); habit(.walk, "Walk", "45 minutes", "figure.walk") }
                    GridRow { diet; habit(.bibleReading, "Bible", "10 pages", "book") }
                }
            } else {
                HStack(spacing: 0) {
                    water.frame(maxWidth: .infinity)
                    habit(.workout, "Workout", "45 min · home / gym", "dumbbell").frame(maxWidth: .infinity)
                    habit(.walk, "Walk", "45 minutes", "figure.walk").frame(maxWidth: .infinity)
                    diet.frame(maxWidth: .infinity)
                    habit(.bibleReading, "Bible", "10 pages", "book").frame(maxWidth: .infinity)
                }
            }
        }
        // The rings are fixed 64 pt drawings; their labels stop growing at the largest standard size.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var closed: Bool { tracker.summary?.status == .missed }

    private var water: some View {
        let ml = tracker.summary?.waterMillilitres ?? 0
        let state: RingGauge.State = tracker.summary?.waterComplete == true ? .done
            : closed ? .missed : ml == 0 ? .pending : .progress(Double(ml) / 4_000)
        return RingGauge(symbol: "drop.fill", label: "Water", state: state, showsPercent: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Water")
            .accessibilityValue("\(ml) of 4,000 millilitres")
            .accessibilityIdentifier("ring-water")
    }

    private func habit(_ habit: Challenge.Habit, _ title: String, _ detail: String, _ icon: String) -> some View {
        let complete = tracker.summary?.completedHabits.contains(habit) ?? false
        return Button { tracker.toggle(habit) } label: {
            RingGauge(symbol: icon, label: title, state: complete ? .done : closed ? .missed : .pending)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!tracker.canEdit)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityValue(complete ? "Complete" : "Not complete")
        .accessibilityHint("Double-tap to \(complete ? "undo" : "mark complete")")
        .accessibilityIdentifier("ring-\(habit.rawValue)")
    }

    private var diet: some View {
        let state = tracker.summary?.diet ?? .pending
        let ring: RingGauge.State = state == .clean ? .done : state == .missed || closed ? .missed : .pending
        return Button {
            tracker.setDiet(state == .pending ? .clean : state == .clean ? .missed : .pending)
        } label: {
            RingGauge(symbol: "leaf", label: "Diet", state: ring).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!tracker.canEdit)
        .accessibilityLabel("Clean diet, your own rules").accessibilityValue(state.rawValue)
        .accessibilityHint("Double-tap to cycle pending, clean and missed")
        .accessibilityIdentifier("ring-diet")
        .contextMenu { PhoneDietMenu(tracker: tracker) }
    }
}

struct PhoneDietMenu: View {
    let tracker: TrackerModel

    var body: some View {
        ForEach([Challenge.DietState.pending, .clean, .missed], id: \.self) { value in
            Button(value.rawValue.capitalized) { tracker.setDiet(value) }.disabled(!tracker.canEdit)
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

/// The jug beside the total, then the pour controls across the full width (on a phone the
/// Mac's row beside the jug would truncate "450 ml"); stacked at accessibility text sizes.
struct PhoneWaterSection: View {
    @Bindable var tracker: TrackerModel
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let ml = tracker.summary?.waterMillilitres ?? 0
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(spacing: 18))
        VStack(spacing: 16) {
            layout {
                WaterJugView(millilitres: ml)
                    .frame(width: Theme.Size.jug.width + 8, height: Theme.Size.jug.height + 14)
                    .accessibilityIdentifier("water-jug")
                WaterTotal(tracker: tracker, font: Theme.Fonts.hero)
                Spacer(minLength: 0)
            }
            PhoneWaterControls(tracker: tracker)
        }
        .overlay { CompletionEffect(event: tracker.celebration) }
    }
}

/// "2,250 ml / 4,000" for the selected day, with the goal turning green once met.
struct WaterTotal: View {
    let tracker: TrackerModel
    let font: Font

    var body: some View {
        let ml = tracker.summary?.waterMillilitres ?? 0
        let complete = tracker.summary?.waterComplete == true
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(ml.formatted()) ml").font(font).tracking(Theme.Tracking.hero)
                .monospacedDigit().foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text("/ 4,000").font(Theme.Fonts.caption)
                .foregroundStyle(complete ? Theme.doneText : Theme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ml) of 4,000 millilitres")
        .accessibilityIdentifier("water-total")
    }
}

/// −, + 450 ml and ⋯ (custom pour), for the selected day.
struct PhoneWaterControls: View {
    @Bindable var tracker: TrackerModel
    @State private var showingCustom = false
    @State private var customAmount = ""

    var body: some View {
        let size: CGFloat = 44
        HStack(spacing: 12) {
            Button { tracker.undoWater() } label: { Image(systemName: "minus") }
                .buttonStyle(RoundIconStyle(size: size))
                .disabled(!tracker.canUndo)
                .accessibilityLabel("Undo latest water pour")
                .accessibilityIdentifier("water-undo")
            add
            Button { customAmount = ""; showingCustom = true } label: { Image(systemName: "ellipsis") }
                .buttonStyle(RoundIconStyle(size: size))
                .disabled(!tracker.canEdit)
                .accessibilityLabel("Custom pour")
                .accessibilityIdentifier("water-custom")
        }
        .alert("Custom pour", isPresented: $showingCustom) {
            TextField("Amount in ml", text: $customAmount).keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Add") { tracker.addCustomWater(customAmount) }
        } message: {
            Text("Whole millilitres, such as 250.")
        }
    }

    /// Primary until the goal is met, then a quieter tinted pill.
    @ViewBuilder private var add: some View {
        let label = Label("450 ml", systemImage: "plus").lineLimit(1)
        Group {
            if tracker.summary?.waterComplete == true {
                Button { tracker.addWater() } label: { label }
                    .buttonStyle(TintedPillStyle(height: 44, expands: true))
            } else {
                Button { tracker.addWater() } label: { label }
                    .buttonStyle(PrimaryPillStyle(height: 44, expands: true))
            }
        }
        .disabled(!tracker.canEdit)
        .accessibilityLabel("Add 450 millilitres of water")
        .accessibilityIdentifier("water-add")
    }
}

/// Flame "12 / 75 days" with the best streak (and any 75-day milestones) as badges.
struct PhoneStreakRow: View {
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
            .accessibilityIdentifier("streak-current")
            Spacer()
            if milestones > 0 {
                Badge(symbol: "rosette", text: "\(milestones)", fill: Theme.doneTint, foreground: Theme.doneText, height: 28)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(milestones) milestone\(milestones == 1 ? "" : "s")")
            }
            Badge(symbol: "trophy.fill", text: "\(best)", fill: Theme.bestBadgeFill, foreground: Theme.bestBadgeText,
                  height: 28, symbolColor: Theme.amber)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Best streak: \(best) days")
        }
    }
}
