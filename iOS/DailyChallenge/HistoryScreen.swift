import ChallengeCore
import ChallengeSyncKit
import SwiftUI

/// History: the month calendar, the selected day's card with its explicit Edit unlock,
/// and the day's activity, newest first. Same rules as the Mac: selecting a day is not
/// an edit; corrections need the pencil and recalculate streaks and milestones.
struct HistoryScreen: View {
    @Bindable var tracker: TrackerModel
    @State private var month = Date()

    var body: some View {
        PhoneScreen {
            PhoneHeader(title: "History") { SyncChip(tracker: tracker) }
            GlassCard {
                calendar
                    .padding(.horizontal, Theme.Size.sectionHorizontal)
                    .padding(.vertical, 14)
                HairlineDivider()
                dayCard
                    .id("fixture-history-day")
                    .padding(.horizontal, Theme.Size.sectionHorizontal)
                    .padding(.vertical, Theme.Size.sectionVertical)
            }
            ErrorBanner(tracker: tracker)
            GlassCard { activity }
        }
        .onAppear { month = monthStart(tracker.selectedDay) }
        .onChange(of: tracker.selectedDay) { _, day in month = monthStart(day) }
    }

    // MARK: Calendar

    private var calendar: some View {
        VStack(spacing: 10) {
            HStack {
                Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(RoundIconStyle(size: 36))
                    .disabled(month <= monthStart(tracker.challenge?.startDate ?? tracker.today))
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(tracker.dates.label(month, format: "MMMM yyyy")).font(Theme.Fonts.appName)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(RoundIconStyle(size: 36))
                    .disabled(month >= monthStart(tracker.today))
                    .accessibilityLabel("Next month")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, label in
                    Text(label).font(Theme.Fonts.ringLabel).foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 36) }
                ForEach(daysInMonth, id: \.self) { day in dayCell(day) }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }

    private var leadingBlanks: Int {
        (tracker.dates.calendar.component(.weekday, from: month) - tracker.dates.calendar.firstWeekday + 7) % 7
    }

