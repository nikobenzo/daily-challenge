import ChallengeCore
import ChallengeSyncKit
import SwiftUI

/// One of the five rows: water or one of the four labelled slots.
enum GoalField: Hashable, Identifiable {
    case water
    case slot(Challenge.TargetSlot)
    var id: String {
        switch self {
        case .water: "water"
        case .slot(let slot): slot.rawValue
        }
    }
    static let all: [GoalField] = [.water, .slot(.workout), .slot(.walk), .slot(.diet), .slot(.bibleReading)]
}

/// The five rows (Setup and Account › Daily goals): icon, name, the target in force and a
/// chevron. Tapping a row opens its editor.
struct GoalRows: View {
    let targets: Challenge.Targets
    let open: (GoalField) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(GoalField.all) { field in
                if field != .water { Theme.hairline.frame(height: 1) }
                Button { open(field) } label: { row(field).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title(field))
                    .accessibilityValue(spokenDetail(field))
                    .accessibilityHint("Opens its editor")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("goal-\(field.id)")
            }
        }
    }

    private func row(_ field: GoalField) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                icon(field)
                Text(title(field)).font(Theme.Fonts.rowLabel).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer(minLength: 8)
                Text(detail(field)).font(Theme.Fonts.field).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).monospacedDigit()
                chevron
            }
            // Large text: the detail moves under the name rather than truncating.
            HStack(spacing: 12) {
                icon(field)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(field)).font(Theme.Fonts.rowLabel).foregroundStyle(Theme.textPrimary)
                    Text(detail(field)).font(Theme.Fonts.field).foregroundStyle(Theme.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                chevron
            }
        }
        .frame(minHeight: 52)
    }

    private func icon(_ field: GoalField) -> some View {
        Image(systemName: symbol(field)).font(.system(size: 17, weight: .medium))
            .foregroundStyle(field == .water ? Theme.water : Theme.textPrimary)
            .frame(width: 24)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textTertiary)
    }

    private func symbol(_ field: GoalField) -> String {
        switch field {
        case .water: "drop.fill"
        case .slot(let slot): GoalWords.symbol(slot, targets[slot])
        }
    }

    private func title(_ field: GoalField) -> String {
        switch field {
        case .water: "Water"
        case .slot(let slot): targets[slot].name
        }
    }

    private func detail(_ field: GoalField) -> String {
        switch field {
        case .water: GoalWords.water(targets.water)
        case .slot(let slot): GoalWords.detail(slot, targets[slot])
        }
    }

    private func spokenDetail(_ field: GoalField) -> String {
        switch field {
        case .water: "Goal \(targets.water.goal.formatted()) millilitres, \(targets.water.glass.formatted()) millilitre glass"
        case .slot(.diet): "\(GoalWords.role(.diet)), your own rules"
        case .slot(let slot): [GoalWords.role(slot), GoalWords.spokenAmount(targets[slot]) ?? "no set amount"].joined(separator: ", ")
        }
    }
}

/// The editor for one row, in its own navigation stack (a sheet on Setup, a push in Daily
/// goals). `save` returns nil once saved, otherwise the reason nothing was saved.
struct GoalEditor: View {
    let field: GoalField
    let targets: Challenge.Targets
    /// "Applies from today, Mon 12 Oct…" after the start; nil during setup.
    var footnote: String?
    let save: (Challenge.Targets) -> String?

    var body: some View {
        switch field {
        case .water: WaterGoalEditor(targets: targets, footnote: footnote, save: save)
        case .slot(let slot): TargetEditor(slot: slot, targets: targets, footnote: footnote, save: save)
        }
    }
}

// MARK: Water

struct WaterGoalEditor: View {
    let targets: Challenge.Targets
    var footnote: String?
    let save: (Challenge.Targets) -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var goal: Int
    @State private var glass: Int
    @State private var otherGlass: String
    @State private var choosingOther: Bool
    @State private var error: String?
    @FocusState private var focusedField: String?
    @ScaledMetric(relativeTo: .body) private var controlHeight = 44.0

