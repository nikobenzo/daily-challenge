import ChallengeCore
import ChallengeSyncKit
import SwiftUI

struct WaterReminderSettingsView: View {
    @Bindable var model: WaterReminderController
    @State private var choosingWindow = false

    static func details(timeZone: TimeZone) -> String {
        """
        Times are \(ChallengeDates.city(timeZone)) time, your challenge's time zone, within one day; the end must be at or after \
        the start, and reminders start when the window opens. This setting stays on this Mac and does not sync. The app must be running and awake; missed reminders are not replayed. \
        Finishing your water on another Mac stops reminders here once it syncs. Turning reminders on for both Macs can send duplicates. \
        Manage permission in System Settings > Notifications > Daily Challenge.
        """
    }

    var body: some View {
        let interval = model.settings.intervalMinutes
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: setting(\.enabled)) {
                HStack(spacing: 12) {
                    Image(systemName: "bell").font(.system(size: 17, weight: .medium)).frame(width: 24)
                        .accessibilityHidden(true)
                    Text("Reminders").font(Theme.Fonts.rowLabel)
                    Image(systemName: "questionmark.circle").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                        .help("Turn this on for just one Mac. " + Self.details(timeZone: model.timeZone))
                        .accessibilityLabel("More about water reminders")
                        .accessibilityHint(Self.details(timeZone: model.timeZone))
                }
                .foregroundStyle(Theme.textPrimary)
            }
            .toggleStyle(GlassToggleStyle())
            .frame(minHeight: 44)
            .accessibilityLabel("Water reminders on this Mac")
            HStack {
                PillStepper(text: "\(interval) min", accessibilityText: "Every \(interval) minutes",
                            decrement: interval > 15 ? { step(-15) } : nil,
                            increment: interval < 240 ? { step(15) } : nil)
                    .help("How often to remind you")
                Spacer()
                Button { choosingWindow = true } label: {
                    Label("\(Self.clock(model.settings.startMinute)) – \(Self.clock(model.settings.endMinute))", systemImage: "clock")
                        .monospacedDigit()
                }
                .buttonStyle(TintedPillStyle(height: Theme.Size.segmentTrack))
                .help("Reminder hours, \(ChallengeDates.city(model.timeZone)) time")
                .accessibilityLabel("Reminder hours")
                .accessibilityValue("From \(Self.clock(model.settings.startMinute)) until \(Self.clock(model.settings.endMinute))")
                .popover(isPresented: $choosingWindow, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        DatePicker("From", selection: time(\.startMinute), displayedComponents: .hourAndMinute)
                        DatePicker("Until", selection: time(\.endMinute), displayedComponents: .hourAndMinute)
                    }
                    .padding(16)
                    .environment(\.timeZone, model.timeZone)
                    .environment(\.calendar, Challenge.calendar(for: model.timeZone))
                    .trackerSurface()
                }
            }
            .padding(.leading, 36)
            Text(model.status).font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 36)
            if let error = model.errorMessage {
                FieldError(text: error).padding(.leading, 36)
            }
        }
    }

    static func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }

    private func step(_ delta: Int) {
        var settings = model.settings
        settings.intervalMinutes = min(240, max(15, settings.intervalMinutes + delta))
        model.update(settings)
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<WaterReminderSettings, Value>) -> Binding<Value> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { value in
            var settings = model.settings
            settings[keyPath: keyPath] = value
            model.update(settings)
        })
    }

    private func time(_ keyPath: WritableKeyPath<WaterReminderSettings, Int>) -> Binding<Date> {
        // A fixed day without a transition in the zone represents a wall-clock preference.
        let calendar = Challenge.calendar(for: model.timeZone)
        let day = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        return Binding(get: {
            calendar.date(byAdding: .minute, value: model.settings[keyPath: keyPath], to: day)!
        }, set: { date in
            let components = calendar.dateComponents([.hour, .minute], from: date)
            var settings = model.settings
            settings[keyPath: keyPath] = components.hour! * 60 + components.minute!
            model.update(settings)
        })
    }
}