    private var daysInMonth: [Date] {
        guard let range = tracker.dates.calendar.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { tracker.dates.calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    /// Each state has its own shape: complete (green disc), missed (red ring), today
    /// (blue ring + halo), selected (ink disc), future/outside (faint numeral).
    private func dayCell(_ day: Date) -> some View {
        let state = tracker.challenge?.summary(on: day, asOf: tracker.now).status ?? .outsideChallenge
        let selected = tracker.dates.calendar.isDate(day, inSameDayAs: tracker.selectedDay)
        let isToday = tracker.dates.calendar.isDate(day, inSameDayAs: tracker.today)
        let allowed = state != .outsideChallenge && state != .future
        let number = Text("\(tracker.dates.calendar.component(.day, from: day))")
            .font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit()
        let size: CGFloat = 36
        return Button { tracker.selectHistoryDay(day) } label: {
            ZStack {
                if isToday {
                    Circle().stroke(Theme.focusHalo, lineWidth: 5).frame(width: size + 4, height: size + 4)
                    Circle().fill(state == .complete ? Theme.done : .clear)
                    Circle().strokeBorder(Theme.water, lineWidth: 2)
                    number.foregroundStyle(state == .complete ? Theme.onDone : Theme.textPrimary)
                } else if selected {
                    Circle().fill(Theme.textPrimary)
                    number.foregroundStyle(Theme.textInverse)
                } else if state == .complete {
                    Circle().fill(Theme.done)
                    number.foregroundStyle(Theme.onDone)
                } else if state == .missed {
                    Circle().strokeBorder(Theme.dangerRing, lineWidth: 1.5)
                    number.foregroundStyle(Theme.danger)
                } else if allowed {
                    Circle().fill(Theme.controlFill)
                    number.foregroundStyle(Theme.textPrimary)
                } else {
                    number.foregroundStyle(Theme.futureDay)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!allowed)
        .accessibilityLabel("\(tracker.dates.label(day, format: "d MMMM yyyy")), \(name(state))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Day card

    private var dayCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text(tracker.dates.label(tracker.selectedDay, format: "EEE d MMM"))
                    .font(Theme.Fonts.screenTitle).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                statusBadge
                Spacer(minLength: 0)
                editChip
            }
            HStack(spacing: 8) {
                Image(systemName: "drop.fill").font(.system(size: 17)).foregroundStyle(Theme.water)
                    .accessibilityHidden(true)
                WaterTotal(tracker: tracker, font: Theme.Fonts.streak)
                Spacer(minLength: 0)
            }
            PhoneWaterControls(tracker: tracker)
            PhoneHabitControls(tracker: tracker)
            if (tracker.summary?.extrasTotal ?? 0) > 0 {
                HairlineDivider()
                PhoneExtrasHeading(tracker: tracker).id("fixture-extras").frame(maxWidth: .infinity, alignment: .leading)
                PhoneExtrasChecklist(tracker: tracker)
                if !tracker.canEdit {
                    Text("Select Edit this day to correct these ticks.")
                        .font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if tracker.dates.calendar.isDate(tracker.selectedDay, inSameDayAs: tracker.today) {
            Badge(text: "Today", fill: Theme.accentTint, foreground: Theme.accentText, height: 28)
                .accessibilityLabel("Today, \(statusName)")
        } else {
            let status = tracker.summary?.status ?? .outsideChallenge
            Badge(symbol: icon(status), text: statusName,
                  fill: status == .complete ? Theme.doneTint : status == .missed ? Theme.dangerTint : Theme.controlFill,
                  foreground: status == .complete ? Theme.doneText : status == .missed ? Theme.danger : Theme.textSecondary,
                  height: 28)
        }
    }

    /// An amber pencil while the day is editable, otherwise the button that unlocks
    /// corrections for a past day.
    @ViewBuilder
    private var editChip: some View {
        if tracker.canEdit {
            Image(systemName: "pencil").font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.amberText)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.amberTint))
                .overlay(Circle().strokeBorder(Theme.amber.opacity(0.7), lineWidth: 1.5))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tracker.isEditingHistory ? "Editing this day" : "Editing today")
                .accessibilityIdentifier("history-editing")
        } else if let status = tracker.summary?.status, status != .future, status != .outsideChallenge {
            Button { tracker.enableCorrections() } label: { Image(systemName: "pencil") }
                .buttonStyle(RoundIconStyle(size: 36))
                .accessibilityLabel("Edit this day")
                .accessibilityHint("Allows corrections to this day. Streaks and milestones recalculate.")
                .accessibilityIdentifier("history-edit")
        }
    }

    // MARK: Activity

    private var activity: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "clock").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
                Eyebrow(text: "Activity", font: Theme.Fonts.caption)
                Badge(text: "\(tracker.history.count)", height: 22)
                Spacer()
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Activity and corrections, \(tracker.history.count)")
            .accessibilityAddTraits(.isHeader)
            if tracker.history.isEmpty {
                Text("No activity recorded. Closed unrecorded days are missed.")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, Theme.Space.s)
            } else {
                let contexts = ActivityWords.contexts(on: tracker.selectedDay, in: tracker.challenge)
                ForEach(tracker.history) { activity in row(activity, contexts[activity.id] ?? .init()) }
            }
        }
        .padding(.horizontal, Theme.Size.sectionHorizontal)
        .padding(.vertical, Theme.Space.xs)
    }

    private func row(_ activity: Challenge.Activity, _ context: ActivityWords.Context) -> some View {
        let (symbol, tint) = ActivityWords.icon(activity, in: context)
        return HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(ActivityWords.short(activity, in: context)).font(Theme.Fonts.field).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text(tracker.dates.label(activity.recordedAt, format: "HH:mm")).font(Theme.Fonts.caption).monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ActivityWords.long(activity, in: context)), edited \(tracker.dates.label(activity.recordedAt, format: "d MMM, HH:mm"))")
    }

    private var statusName: String { name(tracker.summary?.status ?? .outsideChallenge) }
    private func name(_ status: Challenge.DayStatus) -> String {
        switch status {
        case .complete: "Complete"
        case .missed: "Missed"
        case .inProgress: "In progress"
        case .future: "Future"
        case .outsideChallenge: "Outside challenge"
        }
    }
    private func icon(_ status: Challenge.DayStatus) -> String {
        switch status {
        case .complete: "checkmark"
        case .missed: "xmark"
        case .inProgress: "circle.dotted"
        case .future, .outsideChallenge: "minus"
        }
    }
    private func monthStart(_ date: Date) -> Date {
        tracker.dates.calendar.dateInterval(of: .month, for: date)!.start
    }
    private func changeMonth(_ offset: Int) {
        month = tracker.dates.calendar.date(byAdding: .month, value: offset, to: month)!
    }
}

/// Activity wording, as on the Mac. Written as `if case` chains so a newer client's
/// action kinds read as a generic change instead of breaking this screen. Habits are named
/// by the day's targets, and a goal change by the target it replaced.
enum ActivityWords {
    /// What an activity's wording depends on besides the activity itself.
    struct Context {
        /// The targets of the activity's day: what its habit ticks are called.
        var targets: Challenge.Targets = .standard
        /// The targets in force just before it: what a goal change replaced.
        var previous: Challenge.Targets = .standard
        /// The extra a repeat rule belongs to.
        var extraTitle: String?
    }

