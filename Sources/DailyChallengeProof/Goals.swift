import ChallengeCore
import Foundation

/// How the day's targets read and look on the Mac: names, amounts, icons and the setup
/// presets (docs/tracker-interface.md#custom-daily-targets-and-recurring-extras-shared-rules).
/// The rules themselves, limits included, live in `Challenge.Targets`.
enum Goals {
    typealias Slot = Challenge.TargetSlot
    typealias Unit = Challenge.TargetUnit

    /// The shared icon ids and their SF Symbols. An id this version does not know shows
    /// the slot's default, so the list can grow.
    static let symbols: [String: String] = [
        "dumbbell": "dumbbell", "walk": "figure.walk", "run": "figure.run", "bike": "figure.outdoor.cycle",
        "swim": "figure.pool.swim", "yoga": "figure.yoga", "pilates": "figure.pilates",
        "stretch": "figure.flexibility", "book": "book.closed", "bible": "book", "headphones": "headphones",
        "study": "graduationcap", "leaf": "leaf"
    ]
    /// The icons a custom goal can pick from, in picker order.
    static let iconChoices = ["dumbbell", "walk", "run", "bike", "swim", "yoga", "pilates", "stretch",
                              "book", "bible", "headphones", "study"]

    static func defaultIcon(_ slot: Slot) -> String {
        switch slot {
        case .workout: "dumbbell"
        case .walk: "walk"
        case .diet: "leaf"
        case .bibleReading: "bible"
        }
    }

    static func symbol(_ slot: Slot, _ target: Challenge.Target) -> String {
        target.icon.flatMap { symbols[$0] } ?? symbols[defaultIcon(slot)]!
    }

    static func symbol(_ habit: Challenge.Habit, in targets: Challenge.Targets) -> String {
        symbol(slot(habit), targets[slot(habit)])
    }

    static func slot(_ habit: Challenge.Habit) -> Slot {
        switch habit {
        case .workout: .workout
        case .walk: .walk
        case .bibleReading: .bibleReading
        }
    }

    /// What the setup and Daily goals rows call each slot when it is not named.
    static func role(_ slot: Slot) -> String {
        switch slot {
        case .workout: "First activity"
        case .walk: "Second activity"
        case .diet: "Diet"
        case .bibleReading: "Reading"
        }
    }

    // MARK: Words

    /// "45 min", "10 pages", "1 chapter", "10,000 steps"; nil without an amount.
    static func amount(_ target: Challenge.Target, spoken: Bool = false) -> String? {
        guard let amount = target.amount, let unit = target.unit else { return nil }
        return "\(amount.formatted()) \(unitName(unit, amount: amount, spoken: spoken))"
    }

    static func unitName(_ unit: Unit, amount: Int, spoken: Bool = false) -> String {
        let one = amount == 1
        switch unit {
        case .minutes: return spoken ? (one ? "minute" : "minutes") : "min"
        case .pages: return one ? "page" : "pages"
        case .chapters: return one ? "chapter" : "chapters"
        case .kilometres: return spoken ? (one ? "kilometre" : "kilometres") : "km"
        case .miles: return one ? "mile" : "miles"
        case .steps: return one ? "step" : "steps"
        }
    }

    /// The units picker's words.
    static func unitTitle(_ unit: Unit) -> String {
        switch unit {
        case .minutes: "minutes"
        case .pages: "pages"
        case .chapters: "chapters"
        case .kilometres: "km"
        case .miles: "miles"
        case .steps: "steps"
        }
    }

    /// The row and tooltip detail: "45 min · home or gym" for the standard workout,
    /// "Your own rules" for diet, otherwise the amount, or "Tick it when it's done".
    static func detail(_ slot: Slot, _ target: Challenge.Target, spoken: Bool = false) -> String {
        if slot == .diet { return "Your own rules" }
        guard let amount = amount(target, spoken: spoken) else { return "No set amount" }
        return target == Challenge.Targets.standard.workout ? "\(amount) · home or gym" : amount
    }

