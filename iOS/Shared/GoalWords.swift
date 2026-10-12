import ChallengeCore
import Foundation

/// How the iPhone app and its widgets show a day's targets and an extra's repeat rule:
/// slot titles, icons, amounts, and the setup presets. Everything here is display only;
/// the rules live in `ChallengeCore`.
enum GoalWords {
    /// The shared icon ids (stored in `setTarget`) and their SF Symbols. An id that is not
    /// listed, or none, shows the slot's own icon, so the list can grow later.
    static let icons: [(id: String, symbol: String, name: String)] = [
        ("dumbbell", "dumbbell", "Weights"),
        ("walk", "figure.walk", "Walk"),
        ("run", "figure.run", "Run"),
        ("bike", "figure.outdoor.cycle", "Cycle"),
        ("swim", "figure.pool.swim", "Swim"),
        ("yoga", "figure.yoga", "Yoga"),
        ("pilates", "figure.pilates", "Pilates"),
        ("stretch", "figure.flexibility", "Stretch"),
        ("book", "book", "Book"),
        ("bible", "book.closed", "Bible"),
        ("headphones", "headphones", "Headphones"),
        ("study", "graduationcap", "Study"),
        ("leaf", "leaf", "Leaf"),
    ]

    /// The slot's icon when its target names none (or one this version does not know).
    static func defaultSymbol(_ slot: Challenge.TargetSlot) -> String {
        switch slot {
        case .workout: "dumbbell"
        case .walk: "figure.walk"
        case .diet: "leaf"
        case .bibleReading: "book"
        }
    }

    static func symbol(_ slot: Challenge.TargetSlot, _ target: Challenge.Target) -> String {
        target.icon.flatMap { id in icons.first { $0.id == id }?.symbol } ?? defaultSymbol(slot)
    }

    static func symbol(_ habit: Challenge.Habit, in targets: Challenge.Targets) -> String {
        symbol(slot(habit), targets[slot(habit)])
    }

    static func slot(_ habit: Challenge.Habit) -> Challenge.TargetSlot {
        switch habit {
        case .workout: .workout
        case .walk: .walk
        case .bibleReading: .bibleReading
        }
    }

    /// What each slot is in the editors, whatever it is called.
    static func role(_ slot: Challenge.TargetSlot) -> String {
        switch slot {
        case .workout: "First activity"
        case .walk: "Second activity"
        case .diet: "Diet"
        case .bibleReading: "Reading"
        }
    }

    // MARK: Amounts

    /// "45 min", "10 pages", "1 chapter", "5 km", "10,000 steps"; nil without an amount.
    static func amount(_ target: Challenge.Target) -> String? {
        guard let amount = target.amount, let unit = target.unit else { return nil }
        return "\(amount.formatted()) \(shortUnit(unit, amount))"
    }

    /// "45 minutes", "5 kilometres": the amount as VoiceOver reads it.
    static func spokenAmount(_ target: Challenge.Target) -> String? {
        guard let amount = target.amount, let unit = target.unit else { return nil }
        return "\(amount.formatted()) \(unitName(unit, amount))"
    }

    static func shortUnit(_ unit: Challenge.TargetUnit, _ amount: Int) -> String {
        switch unit {
        case .minutes: "min"
        case .kilometres: "km"
        default: unitName(unit, amount)
        }
    }

    static func unitName(_ unit: Challenge.TargetUnit, _ amount: Int) -> String {
        let one = amount == 1
        return switch unit {
        case .minutes: one ? "minute" : "minutes"
        case .pages: one ? "page" : "pages"
        case .chapters: one ? "chapter" : "chapters"
        case .kilometres: one ? "kilometre" : "kilometres"
        case .miles: one ? "mile" : "miles"
        case .steps: one ? "step" : "steps"
        }
    }

    /// The step the editor's minus and plus buttons move an amount by.
    static func step(_ unit: Challenge.TargetUnit) -> Int {
        switch unit {
        case .minutes: 5
        case .steps: 500
        default: 1
        }
    }

    /// A slot's detail under its name: "45 min · home or gym" for the standard workout,
    /// "Your own rules" for diet, otherwise the amount, or "Tick it when it's done".
    static func detail(_ slot: Challenge.TargetSlot, _ target: Challenge.Target) -> String {
        if slot == .diet { return "Your own rules" }
        if slot == .workout, target == Challenge.Targets.standard.workout { return "45 min · home or gym" }
        return amount(target) ?? "Tick it when it's done"
    }

    /// The diet slot as VoiceOver names it: "Clean diet" for the standard target.
    static func dietName(_ target: Challenge.Target) -> String {
        target == Challenge.Targets.standard.diet ? "Clean diet" : target.name
    }

