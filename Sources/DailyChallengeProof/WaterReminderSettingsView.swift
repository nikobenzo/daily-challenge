import ChallengeCore
import SwiftUI

struct WaterReminderSettingsView: View {
    @Bindable var model: WaterReminderController

    static func details(timeZone: TimeZone) -> String {
        """
        Times are \(ChallengeDates.city(timeZone)) time, your challenge's time zone, within one day; the end must be at or after \
        the start, and reminders start when the window opens. This setting stays on this Mac and does not sync. The app must be running and awake; missed reminders are not replayed. \
        Finishing your water on another Mac stops reminders here once it syncs. Turning reminders on for both Macs can send duplicates. \
        Manage permission in System Settings > Notifications > Daily Challenge.
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Water reminders on this Mac", isOn: setting(\.enabled))
            Stepper("Every \(model.settings.intervalMinutes) minutes", value: setting(\.intervalMinutes), in: 15...240, step: 15)
            HStack {
                DatePicker("From", selection: time(\.startMinute), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: time(\.endMinute), displayedComponents: .hourAndMinute)
            }
            .environment(\.timeZone, model.timeZone)
            .environment(\.calendar, Challenge.calendar(for: model.timeZone))
            Text(model.status)
            if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            HStack(spacing: 4) {
                Text("Turn this on for just one Mac.").foregroundStyle(.secondary)
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                    .accessibilityLabel("More about water reminders")
                    .accessibilityHint(Self.details(timeZone: model.timeZone))
            }
            .help(Self.details(timeZone: model.timeZone))
        }
        .font(.caption)
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
