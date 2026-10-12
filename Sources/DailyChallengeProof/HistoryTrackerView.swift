import ChallengeCore
import ChallengeSyncKit
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
        case .setHabit(let habit, let completed): (Goals.symbol(habit, in: targets), completed ? Theme.done : Theme.textTertiary)
        case .defineExtra: ("checklist", Theme.textSecondary)
        case .archiveExtra: ("archivebox", Theme.textTertiary)
        case .setExtra(_, let completed): ("checklist.checked", completed ? Theme.done : Theme.textTertiary)
        case .setTarget(let slot, let name, let amount, let unit, let icon):
            (Goals.symbol(slot, Challenge.Target(name: name, amount: amount, unit: unit, icon: icon)), Theme.textSecondary)
        case .setWater: ("drop", Theme.water)
        case .scheduleExtra: ("repeat", Theme.textSecondary)
        }
    }

    /// The extra's current name; renames show under the name they were given.
    private func extraTitle(_ id: UUID) -> String {
        "“\(model.challenge?.allExtras.first { $0.id == id }?.title ?? "Extra")”"
    }

    /// True when this definition is the extra's first, so it added rather than renamed it.
    private func addsExtra(_ activity: Challenge.Activity, id: UUID) -> Bool {
        model.challenge?.allActivities.first { event in
            if case .defineExtra(let extraID, _) = event.action { extraID == id } else { false }
        }?.id == activity.id
    }

    /// The selected day's targets: the names a tick on that day was made under.
    private var targets: Challenge.Targets { model.summary?.targets ?? .standard }

    private func habitName(_ habit: Challenge.Habit) -> String { targets[Goals.slot(habit)].name }

    /// The slot's target just before this change: the day before's, or an earlier change
    /// that day (the same latest-day-then-event-order rule as `targets(on:)`).
    private func previous(_ activity: Challenge.Activity) -> (target: Challenge.Target?, water: Challenge.WaterTarget?) {
        var slotTarget: Challenge.Target?, water: Challenge.WaterTarget?
        var slotDay: Date?, waterDay: Date?
        guard let events = model.challenge?.allActivities, let index = events.firstIndex(of: activity) else { return (nil, nil) }
        for (offset, event) in events.enumerated() where offset != index
            && (event.day < activity.day || (event.day == activity.day && offset < index)) {
            switch (event.action, activity.action) {
            case (.setTarget(let slot, let name, let amount, let unit, let icon), .setTarget(let changed, _, _, _, _)) where slot == changed:
                guard slotDay.map({ $0 <= event.day }) ?? true else { continue }
                slotDay = event.day
                slotTarget = Challenge.Target(name: name, amount: amount, unit: unit, icon: icon)
            case (.setWater(let goal, let pour), .setWater):
                guard waterDay.map({ $0 <= event.day }) ?? true else { continue }
                waterDay = event.day
                water = Challenge.WaterTarget(goal: goal, glass: pour)
            default: break
            }
        }
        return (slotTarget, water)
    }

    /// "Walk changed to Yoga · 30 min", "Water goal changed to 3,000 ml, 330 ml glass";
    /// `short` fits a row: "Water now 3,000 ml · 330 ml glass".
    private func targetChange(_ activity: Challenge.Activity, short: Bool = false) -> String {
        switch activity.action {
        case .setTarget(let slot, let name, let amount, let unit, let icon):
            let new = Challenge.Target(name: name, amount: amount, unit: unit, icon: icon)
            let old = previous(activity).target ?? Challenge.Targets.standard[slot]
            if old.name == new.name { return "\(name) changed to \(Goals.amount(new) ?? "no set amount")" }
            return "\(old.name) changed to \(Goals.summary(slot, new))"
        case .setWater(let goal, let pour):
            let old = previous(activity).water ?? Challenge.Targets.standard.water
            if old.goal == goal { return "Glass changed to \(pour.formatted()) ml" }
            if old.glass == pour { return "Water goal changed to \(goal.formatted()) ml" }
            return short ? "Water now \(goal.formatted()) ml · \(pour.formatted()) ml glass"
                : "Water goal changed to \(goal.formatted()) ml, \(pour.formatted()) ml glass"
        default: return ""
        }
    }

    /// "“Stretch” repeats every day", "“Book dentist” is a to-do again".
    private func repeatChange(_ id: UUID, weekdays: [Int]?, every: Int?) -> String {
        let schedule = Challenge.ExtraSchedule(weekdays: weekdays, every: every) ?? .once
        return schedule == .once ? "\(extraTitle(id)) is a to-do again" : "\(extraTitle(id)) repeats \(ExtraRepeat.phrase(schedule))"
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
    /// An Activity row's words, as shown (the tests read them through this).
    static func auditText(_ model: TrackerModel, _ activity: Challenge.Activity) -> String {
        HistoryTrackerView(model: model).shortDescription(activity)
    }

    /// Its tooltip and VoiceOver words.
    static func auditDescription(_ model: TrackerModel, _ activity: Challenge.Activity) -> String {
        HistoryTrackerView(model: model).description(activity)
    }

    private func shortDescription(_ activity: Challenge.Activity) -> String {
        switch activity.action {
        case .pour(let amount): "+\(amount.formatted()) ml"
        case .undoLatestPour: "Undid pour"
        case .setDiet(let value): "Diet \(value.rawValue)"
        case .setHabit(let habit, let completed): "\(habitName(habit)) \(completed ? "complete" : "not complete")"
        case .defineExtra(let id, let title): addsExtra(activity, id: id) ? "Added “\(title)”" : "Renamed “\(title)”"
        case .archiveExtra(let id): "Archived \(extraTitle(id))"
        case .setExtra(let id, let completed): "\(extraTitle(id)) \(completed ? "done" : "not done")"
        case .setTarget, .setWater: targetChange(activity, short: true)
        case .scheduleExtra(let id, let weekdays, let every): repeatChange(id, weekdays: weekdays, every: every)
        }
    }
    private func description(_ activity: Challenge.Activity) -> String {
        switch activity.action {
        case .pour(let amount): "Added \(amount.formatted()) ml"
        case .undoLatestPour: "Undid pour \(activity.undonePourID.map { String($0.uuidString.prefix(8)) } ?? "")"
        case .setDiet(let value): "Diet → \(value.rawValue)"
        case .setHabit(let habit, let completed): "\(habitName(habit)) → \(completed ? "complete" : "not complete")"
        case .defineExtra(let id, let title): addsExtra(activity, id: id) ? "Added extra “\(title)”" : "Renamed extra to “\(title)”"
        case .archiveExtra(let id): "Archived extra \(extraTitle(id))"
        case .setExtra(let id, let completed): "Extra \(extraTitle(id)) → \(completed ? "done" : "not done")"
        case .setTarget, .setWater: "Daily goal: \(targetChange(activity)), from this day on"
        case .scheduleExtra(let id, let weekdays, let every): "Extra \(repeatChange(id, weekdays: weekdays, every: every)), from this day on"
        }
    }
}

