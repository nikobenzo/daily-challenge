import Foundation

public enum ChallengeError: LocalizedError {
    case invalidWaterAmount
    case dateOutsideChallenge
    case conflictingActivity

    public var errorDescription: String? {
        switch self {
        case .invalidWaterAmount: "Water amounts must be positive whole millilitres within the supported total."
        case .dateOutsideChallenge: "Only days from the challenge start through today can be edited."
        case .conflictingActivity: "An activity ID was reused with different content. Nothing was changed."
        }
    }
}

public struct Challenge: Codable, Sendable {
    public enum Habit: String, CaseIterable, Codable, Sendable {
        case workout, walk, bibleReading
    }

    public enum DietState: String, Codable, Sendable {
        case pending, clean, missed
    }

    public enum Action: Codable, Equatable, Sendable {
        case pour(Int)
        case undoLatestPour
        case setHabit(Habit, completed: Bool)
        case setDiet(DietState)
    }

    public struct Activity: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public let day: Date
        public let recordedAt: Date
        public let action: Action
        public let undonePourID: UUID?
        public let deviceID: String?

        public init(id: UUID, day: Date, recordedAt: Date, action: Action, undonePourID: UUID?, deviceID: String? = nil) {
            self.id = id; self.day = day; self.recordedAt = recordedAt
            self.action = action; self.undonePourID = undonePourID; self.deviceID = deviceID
        }