    init(targets: Challenge.Targets, footnote: String?, save: @escaping (Challenge.Targets) -> String?) {
        self.targets = targets
        self.footnote = footnote
        self.save = save
        let water = targets.water
        _goal = State(initialValue: water.goal)
        _glass = State(initialValue: water.glass)
        let preset = GoalWords.glassPresets.contains(water.glass)
        _otherGlass = State(initialValue: preset ? "" : "\(water.glass)")
        _choosingOther = State(initialValue: !preset)
    }

    private var chosenGlass: Int? { choosingOther ? Int(otherGlass.trimmingCharacters(in: .whitespaces)) : glass }
    private var problem: String? {
        guard let glass = chosenGlass, Challenge.WaterTarget.glasses.contains(glass) else {
            return "A glass or bottle is 50 to 1,000 ml."
        }
        return glass > goal ? "A glass can't hold more than the daily goal." : nil
    }

    var body: some View {
        PhoneScreen {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Daily goal", font: Theme.Fonts.caption)
                    HStack(spacing: 14) {
                        Button { goal = stepped(goal, by: -250) } label: { Image(systemName: "minus") }
                            .buttonStyle(RoundIconStyle(size: 44)).disabled(goal <= Challenge.WaterTarget.goals.lowerBound)
                            .accessibilityHidden(true)
                        Text("\(goal.formatted()) ml").font(Theme.Fonts.streak).monospacedDigit()
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                        Button { goal = stepped(goal, by: 250) } label: { Image(systemName: "plus") }
                            .buttonStyle(RoundIconStyle(size: 44)).disabled(goal >= Challenge.WaterTarget.goals.upperBound)
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Daily goal")
                    .accessibilityValue("\(goal.formatted()) millilitres")
                    .accessibilityAdjustableAction { direction in
                        goal = stepped(goal, by: direction == .increment ? 250 : -250)
                    }
                    .accessibilityIdentifier("water-goal")
                    Text("1,000 to 5,000 ml, in steps of 250.").font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
                }
                .padding(Theme.Size.sectionHorizontal)
                HairlineDivider()
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Your glass or bottle", font: Theme.Fonts.caption)
                    FlowLayout(spacing: 8) {
                        ForEach(GoalWords.glassPresets, id: \.self) { size in
                            Button("\(size) ml") { glass = size; choosingOther = false; focusedField = nil }
                                .buttonStyle(ChoiceCapsuleStyle(selected: !choosingOther && glass == size))
                                .accessibilityAddTraits(!choosingOther && glass == size ? .isSelected : [])
                        }
                        Button("Other…") { choosingOther = true; focusedField = "glass" }
                            .buttonStyle(ChoiceCapsuleStyle(selected: choosingOther))
                            .accessibilityAddTraits(choosingOther ? .isSelected : [])
                            .accessibilityIdentifier("glass-other")
                    }
                    if choosingOther {
                        TextField("Glass size in ml", text: $otherGlass,
                                  prompt: Text("Glass size in ml").foregroundStyle(Theme.textTertiary))
                            .keyboardType(.numberPad)
                            .phoneField(focus: $focusedField, id: "glass", height: controlHeight)
                            .accessibilityIdentifier("glass-other-amount")
                    }
                    if let problem {
                        FieldError(text: problem).accessibilityIdentifier("water-problem")
                    } else if let glass = chosenGlass {
                        Text("The + button adds \(glass.formatted()) ml. About \(glasses(glass)) a day.")
                            .font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("The custom pour button still logs any amount.").font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Size.sectionHorizontal)
            }
            GoalFootnote(text: footnote, error: error)
        }
        .foregroundStyle(Theme.textPrimary)
        .navigationTitle("Water").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: done).disabled(problem != nil).accessibilityIdentifier("goal-done")
            }
        }
    }

    /// Moves by 250 ml within the limits, snapping a goal set elsewhere to the step.
    private func stepped(_ value: Int, by step: Int) -> Int {
        let snapped = step > 0 ? (value / 250 + 1) * 250 : ((value - 1) / 250) * 250
        return min(Challenge.WaterTarget.goals.upperBound, max(Challenge.WaterTarget.goals.lowerBound, snapped))
    }

    private func glasses(_ glass: Int) -> String {
        let count = Int((Double(goal) / Double(glass)).rounded(.up))
        return count == 1 ? "1 glass" : "\(count) glasses"
    }

    private func done() {
        guard problem == nil, let glass = chosenGlass else { return }
        var next = targets
        next.water = Challenge.WaterTarget(goal: goal, glass: glass)
        error = save(next)
        if error == nil { dismiss() }
    }
}

