import ChallengeCore
import SwiftUI

struct HistoryTrackerView: View {
    @Bindable var model: TrackerModel
    @State private var month = Date()
    @State private var showingAudit = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                calendar
                Divider()
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.dates.label(model.selectedDay)).font(.headline)
                        Label(statusName, systemImage: statusIcon).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !model.isEditingHistory {
                        Button("Edit this day") { model.enableCorrections() }
                    } else {
                        Label("Editing", systemImage: "pencil").font(.caption).foregroundStyle(.orange)
                    }
                }
                if model.isEditingHistory {
                    Text("Corrections are saved immediately to this day. Streaks and milestones recalculate.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                WaterControls(model: model)
                HabitControls(model: model)
                DisclosureGroup("Activity & corrections (\(model.history.count))", isExpanded: $showingAudit) {
                    if model.history.isEmpty {
                        Text("No activity recorded. Closed unrecorded days are missed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(model.history) { activity in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(description(activity)).font(.caption)
                            Text("Edited \(model.dates.label(activity.recordedAt, format: "d MMM, HH:mm")) · \(ChallengeDates.city(model.dates.timeZone))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                    }
                }.font(.caption)
            }.padding(.bottom, 6)
        }
        .scrollIndicators(.hidden)
        .frame(height: 510)
        .onAppear { month = monthStart(model.selectedDay) }
        .onChange(of: model.selectedDay) { _, _ in showingAudit = false }
    }

    private var calendar: some View {
        VStack(spacing: 10) {
            HStack {
                Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(month <= monthStart(model.challenge?.startDate ?? model.today))
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(model.dates.label(month, format: "MMMM yyyy")).font(.headline)
                Spacer()
                Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(month >= monthStart(model.today)).accessibilityLabel("Next month")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, label in
                    Text(label).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 37) }
                ForEach(daysInMonth, id: \.self) { day in dayCell(day) }
            }
            HStack(spacing: 14) {
                Label("Complete", systemImage: "checkmark.circle.fill")
                Label("Missed", systemImage: "xmark.circle")
                Label("Today", systemImage: "circle.dotted")
            }.font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var leadingBlanks: Int {
        (model.dates.calendar.component(.weekday, from: month) - model.dates.calendar.firstWeekday + 7) % 7
    }

    private var daysInMonth: [Date] {
        guard let range = model.dates.calendar.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { model.dates.calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    private func dayCell(_ day: Date) -> some View {
        let state = model.challenge?.summary(on: day, asOf: model.now).status ?? .outsideChallenge
        let selected = model.dates.calendar.isDate(day, inSameDayAs: model.selectedDay)
        let allowed = state != .outsideChallenge && state != .future
        return Button { model.selectHistoryDay(day) } label: {
            VStack(spacing: 2) {
                Text("\(model.dates.calendar.component(.day, from: day))").font(.caption.monospacedDigit())
                Image(systemName: icon(state)).font(.system(size: 8)).foregroundStyle(state == .complete ? Color.green : Color.secondary)
            }.frame(maxWidth: .infinity, minHeight: 37)
                .background(selected ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Color.accentColor : .clear, lineWidth: 1))
        }.buttonStyle(.plain).disabled(!allowed)
            .accessibilityLabel("\(model.dates.label(day, format: "d MMMM yyyy")), \(name(state))")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .help(name(state))
    }

    private var statusName: String { name(model.summary?.status ?? .outsideChallenge) }
    private var statusIcon: String { icon(model.summary?.status ?? .outsideChallenge) }
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
        case .complete: "checkmark.circle.fill"
        case .missed: "xmark.circle"
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
