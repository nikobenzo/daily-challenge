import ChallengeCore
import Foundation

/// Display and navigation dates in one challenge's own timezone.
struct ChallengeDates {
    let calendar: Calendar

    init(timeZone: TimeZone) {
        var calendar = Challenge.calendar(for: timeZone)
        calendar.firstWeekday = 2
        self.calendar = calendar
    }

    var timeZone: TimeZone { calendar.timeZone }

    func label(_ date: Date, format: String = "EEE, d MMM") -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// "New York", "Jersey", "GMT": the readable last part of the identifier.
    static func city(_ zone: TimeZone) -> String {
        (zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier)
            .replacingOccurrences(of: "_", with: " ")
    }

    /// "GMT+1", "GMT−4", "GMT+5:30", or "GMT" at the given instant.
    static func offset(_ zone: TimeZone, at date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        guard seconds != 0 else { return "GMT" }
        let minutes = abs(seconds) / 60
        let sign = seconds < 0 ? "−" : "+"
        return "GMT\(sign)\(minutes / 60)" + (minutes % 60 == 0 ? "" : String(format: ":%02d", minutes % 60))
    }
}