// MARK: Activities, diet and reading

struct TargetEditor: View {
    let slot: Challenge.TargetSlot
    let targets: Challenge.Targets
    var footnote: String?
    let save: (Challenge.Targets) -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var unit: Challenge.TargetUnit?
    @State private var amountText: String
    @State private var icon: String?
    @State private var error: String?
    @FocusState private var focusedField: String?
    @ScaledMetric(relativeTo: .body) private var controlHeight = 44.0

    init(slot: Challenge.TargetSlot, targets: Challenge.Targets, footnote: String?,
         save: @escaping (Challenge.Targets) -> String?) {
        self.slot = slot
        self.targets = targets
        self.footnote = footnote
        self.save = save
        let target = targets[slot]
        _name = State(initialValue: target.name)
        _unit = State(initialValue: target.unit)
        _amountText = State(initialValue: target.amount.map(String.init) ?? "")
        _icon = State(initialValue: target.icon)
    }

    private var amount: Int? { Int(amountText.trimmingCharacters(in: .whitespaces)) }

    /// What would be saved, or nil while something is outside the limits.
    private var draft: Challenge.Target? {
        guard let name = Challenge.targetName(name) else { return nil }
        if slot == .diet { return Challenge.Target(name: name, icon: icon) }
        guard let unit else { return Challenge.Target(name: name, icon: normalised(icon)) }
        guard let amount, unit.amounts.contains(amount) else { return nil }
        return Challenge.Target(name: name, amount: amount, unit: unit, icon: normalised(icon))
    }

