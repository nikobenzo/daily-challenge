import ChallengeCore
import ChallengeSyncKit
import SwiftUI

/// The five daily goals as tappable rows (water, two activities, diet, reading), each
/// opening its editor in a popover anchored to the row. Setup edits its own draft before
/// the start; Account › Daily goals saves each editor's Done from today on.
struct GoalRows: View {
    let targets: Challenge.Targets
    /// Saves a change; nil when saved, otherwise why not (the editor stays open).
    let save: (Challenge.Targets) -> String?
    var disabled = false

    enum Row: Hashable, CaseIterable { case water, workout, walk, diet, bibleReading }
    @State private var editing: Row?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(Row.allCases.enumerated()), id: \.element) { index, row in
                if index > 0 { Theme.hairline.frame(height: 1).padding(.leading, 36).accessibilityHidden(true) }
                button(row)
            }
        }
    }

    private func button(_ row: Row) -> some View {
        Button { editing = row } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol(row)).font(.system(size: 17, weight: .medium))
                    .foregroundStyle(row == .water ? Theme.water : Theme.textPrimary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(name(row)).font(Theme.Fonts.rowLabel).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 8)
                Text(detail(row)).font(Theme.Fonts.field).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
            }
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help("\(name(row)): \(detail(row)). Click to change.")
        .accessibilityLabel("\(Self.role(row)): \(name(row)), \(spokenDetail(row))")
        .accessibilityHint("Opens the editor")
        .popover(isPresented: Binding(get: { editing == row }, set: { if !$0 { editing = nil } }), arrowEdge: .trailing) {
            editor(row)
        }
    }

    @ViewBuilder
    private func editor(_ row: Row) -> some View {
        switch row {
        case .water:
            WaterGoalEditor(initial: targets.water, close: { editing = nil }) { water in
                var next = targets
                next.water = water
                return save(next)
            }
        default:
            let slot = Self.slot(row)!
            TargetEditor(slot: slot, initial: targets[slot], close: { editing = nil }) { target in
                var next = targets
                next[slot] = target
                return save(next)
            }
        }
    }

    static func slot(_ row: Row) -> Challenge.TargetSlot? {
        switch row {
        case .water: nil
        case .workout: .workout
        case .walk: .walk
        case .diet: .diet
        case .bibleReading: .bibleReading
        }
    }

    static func role(_ row: Row) -> String { slot(row).map(Goals.role) ?? "Water" }

    private func symbol(_ row: Row) -> String {
        guard let slot = Self.slot(row) else { return "drop.fill" }
        return Goals.symbol(slot, targets[slot])
    }

    private func name(_ row: Row) -> String { Self.slot(row).map { targets[$0].name } ?? "Water" }

    private func detail(_ row: Row) -> String {
        guard let slot = Self.slot(row) else { return Goals.water(targets.water) }
        return Goals.detail(slot, targets[slot])
    }

    private func spokenDetail(_ row: Row) -> String {
        guard let slot = Self.slot(row) else {
            return "\(targets.water.goal) millilitres a day, \(targets.water.glass) millilitre glass"
        }
        return Goals.detail(slot, targets[slot], spoken: true)
    }
}

// MARK: Editors

/// Daily goal (1,000 to 5,000 ml in steps of 250) and the glass the + button pours.
struct WaterGoalEditor: View {
    let close: () -> Void
    let save: (Challenge.WaterTarget) -> String?
    @State var goal: Int
    @State var glass: Int
    @State var other: Bool
    @State var otherText: String
    @State var error: String?
    @FocusState private var focus: Bool?

    init(initial: Challenge.WaterTarget, close: @escaping () -> Void, save: @escaping (Challenge.WaterTarget) -> String?) {
        self.close = close
        self.save = save
        _goal = State(initialValue: initial.goal)
        _glass = State(initialValue: initial.glass)
        _other = State(initialValue: !Goals.glasses.contains(initial.glass))
        _otherText = State(initialValue: Goals.glasses.contains(initial.glass) ? "" : String(initial.glass))
    }

