import ChallengeCore
import Foundation

/// Display and navigation dates in one challenge's own timezone.
public struct ChallengeDates: Sendable {
    public let calendar: Calendar

    public init(timeZone: TimeZone) {
        var calendar = Challenge.calendar(for: timeZone)
        calendar.firstWeekday = 2
        self.calendar = calendar
    }

    public var timeZone: TimeZone { calendar.timeZone }

    public func label(_ date: Date, format: String = "EEE, d MMM") -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// "New York", "Jersey", "GMT": the readable last part of the identifier.
    public static func city(_ zone: TimeZone) -> String {
        (zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier)
            .replacingOccurrences(of: "_", with: " ")
    }

    /// "GMT+1", "GMT−4", "GMT+5:30", or "GMT" at the given instant.
    public static func offset(_ zone: TimeZone, at date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        guard seconds != 0 else { return "GMT" }
        let minutes = abs(seconds) / 60
        let sign = seconds < 0 ? "−" : "+"
        return "GMT\(sign)\(minutes / 60)" + (minutes % 60 == 0 ? "" : String(format: ":%02d", minutes % 60))
    }
}

/// Every canonical zone, searchable by city, region or zone name ("Sydney", "Australia",
/// "Eastern") and grouped by region, for the setup pickers on each device.
public enum TimeZoneChoices {
    public struct Group: Sendable {
        public let region: String
        public let zones: [TimeZone]
    }

    /// "New York · GMT−4"
    public static func title(_ zone: TimeZone, at date: Date) -> String {
        "\(ChallengeDates.city(zone)) · \(ChallengeDates.offset(zone, at: date))"
    }

    public static let all: [TimeZone] = TimeZone.knownTimeZoneIdentifiers
        .compactMap(Challenge.canonicalTimeZone)
        .sorted { ChallengeDates.city($0).localizedStandardCompare(ChallengeDates.city($1)) == .orderedAscending }

    public static func groups(matching query: String) -> [Group] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let matches = searchable.filter { _, texts in
            words.allSatisfy { word in texts.contains { $0.localizedStandardContains(word) } }
        }.map(\.zone)
        return Dictionary(grouping: matches, by: region).sorted { $0.key < $1.key }
            .map { Group(region: $0.key, zones: $0.value) }
    }

    /// Localized zone names are looked up once, not on every keystroke.
    private static let searchable: [(zone: TimeZone, texts: [String])] = all.map { ($0, searchText($0)) }

    private static func region(_ zone: TimeZone) -> String {
        let parts = zone.identifier.split(separator: "/")
        return parts.count > 1 ? String(parts[0]) : "Other"
    }

    private static func searchText(_ zone: TimeZone) -> [String] {
        [zone.identifier.replacingOccurrences(of: "_", with: " "),
         zone.localizedName(for: .generic, locale: .current),
         zone.localizedName(for: .standard, locale: .current)].compactMap { $0 }
    }
}
