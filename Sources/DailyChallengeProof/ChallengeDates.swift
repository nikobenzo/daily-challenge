import Foundation

enum JerseyDates {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Jersey")!
        calendar.firstWeekday = 2
        return calendar
    }

    static func label(_ date: Date, format: String = "EEE, d MMM") -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
