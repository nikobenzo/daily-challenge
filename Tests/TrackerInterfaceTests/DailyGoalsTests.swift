import AppKit
import ChallengeCore
import SwiftUI
import Testing
@testable import ChallengeSyncKit
@testable import DailyChallengeProof

/// Custom daily goals and repeating extras on the Mac (phases P2, P4 and P5): the day's
/// targets on Today, History and the jug, setup's rows and editors, Account › Daily goals,
/// the Activity audit, the welcome window's text and the repeat picker. Every fixture is
/// a temporary directory with a synthetic account; nothing touches real data or a server.
/// With `DAILY_CHALLENGE_SNAPSHOT_DIR` set, each surface is written there in Light and Dark.
@Suite(.serialized) @MainActor
struct DailyGoalsTests {
    static let now = ISO8601DateFormatter().date(from: "2026-10-12T12:00:00Z")!
    static let london = TimeZone(identifier: "Europe/London")!

    /// Gym 45 min, Yoga 30 min, No sugar, Audiobook 20 min, 3,000 ml in 330 ml glasses.
    static let custom: Challenge.Targets = {
        var targets = Challenge.Targets.standard
        targets.water = Challenge.WaterTarget(goal: 3_000, glass: 330)
        targets.workout = Challenge.Target(name: "Gym", amount: 45, unit: .minutes, icon: "dumbbell")
        targets.walk = Challenge.Target(name: "Yoga", amount: 30, unit: .minutes, icon: "yoga")
        targets.diet = Challenge.Target(name: "No sugar")
        targets.bibleReading = Challenge.Target(name: "Audiobook", amount: 20, unit: .minutes, icon: "headphones")
        return targets
    }()

    private func withModel(_ body: (TrackerModel, ProofModel, AppAppearance) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "daily-goals-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let previous = NSApplication.shared.appearance
        defer {
            NSApplication.shared.appearance = previous
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let owner = UUID()
        let model = TrackerModel(directory: directory, clock: { Self.now })
        model.activate(ownerID: owner)
        try body(model, ProofModel(fixtureOwnerID: owner, directory: directory), AppAppearance(defaults: defaults))
    }

    /// Hosts `content` in a never-shown borderless window at its fitting size and returns
    /// that size; with the snapshot directory set, writes `<name>-<light|dark>.png`.
    @discardableResult
    static func render<Content: View>(_ content: Content, name: String, width: CGFloat? = 420) throws -> CGSize {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var fitted = CGSize.zero
        for dark in [false, true] {
            let host = NSHostingView(rootView: content
                .frame(width: width)
                .environment(\.trackerLiquidGlassOverride, false)
                .environment(\.trackerReduceMotionOverride, true)
                .environment(\.colorScheme, dark ? .dark : .light))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width ?? 420, height: 640), styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = host.appearance
            window.contentView = host
            defer { window.close() }
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            fitted = host.fittingSize
            window.setContentSize(fitted)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            window.displayIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            if let output = ProcessInfo.processInfo.environment["DAILY_CHALLENGE_SNAPSHOT_DIR"] {
                let directory = URL(fileURLWithPath: output)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            }
        }
        return fitted
    }

    // MARK: P2: each day's targets everywhere

    @Test func todayHistoryAndTheJugFollowTheDaysTargets() throws {
        try withModel { model, auth, appearance in
            let start = Self.now.addingTimeInterval(-86_400)
            model.startChallenge(on: start, timeZone: Self.london)
            // Yesterday keeps the standard five; today's change applies from today on.
            #expect(model.setTargets(Self.custom) == nil)
            model.addWater()
            #expect(model.summary?.waterMillilitres == 330, "+ pours today's glass")
            for _ in 0..<9 { model.addWater() }
            #expect(model.summary?.waterMillilitres == 3_300)
            #expect(model.summary?.waterComplete == true, "3,300 ml meets a 3,000 ml goal")
            model.toggle(.walk)
            model.setDiet(.clean)
            #expect(model.summary?.targets == Self.custom)
            let yesterday = try #require(model.challenge?.summary(on: start, asOf: Self.now))
            #expect(yesterday.targets == .standard, "Earlier days keep the goals they had")
            try Self.render(TrackerPopup(model: model, auth: auth, appearance: appearance), name: "goals-today")
            model.selectHistoryDay(Self.now)
            try Self.render(TrackerPopup(model: model, auth: auth, appearance: appearance, section: .history),
                            name: "goals-history")
            model.selectHistoryDay(start)
            try Self.render(TrackerPopup(model: model, auth: auth, appearance: appearance, section: .history),
                            name: "goals-history-before-change")
            model.showToday()
        }
    }