    /// "Walk, 45 minutes" for VoiceOver and tooltips: always the full name.
    static func spoken(_ slot: Slot, _ target: Challenge.Target) -> String {
        "\(target.name), \(detail(slot, target, spoken: true))"
    }

    /// VoiceOver's diet ring: "Clean diet, your own rules", or "No sugar, your own rules".
    static func dietLabel(_ target: Challenge.Target) -> String {
        "\(target == Challenge.Targets.standard.diet ? "Clean diet" : target.name), your own rules"
    }

    /// "4,000 ml · 450 ml glass".
    static func water(_ water: Challenge.WaterTarget) -> String {
        "\(water.goal.formatted()) ml · \(water.glass.formatted()) ml glass"
    }

    /// "Yoga · 30 min" in the Activity audit and the welcome window.
    static func summary(_ slot: Slot, _ target: Challenge.Target) -> String {
        amount(target).map { "\(target.name) · \($0)" } ?? target.name
    }

    /// The welcome window's last step and celebration: "3,000 ml of water, Gym 45 min,
    /// Yoga 30 min, No sugar and Audiobook 20 min". The standard five read as before.
    static func sentence(_ targets: Challenge.Targets) -> String {
        if targets == .standard {
            return "4 litres of water, a 45-minute workout, a 45-minute walk, a clean diet and 10 Bible pages"
        }
        let parts = ["\(targets.water.goal.formatted()) ml of water"]
            + [Slot.workout, .walk, .diet, .bibleReading].map { slot in
                let target = targets[slot]
                return amount(target).map { "\(target.name) \($0)" } ?? target.name
            }
        return parts.dropLast().joined(separator: ", ") + " and " + parts.last!
    }

    // MARK: Presets

    struct Preset: Identifiable, Equatable {
        let name: String
        let icon: String
        let amount: Int?
        let unit: Unit?
        var id: String { name }
        var target: Challenge.Target { Challenge.Target(name: name, amount: amount, unit: unit, icon: icon) }
    }

    /// Section 4.2 of the plan. The standard target of each slot is its first preset and
    /// writes no icon, so choosing it again records the standard five exactly.
    static func presets(_ slot: Slot) -> [Preset] {
        func p(_ name: String, _ icon: String, _ amount: Int? = nil, _ unit: Unit? = nil) -> Preset {
            Preset(name: name, icon: icon, amount: amount, unit: unit)
        }
        switch slot {
        case .workout:
            return [p("Workout", "dumbbell", 45, .minutes), p("Gym", "dumbbell", 45, .minutes), p("Run", "run", 30, .minutes),
                    p("Cycle", "bike", 45, .minutes), p("Swim", "swim", 30, .minutes), p("Yoga", "yoga", 30, .minutes),
                    p("Pilates", "pilates", 30, .minutes), p("HIIT", "dumbbell", 20, .minutes)]
        case .walk:
            return [p("Walk", "walk", 45, .minutes), p("Yoga", "yoga", 30, .minutes), p("Pilates", "pilates", 30, .minutes),
                    p("Stretching", "stretch", 15, .minutes), p("Run", "run", 30, .minutes), p("Cycle", "bike", 45, .minutes),
                    p("Steps", "walk", 10_000, .steps)]
        case .bibleReading:
            return [p("Bible", "bible", 10, .pages), p("Book", "book", 10, .pages), p("Audiobook", "headphones", 20, .minutes),
                    p("Devotional", "bible", 1, .chapters), p("Study", "study", 30, .minutes)]
        case .diet:
            return [p("Diet", "leaf"), p("Clean eating", "leaf"), p("No sugar", "leaf"), p("No alcohol", "leaf")]
        }
    }

    /// The target a preset sets: the slot's standard one for its first preset, so picking
    /// it records nothing new; otherwise the preset's name, icon and amount.
    static func target(_ preset: Preset, for slot: Slot) -> Challenge.Target {
        let standard = Challenge.Targets.standard[slot]
        if preset.name == standard.name { return standard }
        return slot == .diet ? Challenge.Target(name: preset.name) : preset.target
    }