/// Four icon-only habit pills (44 pt) with the selected day's icons: pending, done (green
/// + check), missed (red + ×).
struct HabitControls: View {
    @Bindable var model: TrackerModel

    var body: some View {
        let targets = model.summary?.targets ?? .standard
        HStack(spacing: 10) {
            habit(.workout, targets)
            habit(.walk, targets)
            diet(targets.diet)
            habit(.bibleReading, targets)
            if model.summary?.extrasTotal ?? 0 > 0 { ExtrasDayPill(model: model) }
        }
    }

    private var closed: Bool { model.summary?.status == .missed }

    private func habit(_ habit: Challenge.Habit, _ targets: Challenge.Targets) -> some View {
        let slot = Goals.slot(habit), target = targets[slot]
        let complete = model.summary?.completedHabits.contains(habit) ?? false
        return Button { model.toggle(habit) } label: {
            pill(Goals.symbol(slot, target), state: complete ? .done : closed ? .missed : .pending)
        }.buttonStyle(.plain).disabled(!model.canEdit)
            .accessibilityLabel(Goals.spoken(slot, target))
            .accessibilityValue(complete ? "Complete" : "Not complete")
            .accessibilityHint("Press to \(complete ? "undo" : "mark complete")")
            .help("\(target.name): \(Goals.detail(slot, target)). Click to \(complete ? "undo" : "complete").")
    }

    private func diet(_ target: Challenge.Target) -> some View {
        let state = model.summary?.diet ?? .pending
        return Button {
            model.setDiet(state == .pending ? .clean : state == .clean ? .missed : .pending)
        } label: {
            pill("leaf", state: state == .clean ? .done : state == .missed || closed ? .missed : .pending)
        }.buttonStyle(.plain).disabled(!model.canEdit)
            .accessibilityLabel(Goals.dietLabel(target)).accessibilityValue(state.rawValue)
            .accessibilityHint("Press to cycle pending, clean and missed")
            .help("\(target.name): \(state.rawValue.capitalized). Click to cycle pending → clean → missed. Right-click to choose.")
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