    private var chosenGlass: Int? { other ? Int(otherText.trimmingCharacters(in: .whitespaces)) : glass }
    private var problem: String? {
        guard let chosenGlass else { return "Enter the glass size in whole ml, such as 400." }
        return Goals.waterProblem(Challenge.WaterTarget(goal: goal, glass: chosenGlass))
    }

    var body: some View {
        let goals = Challenge.WaterTarget.goals
        VStack(alignment: .leading, spacing: 12) {
            EditorHeader(title: "Water", symbol: "drop.fill")
            HStack {
                Text("Daily goal").font(Theme.Fonts.rowLabel).foregroundStyle(Theme.textPrimary)
                Spacer()
                PillStepper(text: "\(goal.formatted()) ml", accessibilityText: "Daily water goal",
                            decrement: goal > goals.lowerBound ? { goal = max(goals.lowerBound, goal - 250) } : nil,
                            increment: goal < goals.upperBound ? { goal = min(goals.upperBound, goal + 250) } : nil)
            }
            Text("\(goals.lowerBound.formatted()) to \(goals.upperBound.formatted()) ml").font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
            Text("Your glass or bottle").font(Theme.Fonts.rowLabel).foregroundStyle(Theme.textPrimary)
                .padding(.top, 4)
            ChipFlow(spacing: 6) {
                ForEach(Goals.glasses, id: \.self) { size in
                    GoalChip(title: "\(size)", selected: !other && glass == size) { other = false; glass = size; error = nil }
                        .accessibilityLabel("\(size) millilitres")
                }
                GoalChip(title: "Other…", selected: other) { other = true; focus = true; error = nil }
                    .accessibilityLabel("Other glass size")
            }
            if other {
                GlassField(symbol: "drop", placeholder: "Glass size in ml", text: $otherText, focus: $focus, equals: true,
                           onSubmit: done)
            }
            if let size = chosenGlass, problem == nil {
                Text("The + button adds \(size.formatted()) ml. About \(glasses(size)) a day.")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = error ?? (other && otherText.isEmpty ? nil : problem) { FieldError(text: message) }
            EditorButtons(cancel: close, done: done, canSave: problem == nil)
        }
        .padding(16).frame(width: 320).trackerSurface().focusEffectDisabled()
    }

    private func glasses(_ size: Int) -> String {
        let count = Int((Double(goal) / Double(size)).rounded(.up))
        return count == 1 ? "1 glass" : "\(count) glasses"
    }

    private func done() {
        guard problem == nil, let chosenGlass else { error = problem; return }
        error = save(Challenge.WaterTarget(goal: goal, glass: chosenGlass))
        if error == nil { close() }
    }
}

/// An activity or reading slot (presets, name, optional amount and unit, icon), or diet
/// (presets and name only).
struct TargetEditor: View {
    let slot: Challenge.TargetSlot
    let close: () -> Void
    let save: (Challenge.Target) -> String?
    @State var name: String
    @State var icon: String?
    @State var hasAmount: Bool
    @State var amountText: String
    @State var unit: Challenge.TargetUnit
    @State var custom: Bool
    @State var error: String?
    @FocusState private var focus: Field?
    private enum Field: Hashable { case name, amount }

    init(slot: Challenge.TargetSlot, initial: Challenge.Target, close: @escaping () -> Void,
         save: @escaping (Challenge.Target) -> String?) {
        self.slot = slot
        self.close = close
        self.save = save
        _name = State(initialValue: initial.name)
        _icon = State(initialValue: initial.icon)
        _hasAmount = State(initialValue: initial.amount != nil)
        let unit = initial.unit ?? (slot == .bibleReading ? .pages : .minutes)
        _unit = State(initialValue: unit)
        _amountText = State(initialValue: String(initial.amount ?? Goals.suggestedAmount(unit)))
        _custom = State(initialValue: !Goals.presets(slot).contains { Goals.target($0, for: slot) == initial })
    }

    private var amount: Int? { Int(amountText.trimmingCharacters(in: .whitespaces)) }

    /// The target as typed, or nil while something is outside its limits. The slot's
    /// standard target with its default icon is the standard target, which records nothing.
    private var target: Challenge.Target? {
        guard let name = Challenge.targetName(name) else { return nil }
        var target = Challenge.Target(name: name, amount: hasAmount ? amount : nil, unit: hasAmount ? unit : nil, icon: icon)
        let plain = Challenge.Target(name: target.name, amount: target.amount, unit: target.unit)
        if plain == Challenge.Targets.standard[slot], icon == nil || icon == Goals.defaultIcon(slot) { target = plain }
        return target.isValid(for: slot) ? target : nil
    }

