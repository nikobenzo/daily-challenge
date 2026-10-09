import ChallengeCore
import ChallengeSyncKit
import SwiftUI

/// Today's collapsible Extras list under the rings. Hidden entirely when the selected
/// day shows no extras; extras never count toward the five (`isComplete`).
struct ExtrasSection: View {
    @Bindable var model: TrackerModel
    @State var expanded = true
    @State private var managing = false
    @Environment(\.trackerReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        let done = model.summary?.extrasDone ?? 0
        let total = model.summary?.extrasTotal ?? 0
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(reduceMotion ? nil : Theme.Motion.crossFade) { expanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checklist").font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        Eyebrow(text: "Extras", font: .system(size: 12, weight: .bold))
                        Badge(symbol: done == total ? "checkmark" : nil, text: "\(done)/\(total)",
                              fill: done == total ? Theme.doneTint : Theme.controlFill,
                              foreground: done == total ? Theme.doneText : Theme.textPrimary, height: 22)
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(height: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Extras, \(done) of \(total) done")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                .help("Your own daily extras. They never count toward the five or your streak.")
                Button { managing = true } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(RoundIconStyle(size: 30))
                    .help("Manage extras")
                    .accessibilityLabel("Manage extras")
                    .popover(isPresented: $managing, arrowEdge: .bottom) { ManageExtrasView(model: model) }
            }
            if expanded {
                ExtrasChecklist(model: model)
                    .padding(.bottom, 6)
                    .transition(.opacity)
            }
        }
    }
}

/// One checkbox row per extra shown on the selected day. Ticks obey the same edit
/// rules as habit marks: today, or a past day after Edit this day.
struct ExtrasChecklist: View {
    @Bindable var model: TrackerModel

    var body: some View {
        let summary = model.summary
        VStack(spacing: 0) {
            ForEach(summary?.extras ?? []) { extra in
                let done = summary?.completedExtras.contains(extra.id) ?? false
                Button { model.toggleExtra(extra.id) } label: {
                    HStack(spacing: 12) {
                        ExtraCheckbox(done: done)
                        Text(extra.title).font(Theme.Fonts.field)
                            .foregroundStyle(done ? Theme.textSecondary : Theme.textPrimary)
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canEdit)
                .help(extra.title)
                .accessibilityLabel(extra.title)
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
        .popover(isPresented: $showing, arrowEdge: .bottom) {
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
        .help("Manage extras: your own daily to-dos. They never count toward the five or your streak.")
        .popover(isPresented: $managing, arrowEdge: .trailing) { ManageExtrasView(model: model) }
    }
}

/// Add, rename and archive, at most 10 active. No reordering, reminders, notes or icons.
struct ManageExtrasView: View {
    @Bindable var model: TrackerModel
    @State var newTitle = ""
    @State var renaming: UUID?
    @State private var renameTitle = ""
    @State var confirmingArchive: UUID?
    @State var error: String?
    @FocusState private var focus: Field?
    private enum Field: Hashable { case new, rename }

    var body: some View {
        let extras = model.activeExtras
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Extras", systemImage: "checklist").font(Theme.Fonts.appName).foregroundStyle(Theme.textPrimary)
                Spacer()
                Badge(text: "\(extras.count)/\(Challenge.maximumActiveExtras)", height: 24)
                    .accessibilityLabel("\(extras.count) of \(Challenge.maximumActiveExtras) extras")
            }
            Text("Daily to-dos of your own. They never count toward the five or your streak.")
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
                HStack(spacing: 8) {
                    GlassField(symbol: "plus", placeholder: "New extra", text: $newTitle,
                               focus: $focus, equals: .new, onSubmit: add)
                    Button(action: add) { Image(systemName: "plus") }
                        .buttonStyle(RoundIconStyle(size: 36, fill: Theme.primaryTop, foreground: .white))
                        .disabled(Challenge.extraTitle(newTitle) == nil)
                        .help("Add extra").accessibilityLabel("Add extra")
                }
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
            HStack(spacing: 8) {
                GlassField(symbol: "pencil", placeholder: "Name", text: $renameTitle,
                           focus: $focus, equals: .rename, onSubmit: { saveRename(extra) })
                Button { saveRename(extra) } label: { Image(systemName: "checkmark") }
                    .buttonStyle(RoundIconStyle(size: 32))
                    .disabled(Challenge.extraTitle(renameTitle) == nil)
                    .help("Save name").accessibilityLabel("Save name")
                Button { renaming = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(RoundIconStyle(size: 32))
                    .help("Cancel").accessibilityLabel("Cancel rename")
            }
            .padding(.vertical, 6)
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
            HStack(spacing: 8) {
                Text(extra.title).font(Theme.Fonts.field).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).truncationMode(.tail).help(extra.title)
                Spacer(minLength: 4)
                Button {
                    error = nil; confirmingArchive = nil
                    renameTitle = extra.title; renaming = extra.id; focus = .rename
                } label: { Image(systemName: "pencil") }
                    .buttonStyle(RoundIconStyle(size: 30))
                    .help("Rename").accessibilityLabel("Rename \(extra.title)")
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

    private func saveRename(_ extra: Challenge.Extra) {
        error = model.renameExtra(extra.id, to: renameTitle)
        if error == nil { renaming = nil }
    }

    private func archive(_ extra: Challenge.Extra) {
        error = model.archiveExtra(extra.id)
        confirmingArchive = nil
    }
}