    /// Each activity of the challenge day starting at `day`, replayed in event order.
    static func contexts(on day: Date, in challenge: Challenge?) -> [UUID: Context] {
        guard let challenge else { return [:] }
        let targets = challenge.targets(on: day)
        let titles = Dictionary(challenge.allExtras.map { ($0.id, $0.title) }, uniquingKeysWith: { $1 })
        let earlier = challenge.calendar.date(byAdding: .day, value: -1, to: day).map { challenge.targets(on: $0) }
        var current = earlier ?? .standard
        var contexts: [UUID: Context] = [:]
        for activity in challenge.history(on: day) {
            var context = Context(targets: targets, previous: current)
            if case .setTarget(let slot, let name, let amount, let unit, let icon) = activity.action {
                current[slot] = Challenge.Target(name: name, amount: amount, unit: unit, icon: icon)
            }
            if case .setWater(let goal, let pour) = activity.action {
                current.water = Challenge.WaterTarget(goal: goal, glass: pour)
            }
            if case .scheduleExtra(let id, _, _) = activity.action { context.extraTitle = titles[id] }
            contexts[activity.id] = context
        }
        return contexts
    }

    static func habitName(_ habit: Challenge.Habit, in targets: Challenge.Targets = .standard) -> String {
        let name = targets[GoalWords.slot(habit)].name
        return habit == .bibleReading && name == "Bible" ? "Bible reading" : name
    }

    static func symbol(_ habit: Challenge.Habit, in targets: Challenge.Targets = .standard) -> String {
        GoalWords.symbol(habit, in: targets)
    }

    static func icon(_ activity: Challenge.Activity, in context: Context = Context()) -> (String, Color) {
        if case .pour = activity.action { return ("drop.fill", Theme.water) }
        if case .undoLatestPour = activity.action { return ("arrow.uturn.backward", Theme.textSecondary) }
        if case .setDiet(let value) = activity.action {
            return (GoalWords.symbol(.diet, context.targets.diet),
                    value == .clean ? Theme.done : value == .missed ? Theme.danger : Theme.textTertiary)
        }
        if case .setHabit(let habit, let completed) = activity.action {
            return (symbol(habit, in: context.targets), completed ? Theme.done : Theme.textTertiary)
        }
        if case .defineExtra = activity.action { return ("checklist", Theme.textSecondary) }
        if case .archiveExtra = activity.action { return ("archivebox", Theme.textSecondary) }
        if case .setExtra(_, let completed) = activity.action {
            return ("checkmark.circle", completed ? Theme.done : Theme.textTertiary)
        }
        if case .setTarget(let slot, let name, let amount, let unit, let icon) = activity.action {
            return (GoalWords.symbol(slot, Challenge.Target(name: name, amount: amount, unit: unit, icon: icon)), Theme.textSecondary)
        }
        if case .setWater = activity.action { return ("drop", Theme.water) }
        if case .scheduleExtra = activity.action { return ("repeat", Theme.textSecondary) }
        return ("square.and.pencil", Theme.textSecondary)
    }

    static func short(_ activity: Challenge.Activity, in context: Context = Context()) -> String {
        if case .pour(let amount) = activity.action { return "+\(amount.formatted()) ml" }
        if case .undoLatestPour = activity.action { return "Undid pour" }
        if case .setDiet(let value) = activity.action { return "\(context.targets.diet.name) \(value.rawValue)" }
        if case .setHabit(let habit, let completed) = activity.action {
            return "\(habitName(habit, in: context.targets)) \(completed ? "complete" : "not complete")"
        }
        if case .defineExtra(_, let title) = activity.action { return "Extra named “\(title)”" }
        if case .archiveExtra = activity.action { return "Archived extra" }
        if case .setExtra(_, let completed) = activity.action { return "Extra \(completed ? "done" : "not done")" }
        if let words = goalChange(activity, context, spoken: false) { return words }
        return "Changed"
    }

    static func long(_ activity: Challenge.Activity, in context: Context = Context()) -> String {
        if case .pour(let amount) = activity.action { return "Added \(amount.formatted()) ml" }
        if case .undoLatestPour = activity.action { return "Undid a water pour" }
        if case .setDiet(let value) = activity.action { return "\(context.targets.diet.name) set to \(value.rawValue)" }
        if case .setHabit(let habit, let completed) = activity.action {
            return "\(habitName(habit, in: context.targets)) set to \(completed ? "complete" : "not complete")"
        }
        if case .defineExtra(_, let title) = activity.action { return "Extra named “\(title)”" }
        if case .archiveExtra = activity.action { return "Archived extra" }
        if case .setExtra(_, let completed) = activity.action { return "Extra \(completed ? "done" : "not done")" }
        if let words = goalChange(activity, context, spoken: true) { return words }
        return "Changed"
    }

