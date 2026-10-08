import Foundation

/// Device preferences, deliberately not part of ChallengeRecord or sync.
public struct WaterReminderSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var intervalMinutes: Int
    public var startMinute: Int
    public var endMinute: Int

    public init(enabled: Bool = false, intervalMinutes: Int = 90,
                startMinute: Int = 9 * 60, endMinute: Int = 21 * 60) {
        self.enabled = enabled
        self.intervalMinutes = intervalMinutes
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    public var isValid: Bool {
        (15...240).contains(intervalMinutes) && (0...1439).contains(startMinute)
            && (startMinute...1439).contains(endMinute)
    }
}

/// Calendar slots anchored to the window start, inclusive of the end. Missing
/// DST wall times are skipped; repeated wall times occur once (first occurrence).
public struct WaterReminderPlanner {
    private let clock: () -> Date
    public init(clock: @escaping () -> Date = Date.init) { self.clock = clock }

    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Jersey")!
        return calendar
    }

    public func upcoming(settings: WaterReminderSettings, through horizon: Date,
                         waterMillilitres: (Date) -> Int?) -> [Date] {
        guard settings.enabled, settings.isValid else { return [] }
        let now = clock()
        let calendar = Self.calendar
        var day = calendar.startOfDay(for: now)
        var dates: [Date] = []
        while day <= horizon {
            if let water = waterMillilitres(day), water < 4_000 {
                dates += stride(from: settings.startMinute, through: settings.endMinute,
                                by: settings.intervalMinutes).compactMap { minute in
                    let components = DateComponents(hour: minute / 60, minute: minute % 60, second: 0)
                    guard let date = calendar.nextDate(after: day.addingTimeInterval(-1),
                        matching: components, matchingPolicy: .strict, repeatedTimePolicy: .first),
                        calendar.isDate(date, inSameDayAs: day), date > now, date <= horizon else { return nil }
                    return date
                }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return dates
    }
}