    /// "Yoga, 30 minutes" or "No sugar, your own rules": a slot as VoiceOver reads it.
    static func spoken(_ slot: Challenge.TargetSlot, _ target: Challenge.Target) -> String {
        if slot == .diet { return "\(dietName(target)), your own rules" }
        if slot == .workout, target == Challenge.Targets.standard.workout { return "Workout, 45 minutes, home or gym" }
        return [target.name, spokenAmount(target)].compactMap { $0 }.joined(separator: ", ")
    }

    /// "4,000 ml · 450 ml glass".
    static func water(_ water: Challenge.WaterTarget) -> String {
        "\(water.goal.formatted()) ml · \(water.glass.formatted()) ml glass"
    }

    /// "4 L", "2.5 L", "3.25 L".
    static func litres(_ millilitres: Int) -> String {
        (Double(millilitres) / 1_000).formatted(.number.precision(.fractionLength(0...2))) + " L"
    }

    // MARK: Presets

    struct Preset: Identifiable, Equatable {
        let name: String
        let amount: Int?
        let unit: Challenge.TargetUnit?
        /// Nil for the slot's standard preset, so choosing it again records nothing new.
        let icon: String?
        var id: String { name }
        var target: Challenge.Target { Challenge.Target(name: name, amount: amount, unit: unit, icon: icon) }
    }

    static func presets(_ slot: Challenge.TargetSlot) -> [Preset] {
        switch slot {
        case .workout: [
            Preset(name: "Workout", amount: 45, unit: .minutes, icon: nil),
            Preset(name: "Gym", amount: 45, unit: .minutes, icon: "dumbbell"),
            Preset(name: "Run", amount: 30, unit: .minutes, icon: "run"),
            Preset(name: "Cycle", amount: 45, unit: .minutes, icon: "bike"),
            Preset(name: "Swim", amount: 30, unit: .minutes, icon: "swim"),
            Preset(name: "Yoga", amount: 30, unit: .minutes, icon: "yoga"),
            Preset(name: "Pilates", amount: 30, unit: .minutes, icon: "pilates"),
            Preset(name: "HIIT", amount: 20, unit: .minutes, icon: "dumbbell"),
        ]
        case .walk: [
            Preset(name: "Walk", amount: 45, unit: .minutes, icon: nil),
            Preset(name: "Yoga", amount: 30, unit: .minutes, icon: "yoga"),
            Preset(name: "Pilates", amount: 30, unit: .minutes, icon: "pilates"),
            Preset(name: "Stretching", amount: 15, unit: .minutes, icon: "stretch"),
            Preset(name: "Run", amount: 30, unit: .minutes, icon: "run"),
            Preset(name: "Cycle", amount: 45, unit: .minutes, icon: "bike"),
            Preset(name: "Steps", amount: 10_000, unit: .steps, icon: "walk"),
        ]
        case .bibleReading: [
            Preset(name: "Bible", amount: 10, unit: .pages, icon: nil),
            Preset(name: "Book", amount: 10, unit: .pages, icon: "book"),
            Preset(name: "Audiobook", amount: 20, unit: .minutes, icon: "headphones"),
            Preset(name: "Devotional", amount: 1, unit: .chapters, icon: "bible"),
            Preset(name: "Study", amount: 30, unit: .minutes, icon: "study"),
        ]
        case .diet: ["Diet", "Clean eating", "No sugar", "No alcohol"].map {
            Preset(name: $0, amount: nil, unit: nil, icon: nil)
        }
        }
    }

    static let glassPresets = [250, 330, 450, 500, 750]

    // MARK: Extras

    /// "every day", "weekdays", "weekends", "Sundays", "Mon, Wed, Fri", "every 2 days";
    /// nil for a to-do. The ordinary secondary caption beside a repeating extra.
    static func repeatCaption(_ schedule: Challenge.ExtraSchedule) -> String? {
        switch schedule {
        case .once: return nil
        case .every(1): return "every day"
        case .every(let interval): return "every \(interval) days"
        case .weekdays(let days):
            if days == Set(1...7) { return "every day" }
            if days == Set(1...5) { return "weekdays" }
            if days == [6, 7] { return "weekends" }
            if days.count == 1, let day = days.first { return weekdayNames[day - 1] + "s" }
            return days.sorted().map { shortWeekdayNames[$0 - 1] }.joined(separator: ", ")
        }
    }

    /// "every day", "on weekdays", "at weekends", "on Sundays", "on Mon, Wed", "every 2 days";
    /// nil for a to-do.
    static func repeatPhrase(_ schedule: Challenge.ExtraSchedule) -> String? {
        guard let caption = repeatCaption(schedule) else { return nil }
        if caption.hasPrefix("every") { return caption }
        return caption == "weekends" ? "at weekends" : "on \(caption)"
    }

    /// "Once" for a to-do, otherwise the caption with a capital: what Manage extras shows.
    static func repeatTitle(_ schedule: Challenge.ExtraSchedule) -> String {
        guard let caption = repeatCaption(schedule) else { return "Once" }
        return caption.prefix(1).uppercased() + caption.dropFirst()
    }

    /// ISO order, Monday = 1.
    static let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    static let shortWeekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
}