        private enum CodingKeys: String, CodingKey { case id, day, recordedAt, action, undonePourID, deviceID }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            day = Date(timeIntervalSinceReferenceDate: try c.decode(Double.self, forKey: .day))
            recordedAt = Date(timeIntervalSinceReferenceDate: try c.decode(Double.self, forKey: .recordedAt))
            action = try c.decode(Action.self, forKey: .action)
            undonePourID = try c.decodeIfPresent(UUID.self, forKey: .undonePourID)
            deviceID = try c.decodeIfPresent(String.self, forKey: .deviceID)
        }
        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(day.timeIntervalSinceReferenceDate, forKey: .day)
            try c.encode(recordedAt.timeIntervalSinceReferenceDate, forKey: .recordedAt)
            try c.encode(action, forKey: .action)
            try c.encodeIfPresent(undonePourID, forKey: .undonePourID)
            try c.encodeIfPresent(deviceID, forKey: .deviceID)
        }
    }

    public struct WaterPour: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let millilitres: Int
    }

    public enum DayStatus: String, Sendable {
        case outsideChallenge, future, inProgress, missed, complete
    }

    public struct DailySummary: Sendable {
        public let interval: DateInterval
        public let activePours: [WaterPour]
        public let completedHabits: Set<Habit>
        public let diet: DietState
        public var waterMillilitres: Int { activePours.reduce(0) { $0 + $1.millilitres } }
        public var waterComplete: Bool { waterMillilitres >= 4_000 }
        public let status: DayStatus
        public var isComplete: Bool { status == .complete }
    }

    public struct StreakSummary: Sendable {
        public let current: Int
        public let best: Int
        public let milestones: [Date]
    }

    /// Challenges created before each challenge chose its own timezone were all
    /// Jersey days. Only legacy data (snapshots, records, exports without a zone) uses it.
    public static let legacyTimeZoneIdentifier = "Europe/Jersey"
    public static var legacyTimeZone: TimeZone { TimeZone(identifier: legacyTimeZoneIdentifier)! }

    /// A zone is accepted only in its canonical spelling (for example "GMT", not
    /// "UTC"), so comparing identifiers compares zones: settings stay comparable.
    public static func canonicalTimeZone(_ identifier: String) -> TimeZone? {
        guard let zone = TimeZone(identifier: identifier), zone.identifier == identifier else { return nil }
        return zone
    }

    public let ownerID: UUID
    public let startDate: Date
    /// Every challenge day is a calendar date in this zone, bounded by its midnights.
    public let timeZone: TimeZone
    public let calendar: Calendar
    private var activities: [Activity] = []

    public init(ownerID: UUID, startDate: Date, timeZone: TimeZone) {
        self.ownerID = ownerID
        self.timeZone = timeZone
        calendar = Self.calendar(for: timeZone)
        self.startDate = calendar.startOfDay(for: startDate)
    }

    private enum CodingKeys: String, CodingKey {
        case ownerID, startDate, timeZone, activities
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(ownerID, forKey: .ownerID)
        try values.encode(startDate, forKey: .startDate)
        try values.encode(timeZone.identifier, forKey: .timeZone)
        try values.encode(activities, forKey: .activities)
    }

    /// Loading a snapshot must obey the same rules as recording live activity.
    /// Codable alone would allow duplicate IDs, invalid pours, and forged undos.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let owner = try values.decode(UUID.self, forKey: .ownerID)
        let start = try values.decode(Date.self, forKey: .startDate)
        let identifier = try values.decodeIfPresent(String.self, forKey: .timeZone) ?? Self.legacyTimeZoneIdentifier
        guard let zone = Self.canonicalTimeZone(identifier) else {
            throw DecodingError.dataCorruptedError(
                forKey: .timeZone, in: values, debugDescription: "Unknown challenge timezone"
            )
        }
        guard start.timeIntervalSince1970.isFinite, Self.calendar(for: zone).startOfDay(for: start) == start else {
            throw DecodingError.dataCorruptedError(
                forKey: .startDate, in: values, debugDescription: "Invalid challenge start day"
            )
        }
        let saved = try values.decode([Activity].self, forKey: .activities)
        guard Set(saved.map(\.id)).count == saved.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .activities, in: values, debugDescription: "Duplicate activity IDs"
            )
        }
        self.init(ownerID: owner, startDate: start, timeZone: zone)
        if saved.contains(where: { $0.deviceID != nil }) {
            try merge(saved)
            return
        }
        for activity in saved {
            guard activity.day.timeIntervalSince1970.isFinite,
                  activity.recordedAt.timeIntervalSince1970.isFinite,
                  day(activity.day) == activity.day else {
                throw DecodingError.dataCorruptedError(
                    forKey: .activities, in: values, debugDescription: "Invalid activity date"
                )
            }
            let applied = try record(activity.action, on: activity.day, at: activity.recordedAt, id: activity.id)
            guard applied == activity.id, activities.last == activity else {
                throw DecodingError.dataCorruptedError(
                    forKey: .activities, in: values, debugDescription: "Invalid activity or undo target"
                )
            }
        }
    }

    @discardableResult
    public mutating func record(
        _ action: Action, on date: Date, at now: Date, id: UUID = UUID(), deviceID: String? = nil
    ) throws -> UUID? {
        if let existing = activities.first(where: { $0.id == id }) {
            guard existing.day == day(date), existing.recordedAt == now, existing.action == action else {
                throw ChallengeError.conflictingActivity
            }
            return id
        }
        guard day(date) >= startDate, day(date) <= day(now) else {
            throw ChallengeError.dateOutsideChallenge
        }
        let target: UUID?
        switch action {
        case .pour(let amount):
            guard amount > 0,
                  !summary(on: date, asOf: now).waterMillilitres.addingReportingOverflow(amount).overflow else {
                throw ChallengeError.invalidWaterAmount
            }
            target = nil
        case .setHabit, .setDiet: target = nil
        case .undoLatestPour:
            guard let last = summary(on: date, asOf: now).activePours.last else { return nil }
            target = last.id
        }
        let record = Activity(id: id, day: day(date), recordedAt: now, action: action, undonePourID: target, deviceID: deviceID)
        if deviceID != nil { try merge([record]) } else { activities.append(record) }
        return record.id
    }

    public var allActivities: [Activity] { activities }

    /// Union immutable events, then derive state. Undo targets are never replayed as
    /// commands: two devices undoing one pour must not remove two different pours.
    public mutating func merge(_ incoming: [Activity]) throws {
        var known = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0) })
        for event in incoming {
            if let existing = known[event.id], existing != event { throw ChallengeError.conflictingActivity }
            known[event.id] = event
        }
        var totals: [Date: Int] = [:]
        let undone = Set(known.values.compactMap(\.undonePourID))
        for event in known.values {
            guard event.day.timeIntervalSince1970.isFinite,
                  event.recordedAt.timeIntervalSince1970.isFinite,
                  day(event.day) == event.day, event.day >= startDate,
                  event.day <= day(event.recordedAt) else { throw ChallengeError.dateOutsideChallenge }
            switch event.action {
            case .pour(let amount):
                guard amount > 0, event.undonePourID == nil else { throw ChallengeError.invalidWaterAmount }
                if !undone.contains(event.id) {
                    let sum = (totals[event.day] ?? 0).addingReportingOverflow(amount)
                    guard !sum.overflow else { throw ChallengeError.invalidWaterAmount }
                    totals[event.day] = sum.partialValue
                }
            case .undoLatestPour:
                guard let target = event.undonePourID, let pour = known[target],
                      case .pour = pour.action, pour.day == event.day else { throw ChallengeError.conflictingActivity }
            case .setHabit, .setDiet:
                guard event.undonePourID == nil else { throw ChallengeError.conflictingActivity }
            }
        }
        activities = known.values.sorted {
            if $0.recordedAt != $1.recordedAt { return $0.recordedAt < $1.recordedAt }
            if $0.deviceID != $1.deviceID { return ($0.deviceID ?? "") < ($1.deviceID ?? "") }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    public func history(on date: Date) -> [Activity] {
        let selected = day(date)
        return activities.filter { $0.day == selected }
    }

    public func summary(on date: Date, asOf now: Date) -> DailySummary {
        let records = history(on: date)
        let undone = Set(records.compactMap(\.undonePourID))
        let pours = records.compactMap { record -> WaterPour? in
            guard case .pour(let amount) = record.action, !undone.contains(record.id) else { return nil }
            return WaterPour(id: record.id, millilitres: amount)
        }
        var completed: Set<Habit> = []
        var diet: DietState = .pending
        for record in records {
            switch record.action {
            case .setHabit(let habit, let value):
                if value { completed.insert(habit) } else { completed.remove(habit) }
            case .setDiet(let value): diet = value
            case .pour, .undoLatestPour: break
            }
        }
        let selected = day(date)
        let today = day(now)
        let allMet = pours.reduce(0) { $0 + $1.millilitres } >= 4_000
            && completed.count == Habit.allCases.count && diet == .clean
        let status: DayStatus
        if selected < startDate { status = .outsideChallenge }
        else if selected > today { status = .future }
        else if allMet { status = .complete }
        else if selected < today { status = .missed }
        else { status = .inProgress }
        return DailySummary(
            interval: calendar.dateInterval(of: .day, for: selected)!,
            activePours: pours, completedHabits: completed, diet: diet, status: status
        )
    }

    public func streaks(asOf now: Date) -> StreakSummary {
        let today = day(now)
        var date = startDate
        var run = 0
        var best = 0
        var current = 0
        var milestones: [Date] = []
        while date <= today {
            if summary(on: date, asOf: now).isComplete {
                run += 1
                best = max(best, run)
                current = run
                if run == 75 { milestones.append(date) }
            } else if date < today {
                run = 0
                current = 0
            }
            // Pending today preserves the sequence ending yesterday.
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        return StreakSummary(current: current, best: best, milestones: milestones)
    }

    /// The calendar every day boundary, reminder and display date uses for a zone.
    public static func calendar(for timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func day(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
}
