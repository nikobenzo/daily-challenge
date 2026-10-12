import ChallengeCore
import ChallengeSyncKit
import SwiftUI

/// Today's Extras section under the rings. With extras it is the collapsible checklist
/// (header badge, chevron and the Manage extras pencil). With none it is one slim row,
/// "Extras · Add your own to-dos", that drops the add field down inline, so the first
/// extra can be added from the main screen rather than Account › Extras. The moment one
/// exists the editor cross-fades into the checklist while the glass height animates
/// (`AnimatedPopupStack`). Extras never count toward the five (`isComplete`).
struct ExtrasSection: View {
    @Bindable var model: TrackerModel
    @State var expanded: Bool
    @State private var newTitle = ""
    @State private var error: String?
    @State private var managing = false
    @FocusState private var focus: Bool?
    @Environment(\.trackerReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    /// The checklist starts open; the empty row starts collapsed.
    init(model: TrackerModel, expanded: Bool? = nil) {
        self.model = model
        _expanded = State(initialValue: expanded ?? (model.summary?.extrasTotal ?? 0 > 0))
    }

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    private var hasExtras: Bool { model.summary?.extrasTotal ?? 0 > 0 }

    var body: some View {
        let done = model.summary?.extrasDone ?? 0
        let total = model.summary?.extrasTotal ?? 0
        let hasExtras = hasExtras
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: toggle) {
                    HStack(spacing: 10) {
                        Image(systemName: "checklist").font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        Eyebrow(text: "Extras", font: .system(size: 12, weight: .bold))
                        if hasExtras {
                            Badge(symbol: done == total ? "checkmark" : nil, text: "\(done)/\(total)",
                                  fill: done == total ? Theme.doneTint : Theme.controlFill,
                                  foreground: done == total ? Theme.doneText : Theme.textPrimary, height: 22)
                                .transition(.opacity)
                        } else {
                            Text("Add your own to-dos").font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                                .transition(.opacity)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textSecondary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .frame(height: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hasExtras ? "Extras, \(done) of \(total) done" : "Add extras, your own to-dos")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                .accessibilityHint(hasExtras ? "Press to \(expanded ? "collapse" : "expand") the checklist"
                                   : "Press to \(expanded ? "hide" : "show") the add field")
                .help(hasExtras ? "Your own daily extras. They never count toward the five or your streak."
                      : "Add extras: your own to-dos. They never count toward the five or your streak.")
                if hasExtras {
                    Button { managing = true } label: { Image(systemName: "square.and.pencil") }
                        .buttonStyle(RoundIconStyle(size: 30))
                        .help("Manage extras")
                        .accessibilityLabel("Manage extras")
                        .popover(isPresented: $managing, arrowEdge: .bottom) { ManageExtrasView(model: model) }
                        .transition(.opacity)
                }
            }
            // The clip keeps the editor's drop-down under the header; 4 pt of room for the field's focus halo.
            VStack(spacing: 0) {
                if expanded {
                    ZStack(alignment: .top) {
                        if hasExtras {
                            ExtrasChecklist(model: model)
                                .padding(.bottom, 6)
                                .transition(.opacity)
                        } else {
                            editor.transition(.opacity)
                        }
                    }
                    .transition(reduceMotion || hasExtras ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .clipShape(Rectangle().inset(by: -4))
        }
        .animation(reduceMotion ? Theme.Motion.reducedResize : Theme.Motion.sectionResize, value: hasExtras)
        .onChange(of: hasExtras) { _, has in
            // Archiving the last extra returns the slim row, collapsed.
            if !has { withAnimation(reduceMotion ? Theme.Motion.reducedResize : Theme.Motion.sectionResize) { expanded = false } }
        }
        // Only the developer popup probe and the interface fixtures post this; it toggles exactly as a click does.
        .onReceive(NotificationCenter.default.publisher(for: PopupProbe.toggleExtrasRow)) { _ in toggle() }
    }

    /// Caption, the "New extra" field and its plus button, as in Manage extras.
    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ManageExtrasView.caption)
                .font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ExtrasAddRow(title: $newTitle, focus: $focus, equals: true, add: add)
            if let error { FieldError(text: error) }
        }
        .padding(.top, 2)
        .padding(.bottom, 12)
        .onAppear { focus = true }
    }

    private func toggle() {
        let opening = !expanded
        if hasExtras {
            withAnimation(reduceMotion ? nil : Theme.Motion.crossFade) { expanded.toggle() }
            return
        }
        withAnimation(reduceMotion ? Theme.Motion.reducedResize : Theme.Motion.sectionResize) { expanded.toggle() }
        if opening {
            AccessibilityNotification.Announcement("Add extras expanded. Type a name and press Return to add one.").post()
        } else {
            error = nil
        }
    }

    private func add() {
        guard Challenge.extraTitle(newTitle) != nil else { return }
        error = model.addExtra(newTitle)
        if error == nil { newTitle = "" }
    }
}

/// One checkbox row per extra shown on the selected day, with "Late" once it has
/// carried over. Ticks obey the same edit rules as habit marks: today, or a past day
/// after Edit this day.
struct ExtrasChecklist: View {
    @Bindable var model: TrackerModel