    static let glasses = [250, 330, 450, 500, 750]

    /// The suggested amount for a unit when someone first picks it.
    static func suggestedAmount(_ unit: Unit) -> Int {
        switch unit {
        case .minutes: 30
        case .pages: 10
        case .chapters: 1
        case .kilometres: 5
        case .miles: 3
        case .steps: 10_000
        }
    }

    /// One stepper press: 5 minutes, 1 page or chapter, 1 km or mile, 500 steps.
    static func step(_ unit: Unit) -> Int {
        switch unit {
        case .minutes: 5
        case .steps: 500
        case .pages, .chapters, .kilometres, .miles: 1
        }
    }

    /// The limit a unit's amount must stay within, in words: "5 to 300 minutes".
    static func range(_ unit: Unit) -> String {
        let range = unit.amounts
        return "\(range.lowerBound.formatted()) to \(range.upperBound.formatted()) \(unitName(unit, amount: 2, spoken: true))"
    }

    /// Why a typed name can't be saved, or nil when it can.
    static func nameProblem(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Enter a name." }
        if trimmed.count > Challenge.maximumTargetNameLength {
            return "Use \(Challenge.maximumTargetNameLength) characters or fewer (\(trimmed.count) now)."
        }
        return Challenge.targetName(raw) == nil ? "Use one line of ordinary text." : nil
    }

    /// Why a water goal or glass can't be saved, or nil when it can.
    static func waterProblem(_ water: Challenge.WaterTarget) -> String? {
        let goals = Challenge.WaterTarget.goals, glasses = Challenge.WaterTarget.glasses
        if !goals.contains(water.goal) {
            return "The daily goal must be \(goals.lowerBound.formatted()) to \(goals.upperBound.formatted()) ml."
        }
        if !glasses.contains(water.glass) {
            return "A glass must be \(glasses.lowerBound.formatted()) to \(glasses.upperBound.formatted()) ml."
        }
        return water.glass > water.goal ? "A glass can't be more than the daily goal." : nil
    }
}

/// How an extra's repeat rule reads: captions in Manage extras and Today, phrases in the
/// Activity audit and VoiceOver.
enum ExtraRepeat {
    static let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    static let weekdayInitials = ["M", "T", "W", "T", "F", "S", "S"]

    /// "Once", "Every day", "Weekdays", "Weekends", "Sundays", "Mon, Wed, Fri", "Every 2 days".
    static func caption(_ schedule: Challenge.ExtraSchedule) -> String {
        switch schedule {
        case .once: return "Once"
        case .every(1): return "Every day"
        case .every(let days): return "Every \(days) days"
        case .weekdays(let days):
            if days.count == 7 { return "Every day" }
            if days == [1, 2, 3, 4, 5] { return "Weekdays" }
            if days == [6, 7] { return "Weekends" }
            if days.count == 1, let day = days.first { return weekdayNames[day - 1] + "s" }
            return days.sorted().map { String(weekdayNames[$0 - 1].prefix(3)) }.joined(separator: ", ")
        }
    }

    /// "every day", "on weekdays", "on Sundays", "on Mon, Wed, Fri", "every 2 days".
    static func phrase(_ schedule: Challenge.ExtraSchedule) -> String {
        switch schedule {
        case .once: return "once"
        case .every: return caption(schedule).lowercased()
        case .weekdays(let days):
            let caption = caption(schedule)
            if days.count == 7 { return "every day" }
            return "on " + (days == [1, 2, 3, 4, 5] || days == [6, 7] ? caption.lowercased() : caption)
        }
    }

    /// Today's lower-case row caption beside a repeating extra ("every day", "weekdays",
    /// "Sundays"); nil for a to-do.
    static func rowCaption(_ schedule: Challenge.ExtraSchedule) -> String? {
        switch schedule {
        case .once: nil
        case .weekdays(let days) where days != [1, 2, 3, 4, 5] && days != [6, 7] && days.count != 7: caption(schedule)
        default: caption(schedule).lowercased()
        }
    }
}
