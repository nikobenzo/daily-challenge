import ChallengeCore
import ChallengeSyncKit
import SwiftUI

/// Optional daily to-dos; their count comes from the selected day's summary.
struct PhoneExtrasSection: View {
    @Bindable var tracker: TrackerModel
    @State private var managing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if (tracker.summary?.extrasTotal ?? 0) == 0 {
                Button { managing = true } label: {
                    Label("Extras · Add your own to-dos", systemImage: "checklist")
                        .font(Theme.Fonts.field).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("extras-empty")
            } else {
                HStack {
                    PhoneExtrasHeading(tracker: tracker)
                    Spacer(minLength: 8)
                    Button { managing = true } label: { Image(systemName: "square.and.pencil") }
                        .buttonStyle(RoundIconStyle(size: 44))
                        .accessibilityLabel("Manage extras").accessibilityIdentifier("extras-manage")
                }
                PhoneExtrasChecklist(tracker: tracker)
            }
        }
        .padding(.horizontal, Theme.Size.sectionHorizontal)
        .padding(.vertical, Theme.Space.s)
        .sheet(isPresented: $managing) { PhoneManageExtrasView(tracker: tracker) }
        #if DEBUG
        .onAppear { managing = PhoneFixtures.showingManagement }
        #endif
    }
}

struct PhoneExtrasHeading: View {
    let tracker: TrackerModel

    var body: some View {
        let done = tracker.summary?.extrasDone ?? 0
        let total = tracker.summary?.extrasTotal ?? 0
        Label("Extras · \(done)/\(total)", systemImage: "checklist")
            .font(Theme.Fonts.rowLabel).foregroundStyle(Theme.textSecondary)
            .accessibilityLabel("Extras, \(done) of \(total) done")
            .accessibilityIdentifier("extras-count")
            .accessibilityAddTraits(.isHeader)
    }
}

/// Uses historical extras, including extras archived after the selected day.
struct PhoneExtrasChecklist: View {
    @Bindable var tracker: TrackerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(tracker.summary?.extras ?? []) { extra in
                let done = tracker.summary?.completedExtras.contains(extra.id) == true
                Button { tracker.toggleExtra(extra.id) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24)).foregroundStyle(done ? Theme.done : Theme.textTertiary)
                            .accessibilityHidden(true)
                        Text(extra.title).font(Theme.Fonts.field)
                            .foregroundStyle(done ? Theme.textSecondary : Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.vertical, 4).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(!tracker.canEdit)
                .accessibilityLabel(extra.title).accessibilityValue(done ? "Done" : "Not done")
                .accessibilityHint(tracker.canEdit ? "Double-tap to \(done ? "undo" : "mark done")" : "Select Edit this day to correct this tick")
                .accessibilityIdentifier("extra-\(extra.id.uuidString)")
            }
        }
    }
}

/// One native, scrolling management sheet used by Today and Account.
struct PhoneManageExtrasView: View {
    @Bindable var tracker: TrackerModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var controlHeight = 44.0
    @State private var newTitle = ""
    @State private var renaming: Challenge.Extra?
    @State private var renameTitle = ""
    @State private var archiving: Challenge.Extra?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            PhoneScreen {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(tracker.activeExtras.count)/\(Challenge.maximumActiveExtras) extras")
                            .font(Theme.Fonts.rowLabel).accessibilityIdentifier("extras-active-count")
                        Text("Daily to-dos of your own. They never count toward the five or your streak.")
                            .font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if tracker.canAddExtra {
                            TextField("New extra", text: $newTitle, prompt: Text("New extra").foregroundStyle(Theme.textTertiary))
                                .textFieldStyle(.roundedBorder).font(Theme.Fonts.field)
                                .accessibilityIdentifier("extras-new-title")
                            titleHelp(newTitle)
                            Button("Add extra", action: add)
                                .buttonStyle(TintedPillStyle(height: controlHeight, expands: true))
                                .disabled(Challenge.extraTitle(newTitle) == nil)
                                .accessibilityIdentifier("extras-add")
                        } else {
                            Label("Up to 10 extras. Archive one to add another.", systemImage: "info.circle")
                                .font(Theme.Fonts.caption).foregroundStyle(Theme.amberText)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("extras-cap")
                        }
                        if let error { FieldError(text: error) }
                    }
                    .padding(Theme.Size.sectionHorizontal)
                }
                if !tracker.activeExtras.isEmpty {
                    GlassCard {
                        VStack(spacing: 0) {
                            ForEach(tracker.activeExtras) { extra in
                                if extra.id != tracker.activeExtras.first?.id { HairlineDivider() }
                                row(extra).padding(Theme.Size.sectionHorizontal)
                                    .id(extra.id == tracker.activeExtras.first?.id ? "fixture-extra-actions" : extra.id.uuidString)
                            }
                        }
                    }
                }
            }
            .foregroundStyle(Theme.textPrimary)
            .navigationTitle("Manage extras").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Archive extra?", isPresented: Binding(
                get: { archiving != nil }, set: { if !$0 { archiving = nil } }
            )) {
                if let extra = archiving {
                    Button("Archive \(extra.title)", role: .destructive) {
                        error = tracker.archiveExtra(extra.id); archiving = nil
                    }
                }
                Button("Cancel", role: .cancel) { archiving = nil }
            } message: {
                Text("It disappears from today on and can't be restored. Earlier days keep their ticks.")
            }
        }
    }

    private func row(_ extra: Challenge.Extra) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if renaming?.id == extra.id {
                TextField("Name", text: $renameTitle, prompt: Text("Name").foregroundStyle(Theme.textTertiary))
                    .textFieldStyle(.roundedBorder).font(Theme.Fonts.field)
                    .accessibilityIdentifier("extras-rename-title")
                titleHelp(renameTitle)
                actionLayout {
                    Button("Save name") {
                        error = tracker.renameExtra(extra.id, to: renameTitle)
                        if error == nil { renaming = nil }
                    }
                    .buttonStyle(TintedPillStyle(height: controlHeight, expands: true))
                    .disabled(Challenge.extraTitle(renameTitle) == nil)
                    Button("Cancel") { renaming = nil }.buttonStyle(TintedPillStyle(height: controlHeight, expands: true))
                }
            } else {
                Text(extra.title).font(Theme.Fonts.field).fixedSize(horizontal: false, vertical: true)
                actionLayout {
                    Button { error = nil; renameTitle = extra.title; renaming = extra } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .buttonStyle(TintedPillStyle(height: controlHeight, expands: true)).accessibilityLabel("Rename \(extra.title)")
                    Button { error = nil; renaming = nil; archiving = extra } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .buttonStyle(TintedPillStyle(height: controlHeight, fill: Theme.dangerTint, foreground: Theme.danger, expands: true))
                    .accessibilityLabel("Archive \(extra.title)")
                }
                .font(Theme.Fonts.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    private func titleHelp(_ title: String) -> some View {
        Text(title.isEmpty || Challenge.extraTitle(title) != nil
             ? "One line, 1–40 characters." : "Use a name of 1–40 characters on one line.")
            .font(Theme.Fonts.caption)
            .foregroundStyle(!title.isEmpty && Challenge.extraTitle(title) == nil ? Theme.danger : Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func add() {
        error = tracker.addExtra(newTitle)
        if error == nil { newTitle = "" }
    }
}