    private var problem: String? {
        if let problem = Goals.nameProblem(name) { return problem }
        guard hasAmount, slot != .diet else { return nil }
        guard let amount, unit.amounts.contains(amount) else {
            return "\(Goals.unitTitle(unit).capitalized) must be \(Goals.range(unit))."
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorHeader(title: Goals.role(slot), symbol: Goals.symbol(slot, preview))
            ChipFlow(spacing: 6) {
                ForEach(Goals.presets(slot)) { preset in
                    GoalChip(title: preset.name, selected: !custom && Goals.target(preset, for: slot) == target) {
                        choose(preset)
                    }
                }
                GoalChip(title: "Custom…", selected: custom) {
                    custom = true; name = ""; error = nil; focus = .name
                }
            }
            GlassField(symbol: "character.cursor.ibeam", placeholder: "Name", text: $name,
                       invalid: !name.isEmpty && Goals.nameProblem(name) != nil, focus: $focus, equals: .name, onSubmit: done)
                .onChange(of: name) { _, _ in error = nil }
                .accessibilityLabel("Name")
            if custom && slot != .diet { iconPicker }
            if slot != .diet { amountRow }
            preview(row: true)
            Text(slot == .diet ? "You mark the day clean or missed by your own rules." : "You tick it yourself when it's done.")
                .font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
            if let message = error ?? (name.isEmpty ? nil : problem) { FieldError(text: message) }
            EditorButtons(cancel: close, done: done, canSave: target != nil)
        }
        .padding(16).frame(width: 340).trackerSurface().focusEffectDisabled()
    }

    private var preview: Challenge.Target { target ?? Challenge.Target(name: name, icon: icon) }