    var body: some View {
        let summary = model.summary
        VStack(spacing: 0) {
            ForEach(summary?.extras ?? []) { extra in
                let done = summary?.completedExtras.contains(extra.id) ?? false
                let late = summary?.isLate(extra) ?? false
                // A repeating extra is never late; its caption says how it repeats.
                let repeats = summary.flatMap { ExtraRepeat.rowCaption(extra.schedule(on: $0.interval.start)) }
                let spoken = late ? "\(extra.title), late" : repeats.map { "\(extra.title), \($0)" } ?? extra.title
                Button { model.toggleExtra(extra.id) } label: {
                    HStack(spacing: 12) {
                        ExtraCheckbox(done: done)
                        Text(extra.title).font(Theme.Fonts.field)
                            .foregroundStyle(done ? Theme.textSecondary : Theme.textPrimary)
                            .lineLimit(1).truncationMode(.tail)
                        if late { LateMarker() }
                        if let repeats {
                            Text(repeats).font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
                                .lineLimit(1).layoutPriority(-1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canEdit)
                .help(spoken)
                .accessibilityLabel(spoken)
                .accessibilityValue(done ? "Done" : "Not done")
                .accessibilityHint("Press to \(done ? "undo" : "mark done")")
            }
        }
    }
}

/// 22 pt round check: an empty ring, or a green disc with a check. Shape, not only colour.
struct ExtraCheckbox: View {
    let done: Bool

    var body: some View {
        ZStack {
            if done {
                Circle().fill(Theme.done)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.onDone)
            } else {
                Circle().strokeBorder(Theme.textTertiary, lineWidth: 1.5)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

/// History's day card: a fifth pill beside the habit pills with the day's extras count,
/// opening that day's checklist. Shown only when the day has extras.
struct ExtrasDayPill: View {
    @Bindable var model: TrackerModel
    @State private var showing = false

    var body: some View {
        let done = model.summary?.extrasDone ?? 0
        let total = model.summary?.extrasTotal ?? 0
        let all = total > 0 && done == total
        Button { showing = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "checklist").font(.system(size: 15, weight: .semibold))
                Text("\(done)/\(total)").font(Theme.Fonts.badge).monospacedDigit()
            }
            .foregroundStyle(all ? Theme.doneText : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Capsule(style: .circular).fill(all ? Theme.doneTint : Theme.controlFill))
            .overlay(Capsule(style: .circular).strokeBorder(all ? Theme.done.opacity(0.55) : Theme.hairline, lineWidth: 1.5))
            .contentShape(Capsule(style: .circular))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Extras, \(done) of \(total) done")
        .help("Extras: \(done) of \(total) done. They never count toward the five.")
        .popover(isPresented: $showing, arrowEdge: .bottom) { ExtrasDayPopover(model: model) }
    }
}

/// The History pill's popover: the selected day's checklist.
struct ExtrasDayPopover: View {
    @Bindable var model: TrackerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Extras · \(model.dates.label(model.selectedDay, format: "EEE d MMM"))", systemImage: "checklist")
                .font(Theme.Fonts.appName).foregroundStyle(Theme.textPrimary)
            ExtrasChecklist(model: model)
            if !model.canEdit {
                Text("Select Edit this day to correct these ticks.")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(16).frame(width: 300).trackerSurface().focusEffectDisabled()
    }
}

/// Account's settings row for extras, opening the same Manage extras popover as Today.
struct ExtrasSettingRow: View {
    let model: TrackerModel
    @State private var managing = false

    var body: some View {
        Button { managing = true } label: {
            SettingRow(symbol: "checklist", title: "Extras") {
                Badge(text: "\(model.activeExtras.count)/\(Challenge.maximumActiveExtras)", height: 24)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.challenge == nil)
        .accessibilityLabel("Manage extras, \(model.activeExtras.count) of \(Challenge.maximumActiveExtras)")
        .help("Manage extras: your own to-dos. They never count toward the five or your streak.")
        .popover(isPresented: $managing, arrowEdge: .trailing) { ManageExtrasView(model: model) }
    }
}

/// The "New extra" field and its plus button: Manage extras and Today's empty row share it.
struct ExtrasAddRow<Focus: Hashable>: View {
    @Binding var title: String
    let focus: FocusState<Focus?>.Binding
    let equals: Focus
    let add: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            GlassField(symbol: "plus", placeholder: "New extra", text: $title, focus: focus, equals: equals, onSubmit: add)
            Button(action: add) { Image(systemName: "plus") }
                .buttonStyle(RoundIconStyle(size: 36, fill: Theme.primaryTop, foreground: .white))
                .disabled(Challenge.extraTitle(title) == nil)
                .help("Add extra").accessibilityLabel("Add extra")
        }
    }
}

/// Add, edit (name and repeat) and archive, at most 10 active. No reordering, reminders,
/// notes or icons.
struct ManageExtrasView: View {
    static let caption = "Your own to-dos: once, carried over until done, or repeating on days you choose. "
        + "They never count toward the five or your streak."

    @Bindable var model: TrackerModel
    @State var newTitle = ""
    /// The extra whose name and repeat are being edited.
    @State var renaming: UUID?
    @State var renameTitle = ""
    @State var repeatChoice = RepeatChoice.once
    @State var repeatDays: Set<Int> = []
    @State var repeatEvery = 2
    @State var confirmingArchive: UUID?
    @State var error: String?
    @FocusState private var focus: Field?
    private enum Field: Hashable { case new, rename }

    /// The repeat picker's five choices (plan section 7.2).
    enum RepeatChoice: String, CaseIterable {
        case once = "Once", everyDay = "Every day", weekdays = "Weekdays", chooseDays = "Choose days", everyN = "Every N days"

        init(_ schedule: Challenge.ExtraSchedule) {
            switch schedule {
            case .once: self = .once
            case .every(1): self = .everyDay
            case .every: self = .everyN
            case .weekdays(let days): self = days == [1, 2, 3, 4, 5] ? .weekdays : .chooseDays
            }
        }
    }

    /// The rule the picker describes, or nil while "Choose days" has none chosen.
    var chosenSchedule: Challenge.ExtraSchedule? {
        switch repeatChoice {
        case .once: .once
        case .everyDay: .every(1)
        case .weekdays: .weekdays([1, 2, 3, 4, 5])
        case .chooseDays: repeatDays.isEmpty ? nil : .weekdays(repeatDays)
        case .everyN: .every(repeatEvery)
        }
    }

    var body: some View {
        let extras = model.activeExtras
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Extras", systemImage: "checklist").font(Theme.Fonts.appName).foregroundStyle(Theme.textPrimary)
                Spacer()
                Badge(text: "\(extras.count)/\(Challenge.maximumActiveExtras)", height: 24)
                    .accessibilityLabel("\(extras.count) of \(Challenge.maximumActiveExtras) extras")
            }
            Text(Self.caption)
                .font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !extras.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(extras.enumerated()), id: \.element.id) { index, extra in
                        if index > 0 { Theme.hairline.frame(height: 1).accessibilityHidden(true) }
                        row(extra)
                    }
                }
            }
            if model.canAddExtra {
                ExtrasAddRow(title: $newTitle, focus: $focus, equals: .new, add: add)
            } else {
                // Replaces the 46 pt add field; a whole-point height keeps the popover's edges crisp.
                Label("Up to \(Challenge.maximumActiveExtras) extras. Archive one to add another.", systemImage: "info.circle")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.amberText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            }
            if let error { FieldError(text: error) }
        }
        .padding(16).frame(width: 320).trackerSurface().focusEffectDisabled()
        .onAppear { if extras.isEmpty { focus = .new } }
    }

