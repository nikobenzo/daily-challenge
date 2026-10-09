import ChallengeCore
import SwiftUI

/// History: month calendar, the selected day's card, and its Activity. Fixed to the
/// shared History/Account height; the Activity list takes the rest and scrolls.
struct HistoryTrackerView: View {
    @Bindable var model: TrackerModel
    @State private var month = Date()
    @State private var showingAudit = true

    var body: some View {
        VStack(spacing: 0) {
            calendar
                .padding(.horizontal, Theme.Size.sectionHorizontal)
                .padding(.vertical, 14)
            HairlineDivider()
            dayCard
                .padding(.horizontal, Theme.Size.sectionHorizontal)
                .padding(.vertical, Theme.Size.sectionVertical)
            HairlineDivider()
            activity
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: Theme.Size.wideSectionHeight, alignment: .top)
        .onAppear { month = monthStart(model.selectedDay) }
        .onChange(of: model.selectedDay) { _, _ in showingAudit = true }
    }

    // MARK: Calendar

    private var calendar: some View {
        VStack(spacing: 10) {
            HStack {
                Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(RoundIconStyle(size: 32))
                    .disabled(month <= monthStart(model.challenge?.startDate ?? model.today))
                    .accessibilityLabel("Previous month").help("Previous month")
                Spacer()
                Text(model.dates.label(month, format: "MMMM yyyy")).font(Theme.Fonts.appName)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(RoundIconStyle(size: 32))
                    .disabled(month >= monthStart(model.today))
                    .accessibilityLabel("Next month").help("Next month")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, label in
                    Text(label).font(Theme.Fonts.ringLabel).foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: Theme.Size.calendarDay) }
                ForEach(daysInMonth, id: \.self) { day in dayCell(day) }
            }
        }
    }

    private var leadingBlanks: Int {
        (model.dates.calendar.component(.weekday, from: month) - model.dates.calendar.firstWeekday + 7) % 7
    }

    private var daysInMonth: [Date] {
        guard let range = model.dates.calendar.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { model.dates.calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    /// Six states, each distinct by shape: complete (green disc), missed (red ring),
    /// today (blue ring + halo), selected (ink disc), future/outside (faint numeral).
    private func dayCell(_ day: Date) -> some View {
        let state = model.challenge?.summary(on: day, asOf: model.now).status ?? .outsideChallenge
        let selected = model.dates.calendar.isDate(day, inSameDayAs: model.selectedDay)
        let isToday = model.dates.calendar.isDate(day, inSameDayAs: model.today)
        let allowed = state != .outsideChallenge && state != .future
        let number = Text("\(model.dates.calendar.component(.day, from: day))")
            .font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
        let size = Theme.Size.calendarDay
        return Button { model.selectHistoryDay(day) } label: {
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
        }.buttonStyle(.plain).disabled(!allowed)
            .accessibilityLabel("\(model.dates.label(day, format: "d MMMM yyyy")), \(name(state))")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .help(name(state))
    }

    // MARK: Day card

    private var dayCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text(model.dates.label(model.selectedDay, format: "EEE d MMM"))
                    .font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.textPrimary)
                statusBadge
                Spacer()
                editChip
            }
            WaterControls(model: model, compact: true)
            HabitControls(model: model)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if model.dates.calendar.isDate(model.selectedDay, inSameDayAs: model.today) {
            Badge(text: "Today", fill: Theme.accentTint, foreground: Theme.accentText, height: 28)
                .accessibilityLabel("Today, \(statusName)")
        } else {
            let status = model.summary?.status ?? .outsideChallenge
            Badge(symbol: icon(status), text: statusName,
                  fill: status == .complete ? Theme.doneTint : status == .missed ? Theme.dangerTint : Theme.controlFill,
                  foreground: status == .complete ? Theme.doneText : status == .missed ? Theme.danger : Theme.textSecondary,
                  height: 28)
        }
    }

    /// Icon-only: an amber pencil while the day is editable, otherwise the button
    /// that unlocks corrections for a past day.
    @ViewBuilder
    private var editChip: some View {
        if model.canEdit {
            Image(systemName: "pencil").font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.amberText)
                .frame(width: Theme.Size.iconChip, height: Theme.Size.iconChip)
                .background(Circle().fill(Theme.amberTint))
                .overlay(Circle().strokeBorder(Theme.amber.opacity(0.7), lineWidth: 1.5))
                .help(model.isEditingHistory
                      ? "Editing this day. Corrections are saved immediately to this day. Streaks and milestones recalculate."
                      : "Editing today. Changes save immediately.")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.isEditingHistory ? "Editing this day" : "Editing today")
        } else if let status = model.summary?.status, status != .future, status != .outsideChallenge {
            Button { model.enableCorrections() } label: { Image(systemName: "pencil") }
                .buttonStyle(RoundIconStyle(size: Theme.Size.iconChip))
                .help("Edit this day")
                .accessibilityLabel("Edit this day")
        }
    }

    // MARK: Activity

    private var activity: some View {
        VStack(spacing: 0) {
            Button { showingAudit.toggle() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    Eyebrow(text: "Activity", font: .system(size: 12, weight: .bold))
                    Badge(text: "\(model.history.count)", height: 22)
                    Spacer()
                    Image(systemName: showingAudit ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textSecondary)
                }
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Size.sectionHorizontal)
            .accessibilityLabel("Activity and corrections, \(model.history.count)")
            .accessibilityValue(showingAudit ? "Expanded" : "Collapsed")
            .help("Activity and corrections for this day, newest first")
            if showingAudit {
                if model.history.isEmpty {
                    Text("No activity recorded. Closed unrecorded days are missed.")
                        .font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Size.sectionHorizontal)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.history) { activity in row(activity) }
                        }
                        .padding(.horizontal, Theme.Size.sectionHorizontal)
                        .padding(.bottom, 8)
                    }
                    .scrollIndicators(.automatic)
                }
            }
        }
        .padding(.top, 6)
    }

    private func row(_ activity: Challenge.Activity) -> some View {
        let (symbol, tint) = rowIcon(activity)
        return HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(shortDescription(activity)).font(Theme.Fonts.rowLabel.weight(.medium)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(model.dates.label(activity.recordedAt, format: "HH:mm")).font(Theme.Fonts.caption).monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(height: 34)
        .help("\(description(activity)) · Edited \(model.dates.label(activity.recordedAt, format: "d MMM, HH:mm")) · \(ChallengeDates.city(model.dates.timeZone))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(description(activity)), edited \(model.dates.label(activity.recordedAt, format: "d MMM, HH:mm"))")
    }

    private func rowIcon(_ activity: Challenge.Activity) -> (String, Color) {
        switch activity.action {
        case .pour: ("drop.fill", Theme.water)
        case .undoLatestPour: ("arrow.uturn.backward", Theme.textSecondary)
        case .setDiet(let value): ("leaf", value == .clean ? Theme.done : value == .missed ? Theme.danger : Theme.textTertiary)
        case .setHabit(let habit, let completed): (Self.symbol(habit), completed ? Theme.done : Theme.textTertiary)
        }
    }

    static func symbol(_ habit: Challenge.Habit) -> String {
        switch habit {
        case .workout: "dumbbell"
        case .walk: "figure.walk"
        case .bibleReading: "book"
        }
    }

    private var statusName: String { name(model.summary?.status ?? .outsideChallenge) }
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
        model.dates.calendar.dateInterval(of: .month, for: date)!.start
    }
    private func changeMonth(_ offset: Int) {
        month = model.dates.calendar.date(byAdding: .month, value: offset, to: month)!
    }
    private func shortDescription(_ activity: Challenge.Activity) -> String {
        switch activity.action {
        case .pour(let amount): "+\(amount.formatted()) ml"
        case .undoLatestPour: "Undid pour"
        case .setDiet(let value): "Diet \(value.rawValue)"
        case .setHabit(let habit, let completed):
            "\(habit == .bibleReading ? "Bible reading" : habit.rawValue.capitalized) \(completed ? "complete" : "not complete")"
        }
    }
    private func description(_ activity: Challenge.Activity) -> String {
        switch activity.action {
        case .pour(let amount): "Added \(amount.formatted()) ml"
        case .undoLatestPour: "Undid pour \(activity.undonePourID.map { String($0.uuidString.prefix(8)) } ?? "")"
        case .setDiet(let value): "Diet → \(value.rawValue)"
        case .setHabit(let habit, let completed):
            "\(habit == .bibleReading ? "Bible reading" : habit.rawValue.capitalized) → \(completed ? "complete" : "not complete")"
        }
    }
}