    /// "Walk changed to Yoga · 30 min", "Water goal changed to 3,000 ml, 330 ml glass",
    /// "“Stretch” repeats every day".
    private static func goalChange(_ activity: Challenge.Activity, _ context: Context, spoken: Bool) -> String? {
        if case .setTarget(let slot, let name, let amount, let unit, let icon) = activity.action {
            let target = Challenge.Target(name: name, amount: amount, unit: unit, icon: icon)
            let before = context.previous[slot].name
            let amountText = spoken ? GoalWords.spokenAmount(target) : GoalWords.amount(target)
            if slot == .diet { return before == name ? "\(name) changed" : "\(before) renamed \(name)" }
            let to = [name, amountText].compactMap { $0 }.joined(separator: spoken ? ", " : " · ")
            return before == name && amountText == nil ? "\(name) changed to no set amount" : "\(before) changed to \(to)"
        }
        if case .setWater(let goal, let pour) = activity.action {
            return "Water goal changed to \(goal.formatted()) ml, \(pour.formatted()) ml glass"
        }
        if case .scheduleExtra(_, let weekdays, let every) = activity.action {
            let title = context.extraTitle.map { "“\($0)”" } ?? "Extra"
            guard let phrase = Challenge.ExtraSchedule(weekdays: weekdays, every: every).flatMap(GoalWords.repeatPhrase) else {
                return "\(title) no longer repeats"
            }
            return "\(title) repeats \(phrase)"
        }
        return nil
    }
}

/// Four habit pills (44 pt): pending, done (green + check), missed (red + ×), with the
/// selected day's icons and, for VoiceOver, its names and amounts.
struct PhoneHabitControls: View {
    @Bindable var tracker: TrackerModel

    var body: some View {
        HStack(spacing: 10) {
            habit(.workout)
            habit(.walk)
            diet
            habit(.bibleReading)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var closed: Bool { tracker.summary?.status == .missed }
    private var targets: Challenge.Targets { tracker.summary?.targets ?? .standard }

    private func habit(_ habit: Challenge.Habit) -> some View {
        let slot = GoalWords.slot(habit)
        let complete = tracker.summary?.completedHabits.contains(habit) ?? false
        return Button { tracker.toggle(habit) } label: {
            pill(GoalWords.symbol(slot, targets[slot]), state: complete ? .done : closed ? .missed : .pending)
        }
        .buttonStyle(.plain).disabled(!tracker.canEdit)
        .accessibilityLabel(GoalWords.spoken(slot, targets[slot]))
        .accessibilityValue(complete ? "Complete" : "Not complete")
        .accessibilityHint("Double-tap to \(complete ? "undo" : "mark complete")")
    }

    private var diet: some View {
        let state = tracker.summary?.diet ?? .pending
        return Button {
            tracker.setDiet(state == .pending ? .clean : state == .clean ? .missed : .pending)
        } label: {
            pill(GoalWords.symbol(.diet, targets.diet), state: state == .clean ? .done : state == .missed || closed ? .missed : .pending)
        }
        .buttonStyle(.plain).disabled(!tracker.canEdit)
        .accessibilityLabel(GoalWords.spoken(.diet, targets.diet)).accessibilityValue(state.rawValue)
        .accessibilityHint("Double-tap to cycle pending, clean and missed")
        .contextMenu { PhoneDietMenu(tracker: tracker) }
    }

    private enum PillState { case pending, done, missed }

    private func pill(_ symbol: String, state: PillState) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
            switch state {
            case .done: Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy))
            case .missed: Image(systemName: "xmark").font(.system(size: 13, weight: .heavy))
            case .pending: EmptyView()
            }
        }
        .foregroundStyle(state == .done ? Theme.doneText : state == .missed ? Theme.danger : Theme.textSecondary)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(Capsule(style: .circular).fill(state == .done ? Theme.doneTint : state == .missed ? Theme.dangerTint : Theme.controlFill))
        .overlay(Capsule(style: .circular).strokeBorder(state == .done ? Theme.done.opacity(0.55)
                                        : state == .missed ? Theme.dangerRing.opacity(0.6) : Theme.hairline, lineWidth: 1.5))
        .contentShape(Capsule(style: .circular))
    }
}
