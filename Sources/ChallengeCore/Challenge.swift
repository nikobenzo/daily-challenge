import Foundation

public enum ChallengeError: LocalizedError {
    case invalidWaterAmount
    case dateOutsideChallenge
    case conflictingActivity
    case invalidExtraTitle, tooManyExtras, unknownExtra, archivedExtra
    case invalidTarget, invalidSchedule

    public var errorDescription: String? {
        switch self {
        case .invalidWaterAmount: "Water amounts must be positive whole millilitres within the supported total."
        case .dateOutsideChallenge: "Only days from the challenge start through today can be edited."
        case .conflictingActivity: "An activity ID was reused with different content. Nothing was changed."
        case .invalidExtraTitle: "An extra's name must be 1 to 40 characters on one line."
        case .tooManyExtras: "You can have up to \(Challenge.maximumActiveExtras) extras. Archive one to add another."
        case .unknownExtra: "That extra doesn't exist. Nothing was changed."
        case .archivedExtra: "That extra is archived, so it can't be changed for this day."
        case .invalidTarget: "A goal needs a name of 1 to 20 characters on one line, and amounts within their limits. Nothing was changed."
        case .invalidSchedule: "An extra repeats on chosen weekdays or every 1 to 30 days. Nothing was changed."
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

    /// The four labelled slots beside water. A key only identifies a ring and its
    /// `setHabit` or `setDiet` events, so `walk` may be labelled Yoga. Never rename them.
    public enum TargetSlot: String, CaseIterable, Codable, Sendable {
        case workout, walk, diet, bibleReading
    }

    /// The units of an activity's optional amount, each with the amounts it allows.
    public enum TargetUnit: String, CaseIterable, Codable, Sendable {
        case minutes, pages, chapters, kilometres, miles, steps

        public var amounts: ClosedRange<Int> {
            switch self {
            case .minutes: 5...300
            case .pages: 1...500
            case .chapters: 1...50
            case .kilometres: 1...100
            case .miles: 1...60
            case .steps: 1_000...50_000
            }
        }
    }

    /// What a slot is called and, optionally, how much. Display only: the slot is still
    /// completed by its tick (or, for diet, by a clean day).
    public struct Target: Equatable, Sendable {
        public let name: String
        public let amount: Int?
        public let unit: TargetUnit?
        /// A short id from the shared icon list. Nil, or an id this version does not
        /// know, shows the slot's default icon.
        public let icon: String?

        public init(name: String, amount: Int? = nil, unit: TargetUnit? = nil, icon: String? = nil) {
            self.name = name; self.amount = amount; self.unit = unit; self.icon = icon
        }

        /// The rules every client and the server apply: a valid name, an amount and unit
        /// together or neither (diet takes none), the amount in its unit's range, and an
        /// icon id of 1 to 16 lower-case letters.
        public func isValid(for slot: TargetSlot) -> Bool {
            guard Challenge.targetName(name) == name, icon.map(Challenge.isIconID) ?? true else { return false }
            switch (amount, unit) {
            case (nil, nil): return true
            case (let amount?, let unit?): return slot != .diet && unit.amounts.contains(amount)
            default: return false
            }
        }
    }

    /// The daily water goal and the glass the + button pours, in millilitres.
    public struct WaterTarget: Equatable, Sendable {
        public let goal: Int
        public let glass: Int
        public static let goals = 1_000...5_000
        public static let glasses = 50...1_000

        public init(goal: Int, glass: Int) { self.goal = goal; self.glass = glass }

        public var isValid: Bool { Self.goals.contains(goal) && Self.glasses.contains(glass) && glass <= goal }
    }

    /// The targets in force on one challenge day.
    public struct Targets: Equatable, Sendable {
        public var water: WaterTarget
        public var workout: Target
        public var walk: Target
        public var diet: Target
        public var bibleReading: Target

        public init(water: WaterTarget, workout: Target, walk: Target, diet: Target, bibleReading: Target) {
            self.water = water; self.workout = workout; self.walk = walk; self.diet = diet; self.bibleReading = bibleReading
        }

        /// The original five: 4,000 ml in 450 ml glasses, a 45-minute workout, a
        /// 45-minute walk, a clean diet and 10 pages of the Bible. A day without target
        /// events uses these.
        public static let standard = Targets(
            water: WaterTarget(goal: 4_000, glass: 450),
            workout: Target(name: "Workout", amount: 45, unit: .minutes),
            walk: Target(name: "Walk", amount: 45, unit: .minutes),
            diet: Target(name: "Diet"),
            bibleReading: Target(name: "Bible", amount: 10, unit: .pages))

        public subscript(slot: TargetSlot) -> Target {
            get {
                switch slot {
                case .workout: workout
                case .walk: walk
                case .diet: diet
                case .bibleReading: bibleReading
                }
            }
            set {
                switch slot {
                case .workout: workout = newValue
                case .walk: walk = newValue
                case .diet: diet = newValue
                case .bibleReading: bibleReading = newValue
                }
            }
        }

        /// One `setWater` or `setTarget` per value that differs from `base`.
        public func changes(from base: Targets = .standard) -> [Action] {
            var actions: [Action] = []
            if water != base.water { actions.append(.setWater(goal: water.goal, pour: water.glass)) }
            for slot in TargetSlot.allCases where self[slot] != base[slot] {
                let target = self[slot]
                actions.append(.setTarget(slot, name: target.name, amount: target.amount, unit: target.unit, icon: target.icon))
            }
            return actions
        }
    }

    /// How an extra repeats.
    public enum ExtraSchedule: Equatable, Sendable {
        /// A to-do: shown from its first day until the day it is ticked, carried over as
        /// late while open. Every extra is one until it is scheduled.
        case once
        /// Shown on these ISO weekdays, Monday = 1 through Sunday = 7. Never late.
        case weekdays(Set<Int>)
        /// Shown every N days (1 is daily), counted from the day the rule applies from.
        /// Never late.
        case every(Int)

        public static let intervals = 1...30

        /// The rule of a `scheduleExtra` event, or nil when no client accepts it: both
        /// rules, an empty, repeated or out-of-range weekday, or N outside 1 to 30.
        public init?(weekdays: [Int]?, every: Int?) {
            switch (weekdays, every) {
            case (nil, nil): self = .once
            case (let days?, nil):
                guard !days.isEmpty, Set(days).count == days.count, days.allSatisfy((1...7).contains) else { return nil }
                self = .weekdays(Set(days))
            case (nil, let interval?):
                guard Self.intervals.contains(interval) else { return nil }
                self = .every(interval)
            default: return nil
            }
        }

        /// The event that sets this rule for an extra, weekdays in ascending order.
        public func action(for id: UUID) -> Action {
            switch self {
            case .once: .scheduleExtra(id: id)
            case .weekdays(let days): .scheduleExtra(id: id, weekdays: days.sorted())
            case .every(let interval): .scheduleExtra(id: id, every: interval)
            }
        }
    }

    /// Synthesized Codable: each event's `action` is a one-key object named after the
    /// case, with nil values left out. These names and labels are the wire format shared
    /// with the server and every client, so never rename them:
    ///
    ///     {"pour":{"_0":450}}                 {"undoLatestPour":{}}
    ///     {"setHabit":{"_0":"walk","completed":true}}    {"setDiet":{"_0":"clean"}}
    ///     {"defineExtra":{"id":"<UUID>","title":"Stretch"}}
    ///     {"archiveExtra":{"id":"<UUID>"}}    {"setExtra":{"id":"<UUID>","completed":true}}
    ///     {"setTarget":{"_0":"walk","name":"Yoga","amount":30,"unit":"minutes","icon":"yoga"}}
    ///     {"setTarget":{"_0":"diet","name":"No sugar"}}    {"setWater":{"goal":3000,"pour":250}}
    ///     {"scheduleExtra":{"id":"<UUID>","weekdays":[1,2,3,4,5]}}
    ///     {"scheduleExtra":{"id":"<UUID>","every":2}}      {"scheduleExtra":{"id":"<UUID>"}}
    ///
    /// Extras never count toward a complete day. A client that predates a case cannot
    /// decode that event at all, skips it and keeps syncing (see HANDOFF.md), which is
    /// why a schedule is its own kind rather than a key inside `defineExtra`.
    public enum Action: Codable, Equatable, Sendable {
        case pour(Int)
        case undoLatestPour
        case setHabit(Habit, completed: Bool)
        case setDiet(DietState)
        /// Adds an extra, or renames it: the last definition in event order wins.
        case defineExtra(id: UUID, title: String)
        /// Hides an extra from its archive day on, permanently; earlier days keep their ticks.
        case archiveExtra(id: UUID)
        /// Ticks or unticks an extra for the event's day. The earliest ticked day completes
        /// a to-do: shown ticked that day and on no later day.
        case setExtra(id: UUID, completed: Bool)
        /// Sets a slot's name, amount and icon from the event's day on (see `targets(on:)`).
        case setTarget(TargetSlot, name: String, amount: Int? = nil, unit: TargetUnit? = nil, icon: String? = nil)
        /// Sets the daily water goal and the + button's glass from the event's day on.
        case setWater(goal: Int, pour: Int)
        /// Sets how an extra repeats from the event's day on: chosen weekdays, every N
        /// days, or neither for a to-do (see `ExtraSchedule`).
        case scheduleExtra(id: UUID, weekdays: [Int]? = nil, every: Int? = nil)

        /// What recording or merging refuses this action for on its content alone, or nil.
        /// Decoders treat such an event as unreadable, like an unknown kind.
        var contentError: ChallengeError? {
            switch self {
            case .setTarget(let slot, let name, let amount, let unit, let icon):
                Target(name: name, amount: amount, unit: unit, icon: icon).isValid(for: slot) ? nil : .invalidTarget
            case .setWater(let goal, let pour): WaterTarget(goal: goal, glass: pour).isValid ? nil : .invalidTarget
            case .scheduleExtra(_, let weekdays, let every):
                ExtraSchedule(weekdays: weekdays, every: every) == nil ? .invalidSchedule : nil
            case .pour, .undoLatestPour, .setHabit, .setDiet, .defineExtra, .archiveExtra, .setExtra: nil
            }
        }
    }

    /// A personal item beside the five requirements. Never part of `isComplete`. As a
    /// to-do it carries over, day by day, until it is done or archived; scheduled to
    /// repeat, it shows on its scheduled days instead. Everything here is derived from
    /// the extras events (see `allExtras`), so nothing is written at midnight.
    public struct Extra: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let title: String
        /// The first challenge day it can show on: its earliest definition day, or an
        /// earlier day it was ticked on as a to-do.
        public let firstDay: Date
        /// The day its current to-do was done: the earliest ticked day of its latest
        /// one-off period, before any archive. Nil while that is open, or while it repeats.
        public let completedOn: Date?
        /// The first challenge day it is hidden from, or nil while it is active.
        public let archivedFrom: Date?
        public var isArchived: Bool { archivedFrom != nil }
        /// Its latest repeat rule: `.once` unless it has been scheduled.
        public var schedule: ExtraSchedule { periods[periods.count - 1].schedule }
        /// Its repeat rules in day order, each from its `start` until the next one's.
        let periods: [Period]

        struct Period: Equatable, Sendable {
            let start: Date
            /// `start` as a day number (`Challenge.dayNumber`), where "every N" counts from.
            let startNumber: Int
            let schedule: ExtraSchedule
            /// For a to-do: the first day shown (in the first period, `firstDay`), and the
            /// earliest ticked day in the period.
            let shownFrom: Date
            let completedOn: Date?
        }

        /// The repeat rule in force on the challenge day starting at `day`.
        public func schedule(on day: Date) -> ExtraSchedule { period(on: day).schedule }

        private func period(on day: Date) -> Period { periods.last { $0.start <= day } ?? periods[0] }

        /// Whether the challenge day starting at `day`, day number `number`, shows it.
        func isShown(on day: Date, number: Int) -> Bool {
            if let archivedFrom, day >= archivedFrom { return false }
            let period = period(on: day)
            switch period.schedule {
            case .once: return period.shownFrom <= day && (period.completedOn.map { day <= $0 } ?? true)
            case .weekdays(let days): return period.start <= day && days.contains(Challenge.isoWeekday(number))
            case .every(let interval): return period.start <= day && (number - period.startNumber) % interval == 0
            }
        }

        /// Carried over to the day starting at `day`: a to-do shown after its period's first
        /// day. A repeating extra is never late.
        func isLate(on day: Date) -> Bool {
            let period = period(on: day)
            return period.schedule == .once && period.shownFrom < day
        }

        /// Still to do as of the day starting at `day`: active, and repeating or not done.
        func isOpen(asOf day: Date) -> Bool {
            guard !isArchived else { return false }
            let period = period(on: day)
            return period.schedule != .once || (period.completedOn.map { $0 > day } ?? true)
        }
    }

    public static let maximumActiveExtras = 10
    public static let maximumExtraTitleLength = 40
    public static let maximumTargetNameLength = 20
    /// Unicode scalars, the length PostgreSQL's `char_length` counts, so a name every
    /// client accepts is never refused on upload.
    static let maximumTargetNameScalars = 80

    /// The stored form of an extra's name: trimmed, 1 to 40 characters, one line.
    /// Nil when nothing valid remains.
    public static func extraTitle(_ raw: String) -> String? {
        label(raw, maximum: maximumExtraTitleLength)
    }

    /// The stored form of a slot's name: trimmed, 1 to 20 characters (at most 80
    /// Unicode scalars), one line. Nil when nothing valid remains.
    public static func targetName(_ raw: String) -> String? {
        label(raw, maximum: maximumTargetNameLength).flatMap { $0.unicodeScalars.count <= maximumTargetNameScalars ? $0 : nil }
    }

    private static func label(_ raw: String, maximum: Int) -> String? {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...maximum).contains(title.count),
              !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0)
                  || CharacterSet.newlines.contains($0) }) else { return nil }
        return title
    }

    /// An icon id: 1 to 16 lower-case ASCII letters.
    public static func isIconID(_ id: String) -> Bool {
        (1...16).contains(id.unicodeScalars.count) && id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) }
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
            // An out-of-range target or schedule is unreadable, like an unknown kind: sync
            // skips the row and files are refused, so it never fails a merge.
            if action.contentError != nil {
                throw DecodingError.dataCorruptedError(forKey: .action, in: c, debugDescription: "Invalid target or schedule")
            }
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
        /// The day's own water goal: a later change never re-judges an earlier day.
        public var waterComplete: Bool { waterMillilitres >= targets.water.goal }
        public let status: DayStatus
        /// The targets in force on this day.
        public let targets: Targets
        /// The five requirements only. Extras never change it.
        public var isComplete: Bool { status == .complete }
        /// The extras shown for this day, in creation order, and which of them are ticked.
        public let extras: [Extra]
        public let completedExtras: Set<UUID>
        public var extrasDone: Int { completedExtras.count }
        public var extrasTotal: Int { extras.count }
        public var allExtrasDone: Bool { extrasTotal > 0 && extrasDone == extrasTotal }
        /// Carried over: a to-do shown on a day after the first day it appeared, ticked or
        /// not. A repeating extra is never late.
        public func isLate(_ extra: Extra) -> Bool { extra.isLate(on: interval.start) }
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
        case .setTarget, .setWater:
            if let problem = action.contentError { throw problem }
            target = nil
        case .scheduleExtra(let extraID, let weekdays, let every):
            guard let schedule = ExtraSchedule(weekdays: weekdays, every: every) else { throw ChallengeError.invalidSchedule }
            guard let existing = allExtras.first(where: { $0.id == extraID }) else { throw ChallengeError.unknownExtra }
            guard !existing.isArchived else { throw ChallengeError.archivedExtra }
            if existing.schedule(on: day(date)) == schedule { return nil }
            // A repeating extra is open, so scheduling a finished to-do takes a place.
            if !existing.isOpen(asOf: day(now)) {
                var trial = self
                trial.activities.append(Activity(id: id, day: day(date), recordedAt: now, action: action, undonePourID: nil))
                guard trial.openExtras(asOf: now).count <= Self.maximumActiveExtras else { throw ChallengeError.tooManyExtras }
            }
            target = nil
        case .defineExtra(let extraID, let title):
            guard Self.extraTitle(title) == title else { throw ChallengeError.invalidExtraTitle }
            let catalog = allExtras
            if let existing = catalog.first(where: { $0.id == extraID }) {
                guard !existing.isArchived else { throw ChallengeError.archivedExtra }
            } else {
                guard openExtras(asOf: now).count < Self.maximumActiveExtras else {
                    throw ChallengeError.tooManyExtras
                }
            }
            target = nil
        case .archiveExtra(let extraID):
            guard let existing = allExtras.first(where: { $0.id == extraID }) else { throw ChallengeError.unknownExtra }
            if existing.isArchived { return nil }
            target = nil
        case .setExtra(let extraID, _):
            guard let existing = allExtras.first(where: { $0.id == extraID }) else { throw ChallengeError.unknownExtra }
            guard existing.archivedFrom.map({ $0 > day(date) }) ?? true else { throw ChallengeError.archivedExtra }
            target = nil
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
        // Order-independent on purpose: a device may tick an extra before it hears of
        // another device's archive, or with a clock behind the definition's. Only an
        // extra never defined anywhere in the union is invalid.
        let definedExtras = Set(known.values.compactMap { event -> UUID? in
            if case .defineExtra(let id, _) = event.action { id } else { nil }
        })
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
            case .defineExtra(_, let title):
                guard event.undonePourID == nil else { throw ChallengeError.conflictingActivity }
                guard Self.extraTitle(title) == title else { throw ChallengeError.invalidExtraTitle }
            case .archiveExtra(let extraID), .setExtra(let extraID, _):
                guard event.undonePourID == nil else { throw ChallengeError.conflictingActivity }
                guard definedExtras.contains(extraID) else { throw ChallengeError.unknownExtra }
            case .setTarget, .setWater:
                guard event.undonePourID == nil else { throw ChallengeError.conflictingActivity }
                if let problem = event.action.contentError { throw problem }
            case .scheduleExtra(let extraID, _, _):
                guard event.undonePourID == nil else { throw ChallengeError.conflictingActivity }
                if let problem = event.action.contentError { throw problem }
                guard definedExtras.contains(extraID) else { throw ChallengeError.unknownExtra }
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
        var ticked: Set<UUID> = []
        for record in records {
            switch record.action {
            case .setHabit(let habit, let value):
                if value { completed.insert(habit) } else { completed.remove(habit) }
            case .setDiet(let value): diet = value
            case .setExtra(let id, let value):
                if value { ticked.insert(id) } else { ticked.remove(id) }
            case .pour, .undoLatestPour, .defineExtra, .archiveExtra, .setTarget, .setWater, .scheduleExtra: break
            }
        }
        let selected = day(date)
        let shown = extras(asOf: selected)
        let today = day(now)
        let targets = targets(on: selected)
        let allMet = pours.reduce(0) { $0 + $1.millilitres } >= targets.water.goal
            && completed.count == Habit.allCases.count && diet == .clean
        let status: DayStatus
        if selected < startDate { status = .outsideChallenge }
        else if selected > today { status = .future }
        else if allMet { status = .complete }
        else if selected < today { status = .missed }
        else { status = .inProgress }
        return DailySummary(
            interval: calendar.dateInterval(of: .day, for: selected)!,
            activePours: pours, completedHabits: completed, diet: diet, status: status, targets: targets,
            extras: shown, completedExtras: ticked.intersection(shown.map(\.id))
        )
    }

    /// The targets in force on the day of `date`: the standard five, changed by every
    /// `setTarget` and `setWater` dated that day or earlier. For each slot the latest
    /// dated change wins, then the last in event order, so two devices changing one slot
    /// on one day resolve like conflicting habit edits, and changes to different slots
    /// both survive. A change never re-judges the days before it.
    public func targets(on date: Date) -> Targets {
        let selected = day(date)
        var targets = Targets.standard
        var waterDay: Date?
        var slotDays: [TargetSlot: Date] = [:]
        for activity in activities where activity.day <= selected {
            switch activity.action {
            case .setTarget(let slot, let name, let amount, let unit, let icon):
                guard slotDays[slot].map({ $0 <= activity.day }) ?? true else { continue }
                slotDays[slot] = activity.day
                targets[slot] = Target(name: name, amount: amount, unit: unit, icon: icon)
            case .setWater(let goal, let pour):
                guard waterDay.map({ $0 <= activity.day }) ?? true else { continue }
                waterDay = activity.day
                targets.water = WaterTarget(goal: goal, glass: pour)
            default: break
            }
        }
        return targets
    }

    /// Every extra ever defined, archived ones included, in creation order (the first
    /// definition's place in event order). Order-independent like `merge`: the earliest
    /// definition day, the earliest archive day and each day's last tick in event order.
    /// `firstDay` is the earliest definition day, or the completion day when that is
    /// earlier (a tick synced from a device with a slower clock, or made on an earlier
    /// day while every extra still showed on every day).
    ///
    /// Each repeat rule applies from its event's day, or from the definition day when
    /// that is later; on one day the latest dated rule wins, then the last in event
    /// order. A to-do rule after a to-do period changes nothing, and any other change
    /// starts a period: a to-do period is completed only by a tick inside it (the first
    /// period also by an earlier tick, as above), so a repeating extra switched back to
    /// a to-do is a fresh open to-do from that day.
    public var allExtras: [Extra] {
        var order: [UUID] = []
        var titles: [UUID: String] = [:]
        var defined: [UUID: Date] = [:]
        var archived: [UUID: Date] = [:]
        var ticks: [UUID: [Date: Bool]] = [:]
        var schedules: [UUID: [(day: Date, schedule: ExtraSchedule)]] = [:]
        for activity in activities {
            switch activity.action {
            case .defineExtra(let id, let title):
                if titles[id] == nil { order.append(id) }
                titles[id] = title
                defined[id] = min(defined[id] ?? activity.day, activity.day)
            case .archiveExtra(let id):
                archived[id] = min(archived[id] ?? activity.day, activity.day)
            case .setExtra(let id, let value):
                ticks[id, default: [:]][activity.day] = value
            case .scheduleExtra(let id, let weekdays, let every):
                if let schedule = ExtraSchedule(weekdays: weekdays, every: every) {
                    schedules[id, default: []].append((activity.day, schedule))
                }
            default: break
            }
        }
        return order.compactMap { id in
            guard let title = titles[id], let definedOn = defined[id] else { return nil }
            // A tick from its archive day on is kept as history but never completes it.
            let ticked = (ticks[id] ?? [:]).filter { tick in
                tick.value && (archived[id].map { tick.key < $0 } ?? true)
            }.keys
            var changes: [Date: (dated: Date, schedule: ExtraSchedule)] = [:]
            for change in schedules[id] ?? [] {
                let from = max(change.day, definedOn)
                if let current = changes[from], current.dated > change.day { continue }
                changes[from] = (change.day, change.schedule)
            }
            var starts: [(day: Date, schedule: ExtraSchedule)] = changes.keys.sorted().map { ($0, changes[$0]!.schedule) }
            if starts.first?.day != definedOn { starts.insert((definedOn, .once), at: 0) }
            starts = starts.enumerated().filter { index, start in
                index == 0 || start.schedule != .once || starts[index - 1].schedule != .once
            }.map(\.element)
            let periods = starts.enumerated().map { index, start -> Extra.Period in
                let end = index + 1 < starts.count ? starts[index + 1].day : nil
                guard start.schedule == .once else {
                    return Extra.Period(start: start.day, startNumber: dayNumber(start.day), schedule: start.schedule,
                                        shownFrom: start.day, completedOn: nil)
                }
                let completedOn = ticked.filter { day in
                    (index == 0 || day >= start.day) && (end.map { day < $0 } ?? true)
                }.min()
                let shownFrom = index == 0 ? min(start.day, completedOn ?? start.day) : start.day
                return Extra.Period(start: start.day, startNumber: dayNumber(start.day), schedule: .once,
                                    shownFrom: shownFrom, completedOn: completedOn)
            }
            let latest = periods[periods.count - 1]
            return Extra(id: id, title: title, firstDay: periods[0].shownFrom,
                         completedOn: latest.schedule == .once ? latest.completedOn : nil,
                         archivedFrom: archived[id], periods: periods)
        }
    }

    /// The extras shown for the day of `date`, in creation order, until the day each is
    /// archived: a to-do from its first day through its completion day, carried over
    /// while open; a repeating extra on its scheduled days.
    public func extras(asOf date: Date) -> [Extra] {
        let selected = day(date)
        let number = dayNumber(selected)
        return allExtras.filter { $0.isShown(on: selected, number: number) }
    }

    /// The extras still to do as of `date`, in creation order: active, and repeating on
    /// that day or a to-do not completed on or before it. Manage extras lists them and
    /// the cap counts them, so ticking a to-do frees its place at once.
    public func openExtras(asOf date: Date) -> [Extra] {
        let selected = day(date)
        return allExtras.filter { $0.isOpen(asOf: selected) }
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

    /// The calendar date of `date` in the challenge's zone as days since 1970-01-01,
    /// so day counts never depend on how long a day is.
    func dayNumber(_ date: Date) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let month = parts.month!, year = parts.year! - (month <= 2 ? 1 : 0)
        let era = (year >= 0 ? year : year - 399) / 400
        let yearOfEra = year - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + parts.day! - 1
        return era * 146_097 + yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear - 719_468
    }

    /// The ISO weekday (Monday = 1 through Sunday = 7) of a day number; day 0 was a Thursday.
    static func isoWeekday(_ number: Int) -> Int { ((number % 7) + 10) % 7 + 1 }
}