/// Four icon-only habit pills (44 pt): pending, done (green + check), missed (red + ×).
struct HabitControls: View {
    @Bindable var model: TrackerModel

    var body: some View {
        HStack(spacing: 10) {
            habit(.workout, title: "Workout", detail: "45 min · home / gym")
            habit(.walk, title: "Walk", detail: "45 minutes")
            diet
            habit(.bibleReading, title: "Bible", detail: "10 pages")
        }
    }

    private var closed: Bool { model.summary?.status == .missed }

    private func habit(_ habit: Challenge.Habit, title: String, detail: String) -> some View {
        let complete = model.summary?.completedHabits.contains(habit) ?? false
        return Button { model.toggle(habit) } label: {
            pill(HistoryTrackerView.symbol(habit), state: complete ? .done : closed ? .missed : .pending)
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
            pill("leaf", state: state == .clean ? .done : state == .missed || closed ? .missed : .pending)
        }.buttonStyle(.plain).disabled(!model.canEdit)
            .accessibilityLabel("Clean diet, your own rules").accessibilityValue(state.rawValue)
            .accessibilityHint("Press to cycle pending, clean and missed")
            .help("Diet: \(state.rawValue.capitalized). Click to cycle pending → clean → missed. Right-click to choose.")
            .contextMenu { DietMenu(model: model) }
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