    @Test func wordsFollowTheTargets() {
        let walk = Self.custom.walk
        #expect(Goals.amount(walk) == "30 min")
        #expect(Goals.amount(walk, spoken: true) == "30 minutes")
        #expect(Goals.spoken(.walk, walk) == "Yoga, 30 minutes")
        #expect(Goals.detail(.workout, Challenge.Targets.standard.workout) == "45 min · home or gym")
        #expect(Goals.detail(.diet, Self.custom.diet) == "Your own rules")
        #expect(Goals.dietLabel(Challenge.Targets.standard.diet) == "Clean diet, your own rules")
        #expect(Goals.dietLabel(Self.custom.diet) == "No sugar, your own rules")
        #expect(Goals.amount(Challenge.Target(name: "Devotional", amount: 1, unit: .chapters)) == "1 chapter")
        #expect(Goals.amount(Challenge.Target(name: "Steps", amount: 10_000, unit: .steps)) == "10,000 steps")
        #expect(Goals.detail(.walk, Challenge.Target(name: "Stretch")) == "No set amount")
        #expect(Goals.water(Self.custom.water) == "3,000 ml · 330 ml glass")
        #expect(Goals.sentence(.standard)
                == "4 litres of water, a 45-minute workout, a 45-minute walk, a clean diet and 10 Bible pages")
        #expect(Goals.sentence(Self.custom)
                == "3,000 ml of water, Gym 45 min, Yoga 30 min, No sugar and Audiobook 20 min")
        // An unknown icon id shows the slot's default.
        #expect(Goals.symbol(.walk, Challenge.Target(name: "Rowing", icon: "rowing")) == "figure.walk")
        #expect(Goals.symbol(.bibleReading, Self.custom.bibleReading) == "headphones")
    }

    @Test func presetsMatchThePlanAndTheStandardPresetRecordsNothing() {
        #expect(Goals.presets(.workout).map(\.name) == ["Workout", "Gym", "Run", "Cycle", "Swim", "Yoga", "Pilates", "HIIT"])
        #expect(Goals.presets(.walk).map(\.name) == ["Walk", "Yoga", "Pilates", "Stretching", "Run", "Cycle", "Steps"])
        #expect(Goals.presets(.bibleReading).map(\.name) == ["Bible", "Book", "Audiobook", "Devotional", "Study"])
        #expect(Goals.presets(.diet).map(\.name) == ["Diet", "Clean eating", "No sugar", "No alcohol"])
        #expect(Goals.glasses == [250, 330, 450, 500, 750])
        for slot in Challenge.TargetSlot.allCases {
            #expect(Goals.target(Goals.presets(slot)[0], for: slot) == Challenge.Targets.standard[slot])
            for preset in Goals.presets(slot) {
                #expect(Goals.target(preset, for: slot).isValid(for: slot), "\(preset.name) is valid for \(slot)")
            }
        }
        #expect(Goals.target(Goals.presets(.diet)[2], for: .diet) == Challenge.Target(name: "No sugar"), "Diet takes a name only")
    }

    @Test func limitsHaveClearMessages() {
        #expect(Goals.nameProblem("   ") == "Enter a name.")
        #expect(Goals.nameProblem(String(repeating: "a", count: 21)) == "Use 20 characters or fewer (21 now).")
        #expect(Goals.nameProblem("Yoga\nflow") != nil)
        #expect(Goals.nameProblem(" Yoga ") == nil, "Trimmed")
        #expect(Goals.waterProblem(Challenge.WaterTarget(goal: 750, glass: 250)) == "The daily goal must be 1,000 to 5,000 ml.")
        #expect(Goals.waterProblem(Challenge.WaterTarget(goal: 3_000, glass: 40)) == "A glass must be 50 to 1,000 ml.")
        #expect(Goals.waterProblem(Challenge.WaterTarget(goal: 1_000, glass: 1_000)) == nil)
        #expect(Goals.waterProblem(Challenge.WaterTarget(goal: 5_000, glass: 1_000)) == nil)
        #expect(Goals.range(.minutes) == "5 to 300 minutes")
        #expect(Goals.range(.steps) == "1,000 to 50,000 steps")
        for unit in Challenge.TargetUnit.allCases {
            #expect(unit.amounts.contains(Goals.suggestedAmount(unit)))
        }
    }

    // MARK: P4: setup, Account › Daily goals, Activity, welcome

    @Test func setupShowsFiveRowsAndStartsWithTheChosenGoals() throws {
        try withModel { model, auth, appearance in
            let standard = try Self.render(TrackerView(model: model, auth: auth, setupTimeZone: Self.london)
                .environment(appearance), name: "goals-setup")
            // No taller than History and Account, which share the tallest sheet.
            let tallest = Theme.Size.headerHeight + Theme.Size.wideSectionHeight + Theme.Size.footerHeight + 24
            #expect(standard.height <= tallest, "Setup fits under the menu bar (\(standard.height))")
            try Self.render(TrackerView(model: model, auth: auth, setupTimeZone: Self.london, setupTargets: Self.custom)
                .environment(appearance), name: "goals-setup-custom")
            model.startChallenge(on: Self.now.addingTimeInterval(-2 * 86_400), timeZone: Self.london, targets: Self.custom)
            let challenge = try #require(model.challenge)
            #expect(challenge.targets(on: challenge.startDate) == Self.custom)
            #expect(challenge.allActivities.count == 5, "One event per changed value, dated the start day")
            #expect(challenge.allActivities.allSatisfy { $0.day == challenge.startDate })
        }
    }

    @Test func acceptingTheStandardFiveWritesNothingNew() throws {
        try withModel { model, _, _ in
            model.startChallenge(on: Self.now, timeZone: Self.london)
            #expect(model.challenge?.allActivities.isEmpty == true)
            #expect(model.setTargets(.standard) == nil)
            #expect(model.challenge?.allActivities.isEmpty == true, "Saving unchanged goals records nothing")
        }
    }

    @Test func dailyGoalsChangeFromTodayAndTheAuditSaysWhat() throws {
        try withModel { model, auth, appearance in
            model.startChallenge(on: Self.now.addingTimeInterval(-3 * 86_400), timeZone: Self.london)
            var next = model.todayTargets
            next.walk = Self.custom.walk
            next.water = Self.custom.water
            #expect(model.setTargets(next) == nil)
            let events = try #require(model.challenge?.allActivities)
            #expect(events.count == 2)
            #expect(events.allSatisfy { $0.day == model.today }, "Changes apply from today")
            model.selectHistoryDay(Self.now)
            #expect(model.history.map { HistoryTrackerView.auditText(model, $0) }
                    == ["Walk changed to Yoga · 30 min", "Water now 3,000 ml · 330 ml glass"], "Newest first")
            let size = try Self.render(TrackerPopup(model: model, auth: auth, appearance: appearance, section: .history),
                                       name: "goals-history-audit")
            #expect(size.width == 420)
            model.showToday()
            try Self.render(VStack(spacing: 0) { DailyGoalsSettings(model: model, expanded: true) }
                .padding(.horizontal, Theme.Size.sectionHorizontal).padding(.vertical, 10)
                .trackerSurface(), name: "goals-account")
            // A rename keeps the amount; a later change on the same day wins.
            next.walk = Challenge.Target(name: "Pilates", amount: 30, unit: .minutes, icon: "pilates")
            #expect(model.setTargets(next) == nil)
            #expect(model.todayTargets.walk.name == "Pilates")
        }
    }

    @Test func activityAuditDescribesGoalAndRepeatChanges() throws {
        try withModel { model, _, _ in
            model.startChallenge(on: Self.now.addingTimeInterval(-86_400), timeZone: Self.london)
            var next = model.todayTargets
            next.walk = Self.custom.walk
            #expect(model.setTargets(next) == nil)
            next.water = Challenge.WaterTarget(goal: 3_000, glass: 330)
            #expect(model.setTargets(next) == nil)
            next.water = Challenge.WaterTarget(goal: 3_000, glass: 250)
            #expect(model.setTargets(next) == nil)
            #expect(model.addExtra("Stretch") == nil)
            let stretch = try #require(model.activeExtras.first)
            #expect(model.scheduleExtra(stretch.id, .every(1)) == nil)
            model.toggle(.walk)
            model.selectHistoryDay(Self.now)
            let rows = model.history.map { HistoryTrackerView.auditText(model, $0) }
            #expect(rows.contains("Walk changed to Yoga · 30 min"))
            #expect(rows.contains("Water now 3,000 ml · 330 ml glass"))
            #expect(model.history.contains { HistoryTrackerView.auditDescription(model, $0)
                == "Daily goal: Water goal changed to 3,000 ml, 330 ml glass, from this day on" })
            #expect(rows.contains("Glass changed to 250 ml"))
            #expect(rows.contains("“Stretch” repeats every day"))
            #expect(rows.contains("Yoga complete"), "A tick is named by the day's target")
        }
    }

    @Test func welcomeTextDescribesTheChosenGoals() {
        #expect(WelcomeStepRow.title(.startDate) == "Choose your daily five and a start date")
        let standard = WelcomeStepRow.detail(.logDay)
        #expect(standard.contains("4 litres of water") && standard.contains("Unless you choose your own"))
        let chosen = WelcomeStepRow.detail(.logDay, targets: Self.custom)
        #expect(chosen == "3,000 ml of water, Gym 45 min, Yoga 30 min, No sugar and Audiobook 20 min, every day.")
        #expect(!chosen.contains("Bible") && !chosen.contains("4 litres"))
        #expect(WelcomeStepRow.started(startLabel: "Mon 12 Oct", targets: Self.custom)
                == "Day 1 is Mon 12 Oct. Click the drop in the menu bar each day to log 3,000 ml of water, Gym 45 min, Yoga 30 min, No sugar and Audiobook 20 min.")
        for text in [standard, chosen, WelcomeStepRow.detail(.startDate)] {
            #expect(!text.contains("—") && !text.contains("–"), "No em or en dashes in public text")
        }
    }

    @Test func editorsRenderWithTheirLimits() throws {
        try Self.render(WaterGoalEditor(initial: Self.custom.water, close: {}, save: { _ in nil }), name: "goals-editor-water",
                        width: nil)
        try Self.render(WaterGoalEditor(initial: Challenge.WaterTarget(goal: 1_000, glass: 400), close: {}, save: { _ in nil }),
                        name: "goals-editor-water-other", width: nil)
        try Self.render(TargetEditor(slot: .walk, initial: Self.custom.walk, close: {}, save: { _ in nil }),
                        name: "goals-editor-walk", width: nil)
        try Self.render(TargetEditor(slot: .bibleReading, initial: Challenge.Target(name: "Poetry", amount: 5, unit: .pages, icon: "book"),
                                     close: {}, save: { _ in nil }), name: "goals-editor-custom", width: nil)
        try Self.render(TargetEditor(slot: .diet, initial: Self.custom.diet, close: {}, save: { _ in nil }),
                        name: "goals-editor-diet", width: nil)
        try Self.render(TargetEditor(slot: .workout, initial: Challenge.Target(name: "Morning strength circuit", amount: 45,
                                                                               unit: .minutes), close: {}, save: { _ in nil }),
                        name: "goals-editor-too-long", width: nil)
    }

    @Test func longNamesFitTheRingRow() throws {
        try withModel { model, _, _ in
            var targets = Self.custom
            targets.bibleReading = Challenge.Target(name: "Scripture memorising", amount: 20, unit: .minutes, icon: "bible")
            targets.walk = Challenge.Target(name: "Evening stretching", amount: 15, unit: .minutes, icon: "stretch")
            model.startChallenge(on: Self.now, timeZone: Self.london, targets: targets)
            let size = try Self.render(RingRow(model: model).padding(.horizontal, 12), name: "goals-rings-long-names")
            #expect(size.width == 420, "Long names scale down and truncate instead of widening the row")
        }
    }

    // MARK: P5: repeating extras

    @Test func repeatCaptionsReadPlainly() {
        #expect(ExtraRepeat.caption(.once) == "Once")
        #expect(ExtraRepeat.caption(.every(1)) == "Every day")
        #expect(ExtraRepeat.caption(.every(3)) == "Every 3 days")
        #expect(ExtraRepeat.caption(.weekdays([1, 2, 3, 4, 5])) == "Weekdays")
        #expect(ExtraRepeat.caption(.weekdays([6, 7])) == "Weekends")
        #expect(ExtraRepeat.caption(.weekdays([7])) == "Sundays")
        #expect(ExtraRepeat.caption(.weekdays([5, 1, 3])) == "Mon, Wed, Fri")
        #expect(ExtraRepeat.caption(.weekdays(Set(1...7))) == "Every day")
        #expect(ExtraRepeat.rowCaption(.once) == nil, "A to-do has no caption; Late is its only marker")
        #expect(ExtraRepeat.rowCaption(.every(1)) == "every day")
        #expect(ExtraRepeat.rowCaption(.weekdays([1, 2, 3, 4, 5])) == "weekdays")
        #expect(ExtraRepeat.rowCaption(.weekdays([7])) == "Sundays")
        #expect(ExtraRepeat.phrase(.weekdays([7])) == "on Sundays")
        #expect(ExtraRepeat.phrase(.every(2)) == "every 2 days")
        let calendar = Challenge.calendar(for: Self.london)
        #expect(ManageExtrasView.weekday(Self.now, calendar) == 1, "12 October 2026 is a Monday")
    }

    @Test func repeatPickerChoicesMapToRules() {
        typealias Choice = ManageExtrasView.RepeatChoice
        #expect(Choice.allCases.map(\.rawValue) == ["Once", "Every day", "Weekdays", "Choose days", "Every N days"])
        #expect(Choice(.once) == .once && Choice(.every(1)) == .everyDay && Choice(.every(4)) == .everyN)
        #expect(Choice(.weekdays([1, 2, 3, 4, 5])) == .weekdays && Choice(.weekdays([7])) == .chooseDays)
    }

    @Test func repeatingExtrasShowCaptionsAndAreNeverLate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = PopupProbe.Clock(Self.now)
        let model = TrackerModel(directory: directory, clock: { clock.now })
        model.activate(ownerID: UUID())
        let start = Self.now.addingTimeInterval(-2 * 86_400)
        let calendar = Challenge.calendar(for: Self.london)
        model.startChallenge(on: start, timeZone: Self.london)
        // A to-do added on the first day and still open is Late today.
        clock.now = start; model.showToday()
        #expect(model.addExtra("Book the dentist") == nil)
        clock.now = Self.now; model.showToday()
        for title in ["Stretch", "Pack lunch", "Call Mum"] { #expect(model.addExtra(title) == nil) }
        let extras = try #require(model.challenge?.allExtras)
        func id(_ title: String) -> UUID { extras.first { $0.title == title }!.id }
        #expect(model.scheduleExtra(id("Stretch"), .every(1)) == nil)
        #expect(model.scheduleExtra(id("Pack lunch"), .weekdays([1, 2, 3, 4, 5])) == nil)
        #expect(model.scheduleExtra(id("Call Mum"), .weekdays([ManageExtrasView.weekday(Self.now, calendar)])) == nil)
        do {
            model.toggleExtra(id("Stretch"))
            let today = try #require(model.summary)
            #expect(today.extrasTotal == 4 && today.extrasDone == 1)
            #expect(today.extras.filter { $0.schedule != .once }.allSatisfy { !today.isLate($0) })
            #expect(today.extras.filter { today.isLate($0) }.map(\.title) == ["Book the dentist"])
            #expect(model.summary?.isComplete == false, "Extras never count toward the five")
            try Self.render(TodayTrackerView(model: model), name: "goals-today-repeating-extras")
            try Self.render(ManageExtrasView(model: model), name: "goals-manage-extras", width: nil)
            let stretch = id("Stretch")
            for (choice, days, name) in [(ManageExtrasView.RepeatChoice.everyDay, Set<Int>(), "every-day"),
                                         (.chooseDays, [1, 3, 5], "choose-days"), (.chooseDays, [], "choose-days-none"),
                                         (.everyN, [], "every-n"), (.once, [], "once")] {
                try Self.render(ManageExtrasView(model: model, renaming: stretch, renameTitle: "Stretch", repeatChoice: choice,
                                                 repeatDays: days, repeatEvery: 3), name: "goals-repeat-\(name)", width: nil)
            }
            #expect(ManageExtrasView(model: model, repeatChoice: .chooseDays, repeatDays: []).chosenSchedule == nil,
                    "Choose days needs at least one day")
            #expect(ManageExtrasView(model: model, repeatChoice: .everyN, repeatEvery: 3).chosenSchedule == .every(3))
        }
    }
}
