import ChallengeCore
import SwiftUI

struct WaterReminderSettingsView: View {
    @Bindable var model: WaterReminderController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Toggle("Water reminders on this Mac", isOn: setting(\.enabled))
            Stepper("Every \(model.settings.intervalMinutes) minutes", value: setting(\.intervalMinutes), in: 15...240, step: 15)
            HStack {
                DatePicker("From", selection: time(\.startMinute), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: time(\.endMinute), displayedComponents: .hourAndMinute)
            }
            .environment(\.timeZone, WaterReminderPlanner.calendar.timeZone)
            .environment(\.calendar, WaterReminderPlanner.calendar)
            Text("Europe/Jersey · Same-day window; end must be at or after start. Slots start at the window opening.")
            Text(model.status)
            if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            Text("Choose just one Mac to remind you. This setting does not sync. The app must be running and awake. No missed reminders are replayed.")
            Text("Other-Mac completion stops reminders after it syncs here. Enabling both Macs can produce duplicates. Manage permission in System Settings > Notifications > Daily Challenge.")
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
        // A fixed non-transition Jersey day represents a wall-clock preference.
        let calendar = WaterReminderPlanner.calendar
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