    @ViewBuilder
    private func row(_ extra: Challenge.Extra) -> some View {
        if renaming == extra.id {
            editor(extra)
        } else if confirmingArchive == extra.id {
            VStack(alignment: .leading, spacing: 8) {
                Text("Archive “\(extra.title)”? It disappears from today on and can't be restored. Earlier days keep their ticks.")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancel") { confirmingArchive = nil }.buttonStyle(TintedPillStyle(height: 32))
                    Spacer()
                    Button("Archive") { archive(extra) }
                        .buttonStyle(TintedPillStyle(height: 32, fill: Theme.dangerTint, foreground: Theme.danger))
                }
            }
            .padding(.vertical, 8)
        } else {
            let caption = ExtraRepeat.caption(extra.schedule)
            HStack(spacing: 8) {
                Text(extra.title).font(Theme.Fonts.field).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).truncationMode(.tail).help(extra.title)
                Spacer(minLength: 4)
                Text(caption).font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).layoutPriority(-1)
                Button { edit(extra) } label: { Image(systemName: "pencil") }
                    .buttonStyle(RoundIconStyle(size: 30))
                    .help("Edit name and repeat").accessibilityLabel("Edit \(extra.title), \(caption)")
                Button { error = nil; renaming = nil; confirmingArchive = extra.id } label: { Image(systemName: "archivebox") }
                    .buttonStyle(RoundIconStyle(size: 30))
                    .help("Archive").accessibilityLabel("Archive \(extra.title)")
            }
            .frame(minHeight: 40)
        }
    }

    private func add() {
        guard Challenge.extraTitle(newTitle) != nil else { return }
        error = model.addExtra(newTitle)
        if error == nil { newTitle = "" }
    }

    /// Name, the repeat chips, then the weekday toggles or the N stepper when they apply.
    private func editor(_ extra: Challenge.Extra) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassField(symbol: "pencil", placeholder: "Name", text: $renameTitle,
                       focus: $focus, equals: .rename, onSubmit: { saveRename(extra) })
            Text("Repeat").font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                .accessibilityAddTraits(.isHeader)
            ChipFlow(spacing: 6) {
                ForEach(RepeatChoice.allCases, id: \.self) { choice in
                    GoalChip(title: choice.rawValue, selected: repeatChoice == choice) {
                        repeatChoice = choice
                        error = nil
                        if choice == .chooseDays, repeatDays.isEmpty { repeatDays = [Self.weekday(model.today, model.dates.calendar)] }
                    }
                }
            }
            switch repeatChoice {
            case .chooseDays:
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { day in
                        let on = repeatDays.contains(day)
                        Button { if on { repeatDays.remove(day) } else { repeatDays.insert(day) } } label: {
                            Text(ExtraRepeat.weekdayInitials[day - 1]).font(Theme.Fonts.badge)
                        }
                        .buttonStyle(RoundIconStyle(size: 32, fill: on ? Theme.accentTint : Theme.controlFill,
                                                    foreground: on ? Theme.accentText : Theme.textPrimary,
                                                    border: on ? Theme.accentText.opacity(0.6) : .clear))
                        .help(ExtraRepeat.weekdayNames[day - 1])
                        .accessibilityLabel(ExtraRepeat.weekdayNames[day - 1])
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                if repeatDays.isEmpty { FieldError(text: "Choose at least one day.") }
            case .everyN:
                HStack {
                    Text("Every").font(Theme.Fonts.field).foregroundStyle(Theme.textPrimary)
                    PillStepper(text: "\(repeatEvery) days", accessibilityText: "Repeat every",
                                decrement: repeatEvery > 2 ? { repeatEvery -= 1 } : nil,
                                increment: repeatEvery < Challenge.ExtraSchedule.intervals.upperBound ? { repeatEvery += 1 } : nil)
                }
                Text("2 to \(Challenge.ExtraSchedule.intervals.upperBound) days, counted from today.")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
            default: EmptyView()
            }
            Text(repeatChoice == .once
                 ? "A to-do carries over, marked Late, until it's done."
                 : "Repeats from today. It comes back on its days, is never late and doesn't carry over.")
                .font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel") { renaming = nil; error = nil }.buttonStyle(TintedPillStyle(height: 32))
                Spacer()
                Button("Save") { saveRename(extra) }
                    .buttonStyle(PrimaryPillStyle(height: 32, expands: false))
                    .disabled(Challenge.extraTitle(renameTitle) == nil || chosenSchedule == nil)
            }
        }
        .padding(.vertical, 8)
    }

    private func edit(_ extra: Challenge.Extra) {
        error = nil; confirmingArchive = nil
        renameTitle = extra.title
        repeatChoice = RepeatChoice(extra.schedule)
        if case .weekdays(let days) = extra.schedule { repeatDays = days } else { repeatDays = [] }
        if case .every(let days) = extra.schedule, days > 1 { repeatEvery = days } else { repeatEvery = 2 }
        renaming = extra.id
        focus = .rename
    }

    /// The ISO weekday (Monday = 1) of `day`.
    static func weekday(_ day: Date, _ calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: day) + 5) % 7 + 1
    }

    private func saveRename(_ extra: Challenge.Extra) {
        guard let schedule = chosenSchedule else { return }
        error = model.renameExtra(extra.id, to: renameTitle)
        if error == nil, schedule != extra.schedule(on: model.today) { error = model.scheduleExtra(extra.id, schedule) }
        if error == nil { renaming = nil }
    }

    private func archive(_ extra: Challenge.Extra) {
        error = model.archiveExtra(extra.id)
        confirmingArchive = nil
    }
}