    private var iconPicker: some View {
        ChipFlow(spacing: 6) {
            ForEach(Goals.iconChoices, id: \.self) { id in
                let selected = (icon ?? Goals.defaultIcon(slot)) == id
                Button { icon = id } label: { Image(systemName: Goals.symbols[id]!) }
                    .buttonStyle(RoundIconStyle(size: 32, fill: selected ? Theme.accentTint : Theme.controlFill,
                                                foreground: selected ? Theme.accentText : Theme.textPrimary,
                                                border: selected ? Theme.accentText.opacity(0.6) : .clear))
                    .help(id.capitalized)
                    .accessibilityLabel("Icon: \(id)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var amountRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Daily target").font(Theme.Fonts.rowLabel).foregroundStyle(Theme.textPrimary)
            HStack(spacing: 8) {
                if hasAmount {
                    Button { nudge(-1) } label: { Image(systemName: "minus") }
                        .buttonStyle(RoundIconStyle(size: 28)).help("Decrease").accessibilityLabel("Decrease amount")
                    GlassField(symbol: "number", placeholder: "Amount", text: $amountText,
                               invalid: problem != nil && Goals.nameProblem(name) == nil, focus: $focus, equals: .amount,
                               onSubmit: done)
                        .frame(width: 112)
                        .accessibilityLabel("Amount in \(Goals.unitTitle(unit))")
                    Button { nudge(1) } label: { Image(systemName: "plus") }
                        .buttonStyle(RoundIconStyle(size: 28)).help("Increase").accessibilityLabel("Increase amount")
                }
                Menu {
                    ForEach(Challenge.TargetUnit.allCases, id: \.self) { choice in
                        Button(Goals.unitTitle(choice)) { pick(choice) }
                    }
                    Divider()
                    Button("No amount") { hasAmount = false; error = nil }
                } label: {
                    Text(hasAmount ? Goals.unitTitle(unit) : "No amount").font(Theme.Fonts.pill)
                }
                .menuStyle(.button).fixedSize()
                .help("Choose a unit, or no amount")
                .accessibilityLabel("Unit")
                .accessibilityValue(hasAmount ? Goals.unitTitle(unit) : "No amount")
            }
            if hasAmount {
                Text(Goals.range(unit).prefix(1).uppercased() + Goals.range(unit).dropFirst())
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    /// "Shows as ( o ) YOGA · 30 min".
    @ViewBuilder
    private func preview(row: Bool) -> some View {
        let shown = preview
        HStack(spacing: 10) {
            Text("Shows as").font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
            Image(systemName: Goals.symbol(slot, shown)).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(Theme.ringTrack, lineWidth: 3))
            Eyebrow(text: shown.name.isEmpty ? Goals.role(slot) : shown.name, color: Theme.textPrimary,
                    font: Theme.Fonts.ringLabel, tracking: Theme.Tracking.ringLabel)
                .lineLimit(1)
            if let amount = Goals.amount(shown) {
                Text("· \(amount)").font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shows as \(shown.name), \(Goals.detail(slot, shown, spoken: true))")
    }

    private func choose(_ preset: Goals.Preset) {
        let chosen = Goals.target(preset, for: slot)
        custom = false
        error = nil
        name = chosen.name
        icon = chosen.icon
        hasAmount = chosen.amount != nil
        if let unit = chosen.unit, let amount = chosen.amount { self.unit = unit; amountText = String(amount) }
    }

    private func pick(_ choice: Challenge.TargetUnit) {
        if !hasAmount || choice != unit { amountText = String(Goals.suggestedAmount(choice)) }
        unit = choice
        hasAmount = true
        error = nil
    }

    private func nudge(_ direction: Int) {
        let range = unit.amounts
        let current = amount ?? Goals.suggestedAmount(unit)
        amountText = String(min(range.upperBound, max(range.lowerBound, current + direction * Goals.step(unit))))
        error = nil
    }

    private func done() {
        guard let target else { error = problem; return }
        error = save(target)
        if error == nil { close() }
    }
}

private struct EditorHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol).font(Theme.Fonts.appName).foregroundStyle(Theme.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct EditorButtons: View {
    let cancel: () -> Void
    let done: () -> Void
    let canSave: Bool

    var body: some View {
        HStack {
            Button("Cancel", action: cancel).buttonStyle(TintedPillStyle(height: 36))
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Done", action: done).buttonStyle(PrimaryPillStyle(height: 36, expands: false))
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
        .padding(.top, 2)
    }
}

/// A preset capsule: tinted when selected (shape too: a border), plain otherwise.
struct GoalChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(Theme.Fonts.field).lineLimit(1)
                .foregroundStyle(selected ? Theme.accentText : Theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule(style: .circular).fill(selected ? Theme.accentTint : Theme.controlFill))
                .overlay(Capsule(style: .circular).strokeBorder(selected ? Theme.accentText.opacity(0.6) : .clear, lineWidth: 1.5))
                .contentShape(Capsule(style: .circular))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Lays chips out in rows, wrapping at the proposed width.
struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

// MARK: Account › Daily goals

/// Account's Daily goals row: expands in place to the five rows, each saving from today on.
struct DailyGoalsSettings: View {
    let model: TrackerModel
    @State var expanded = false
    @State private var saved: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { expanded.toggle(); saved = nil } label: {
                SettingRow(symbol: "target", title: "Daily goals") {
                    if let saved, !expanded {
                        Badge(symbol: "checkmark", text: saved, fill: Theme.doneTint, foreground: Theme.doneText)
                    }
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.challenge == nil)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expanded ? "Hides your daily goals" : "Shows your daily goals to change them")
            .help("Change your water goal, glass size, activities, diet name and reading. Changes apply from today.")
            if expanded {
                GoalRows(targets: model.todayTargets, save: { targets in
                    let error = model.setTargets(targets)
                    if error == nil { saved = "Saved" }
                    return error
                })
                .padding(.leading, 4)
                Text("Changes apply from today, \(model.dates.label(model.today)). Earlier days keep the goals they had.")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.syncError == ChallengeSyncError.serverNeedsCustomGoalsUpdate.errorDescription {
                    Label("Saved on this Mac. The server needs an update before goal changes can sync; they upload once it is applied.",
                          systemImage: "exclamationmark.icloud")
                        .font(Theme.Fonts.caption).foregroundStyle(Theme.amberText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