    var body: some View {
        PhoneScreen {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: slot == .diet ? "Call it" : "Choose", font: Theme.Fonts.caption)
                    FlowLayout(spacing: 8) {
                        ForEach(GoalWords.presets(slot)) { preset in
                            Button(preset.name) { choose(preset) }
                                .buttonStyle(ChoiceCapsuleStyle(selected: matches(preset)))
                                .accessibilityAddTraits(matches(preset) ? .isSelected : [])
                        }
                        Button("Custom…") { name = ""; focusedField = "name" }
                            .buttonStyle(ChoiceCapsuleStyle(selected: !GoalWords.presets(slot).contains(where: matches)))
                            .accessibilityIdentifier("preset-custom")
                    }
                    TextField("Name", text: $name, prompt: Text("Name").foregroundStyle(Theme.textTertiary))
                        .phoneField(focus: $focusedField, id: "name", height: controlHeight)
                        .submitLabel(.done)
                        .accessibilityIdentifier("target-name")
                    nameHelp
                }
                .padding(Theme.Size.sectionHorizontal)
                if slot != .diet {
                    HairlineDivider()
                    amountSection.padding(Theme.Size.sectionHorizontal)
                    HairlineDivider()
                    iconSection.padding(Theme.Size.sectionHorizontal)
                }
                HairlineDivider()
                preview.padding(Theme.Size.sectionHorizontal)
            }
            GoalFootnote(text: footnote, error: error)
        }
        .foregroundStyle(Theme.textPrimary)
        .navigationTitle(GoalWords.role(slot)).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: done).disabled(draft == nil).accessibilityIdentifier("goal-done")
            }
        }
    }

    private var nameHelp: some View {
        let invalid = Challenge.targetName(name) == nil
        return Text(invalid && !name.isEmpty ? "Use a name of 1 to 20 characters on one line."
                    : invalid ? "Give it a name." : "One line, 1 to 20 characters.")
            .font(Theme.Fonts.caption)
            .foregroundStyle(invalid ? Theme.danger : Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("target-name-help")
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: "Daily target", font: Theme.Fonts.caption)
                Spacer()
                Menu {
                    Picker("Unit", selection: unitBinding) {
                        Text("No amount").tag(Challenge.TargetUnit?.none)
                        ForEach(Challenge.TargetUnit.allCases, id: \.self) { unit in
                            Text(GoalWords.unitName(unit, 2).capitalized).tag(Challenge.TargetUnit?.some(unit))
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(unit.map { GoalWords.unitName($0, 2).capitalized } ?? "No amount")
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .bold))
                    }
                    .font(Theme.Fonts.field)
                }
                .accessibilityLabel("Unit")
                .accessibilityValue(unit.map { GoalWords.unitName($0, 2) } ?? "No amount")
                .accessibilityIdentifier("target-unit")
            }
            if let unit {
                HStack(spacing: 12) {
                    Button { nudge(-1, unit) } label: { Image(systemName: "minus") }
                        .buttonStyle(RoundIconStyle(size: 44))
                        .disabled((amount ?? 0) <= unit.amounts.lowerBound)
                        .accessibilityLabel("Less")
                    TextField("Amount", text: $amountText, prompt: Text("Amount").foregroundStyle(Theme.textTertiary))
                        .keyboardType(.numberPad).multilineTextAlignment(.center).monospacedDigit()
                        .phoneField(focus: $focusedField, id: "amount", height: controlHeight)
                        .accessibilityLabel("Amount in \(GoalWords.unitName(unit, 2))")
                        .accessibilityIdentifier("target-amount")
                    Button { nudge(1, unit) } label: { Image(systemName: "plus") }
                        .buttonStyle(RoundIconStyle(size: 44))
                        .disabled((amount ?? .max) >= unit.amounts.upperBound)
                        .accessibilityLabel("More")
                }
                let range = "\(unit.amounts.lowerBound.formatted()) to \(unit.amounts.upperBound.formatted()) \(GoalWords.unitName(unit, 2))"
                if let amount, unit.amounts.contains(amount) {
                    Text(range.prefix(1).uppercased() + range.dropFirst() + ".").font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    FieldError(text: "Use \(range).").accessibilityIdentifier("target-amount-problem")
                }
            } else {
                Text("No amount: it shows by name only.").font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Icon", font: Theme.Fonts.caption)
            FlowLayout(spacing: 8) {
                ForEach(GoalWords.icons, id: \.id) { choice in
                    let selected = GoalWords.symbol(slot, Challenge.Target(name: "x", icon: icon)) == choice.symbol
                    Button { icon = choice.id } label: {
                        Image(systemName: choice.symbol).font(.system(size: 17, weight: .semibold))
                    }
                    .buttonStyle(RoundIconStyle(size: 44, fill: selected ? Theme.accentTint : Theme.controlFill,
                                                foreground: selected ? Theme.accentText : Theme.textPrimary,
                                                border: selected ? Theme.focus : .clear))
                    .accessibilityLabel("\(choice.name) icon")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var preview: some View {
        let shown = draft ?? Challenge.Target(name: name.isEmpty ? GoalWords.role(slot) : name)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Eyebrow(text: "Shows as", font: Theme.Fonts.caption)
                Image(systemName: GoalWords.symbol(slot, shown)).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Eyebrow(text: shown.name, color: Theme.textPrimary, font: Theme.Fonts.caption).lineLimit(1)
                if let amount = GoalWords.amount(shown) {
                    Text("· \(amount)").font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Shows as \(GoalWords.spoken(slot, shown))")
            Text(slot == .diet ? "Each day is still pending, clean or missed, by your own rules."
                 : "You tick it yourself when it's done.")
                .font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unitBinding: Binding<Challenge.TargetUnit?> {
        Binding(get: { unit }, set: { next in
            unit = next
            guard let next else { amountText = ""; return }
            let current = amount ?? suggested(next)
            amountText = String(min(next.amounts.upperBound, max(next.amounts.lowerBound, current)))
        })
    }

    private func suggested(_ unit: Challenge.TargetUnit) -> Int {
        switch unit {
        case .minutes: 30
        case .pages: 10
        case .chapters: 1
        case .kilometres: 5
        case .miles: 3
        case .steps: 10_000
        }
    }

    private func nudge(_ direction: Int, _ unit: Challenge.TargetUnit) {
        let step = GoalWords.step(unit)
        let current = amount ?? suggested(unit)
        let next = direction > 0 ? (current / step + 1) * step : ((current - 1) / step) * step
        amountText = String(min(unit.amounts.upperBound, max(unit.amounts.lowerBound, next)))
    }

    private func choose(_ preset: GoalWords.Preset) {
        name = preset.name
        unit = preset.unit
        amountText = preset.amount.map(String.init) ?? ""
        icon = preset.icon
        focusedField = nil
    }

    private func matches(_ preset: GoalWords.Preset) -> Bool { name == preset.name }

    /// An icon that looks like the slot's own is stored as none, so picking the standard
    /// look records nothing new.
    private func normalised(_ id: String?) -> String? {
        guard let id else { return nil }
        return GoalWords.symbol(slot, Challenge.Target(name: "x", icon: id)) == GoalWords.defaultSymbol(slot) ? nil : id
    }

    private func done() {
        guard let draft else { return }
        var next = targets
        next[slot] = draft
        error = save(next)
        if error == nil { dismiss() }
    }
}

/// "Applies from today…" under an editor, and why a save failed.
struct GoalFootnote: View {
    let text: String?
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error { FieldError(text: error).accessibilityIdentifier("goal-error") }
            if let text {
                Text(text).font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.xs)
    }
}

// MARK: Account › Daily goals

/// Today's five, each opening its editor. A change is recorded on today and applies from
/// today; earlier days keep the goals they had.
struct PhoneDailyGoalsView: View {
    @Bindable var tracker: TrackerModel
    @Environment(\.dismiss) private var dismiss
    @State private var path: [GoalField] = []

    var body: some View {
        NavigationStack(path: $path) {
            PhoneScreen {
                GlassCard {
                    GoalRows(targets: tracker.todayTargets) { path.append($0) }
                        .padding(.horizontal, Theme.Size.sectionHorizontal)
                }
                Text(Self.appliesFrom(tracker))
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Space.xs)
                    .accessibilityIdentifier("goals-applies")
                GoalsServerNotice(tracker: tracker)
            }
            .foregroundStyle(Theme.textPrimary)
            .navigationTitle("Daily goals").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(for: GoalField.self) { field in
                GoalEditor(field: field, targets: tracker.todayTargets, footnote: Self.appliesFrom(tracker)) {
                    tracker.setTargets($0)
                }
            }
        }
        #if DEBUG
        .onAppear { if let field = PhoneFixtures.editingGoal { path = [field] } }
        #endif
    }

    /// "Changes apply from today, Mon 12 Oct. Earlier days keep the goals they had."
    static func appliesFrom(_ tracker: TrackerModel) -> String {
        "Changes apply from today, \(tracker.dates.label(tracker.today, format: "EEE d MMM")). "
            + "Earlier days keep the goals they had."
    }
}

/// Shown while the server has not had the custom goals update: what was changed is saved
/// on this iPhone and waits, and nothing is lost.
struct GoalsServerNotice: View {
    let tracker: TrackerModel

    var body: some View {
        if tracker.syncError == ChallengeSyncError.serverNeedsCustomGoalsUpdate.errorDescription {
            Label {
                Text("Saved on this iPhone. The server needs an update before goal and repeat changes can sync, "
                     + "so they wait here with your other recent entries. Nothing is lost.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.icloud")
            }
            .font(Theme.Fonts.caption).foregroundStyle(Theme.amberText)
            .padding(Theme.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.amberTint))
            .accessibilityIdentifier("goals-server-notice")
        }
    }
}

// MARK: Pieces

/// A preset capsule: selected ones take the accent tint and ring.
struct ChoiceCapsuleStyle: ButtonStyle {
    let selected: Bool
    @ScaledMetric(relativeTo: .body) private var height = 36.0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.field)
            .foregroundStyle(selected ? Theme.accentText : Theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: max(height, 36))
            .background(Capsule(style: .circular).fill(selected ? Theme.accentTint : Theme.controlFill))
            .overlay(Capsule(style: .circular).strokeBorder(selected ? Theme.focus : .clear, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule(style: .circular))
    }
}

/// Lays children out left to right, wrapping onto new rows: preset capsules and icons.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row(indices: [index], width: size.width, height: size.height))
            } else {
                rows[rows.count - 1].indices.append(index)
                rows[rows.count - 1].width = needed
                rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            }
        }
        return rows
    }
}
