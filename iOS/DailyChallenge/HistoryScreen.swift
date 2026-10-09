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
                ForEach(tracker.history) { activity in row(activity) }
            }
        }
        .padding(.horizontal, Theme.Size.sectionHorizontal)
        .padding(.vertical, Theme.Space.xs)
    }

    private func row(_ activity: Challenge.Activity) -> some View {
        let (symbol, tint) = ActivityWords.icon(activity)
        return HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(ActivityWords.short(activity)).font(Theme.Fonts.field).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(tracker.dates.label(activity.recordedAt, format: "HH:mm")).font(Theme.Fonts.caption).monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ActivityWords.long(activity)), edited \(tracker.dates.label(activity.recordedAt, format: "d MMM, HH:mm"))")
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
/// action kinds read as a generic change instead of breaking this screen.
enum ActivityWords {
    static func habitName(_ habit: Challenge.Habit) -> String {
        habit == .bibleReading ? "Bible reading" : habit.rawValue.capitalized
    }

    static func symbol(_ habit: Challenge.Habit) -> String {
        switch habit {
        case .workout: "dumbbell"
        case .walk: "figure.walk"
        case .bibleReading: "book"
        }
    }

    static func icon(_ activity: Challenge.Activity) -> (String, Color) {
        if case .pour = activity.action { return ("drop.fill", Theme.water) }
        if case .undoLatestPour = activity.action { return ("arrow.uturn.backward", Theme.textSecondary) }
        if case .setDiet(let value) = activity.action {
            return ("leaf", value == .clean ? Theme.done : value == .missed ? Theme.danger : Theme.textTertiary)
        }
        if case .setHabit(let habit, let completed) = activity.action {
            return (symbol(habit), completed ? Theme.done : Theme.textTertiary)
        }
        return ("square.and.pencil", Theme.textSecondary)
    }

    static func short(_ activity: Challenge.Activity) -> String {
        if case .pour(let amount) = activity.action { return "+\(amount.formatted()) ml" }
        if case .undoLatestPour = activity.action { return "Undid pour" }
        if case .setDiet(let value) = activity.action { return "Diet \(value.rawValue)" }
        if case .setHabit(let habit, let completed) = activity.action {
            return "\(habitName(habit)) \(completed ? "complete" : "not complete")"
        }
        return "Changed"
    }

    static func long(_ activity: Challenge.Activity) -> String {
        if case .pour(let amount) = activity.action { return "Added \(amount.formatted()) ml" }
        if case .undoLatestPour = activity.action { return "Undid a water pour" }
        if case .setDiet(let value) = activity.action { return "Diet set to \(value.rawValue)" }
        if case .setHabit(let habit, let completed) = activity.action {
            return "\(habitName(habit)) set to \(completed ? "complete" : "not complete")"
        }
        return "Changed"
    }
}

/// Four habit pills (44 pt): pending, done (green + check), missed (red + ×).
struct PhoneHabitControls: View {
    @Bindable var tracker: TrackerModel

    var body: some View {
        HStack(spacing: 10) {
            habit(.workout, title: "Workout", detail: "45 min · home / gym")
            habit(.walk, title: "Walk", detail: "45 minutes")
            diet
            habit(.bibleReading, title: "Bible", detail: "10 pages")
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var closed: Bool { tracker.summary?.status == .missed }

    private func habit(_ habit: Challenge.Habit, title: String, detail: String) -> some View {
        let complete = tracker.summary?.completedHabits.contains(habit) ?? false
        return Button { tracker.toggle(habit) } label: {
            pill(ActivityWords.symbol(habit), state: complete ? .done : closed ? .missed : .pending)
        }
        .buttonStyle(.plain).disabled(!tracker.canEdit)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityValue(complete ? "Complete" : "Not complete")
        .accessibilityHint("Double-tap to \(complete ? "undo" : "mark complete")")
    }

    private var diet: some View {
        let state = tracker.summary?.diet ?? .pending
        return Button {
            tracker.setDiet(state == .pending ? .clean : state == .clean ? .missed : .pending)
        } label: {
            pill("leaf", state: state == .clean ? .done : state == .missed || closed ? .missed : .pending)
        }
        .buttonStyle(.plain).disabled(!tracker.canEdit)
        .accessibilityLabel("Clean diet, your own rules").accessibilityValue(state.rawValue)
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
