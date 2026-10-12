import ChallengeCore
import ChallengeSyncKit
import Foundation
import Testing
@testable import Daily_Challenge

@MainActor private func goalsFixture(_ screen: PhoneFixtures.Screen, directory: URL) -> PhoneApp {
    PhoneFixtures.make(screen, defaults: UserDefaults(suiteName: "phone-goals-tests-\(UUID())")!, directory: directory)
}

@Test func everyPresetIsAValidTargetForItsSlot() {
    for slot in Challenge.TargetSlot.allCases {
        let presets = GoalWords.presets(slot)
        #expect(!presets.isEmpty)
        for preset in presets { #expect(preset.target.isValid(for: slot), "\(slot) \(preset.name)") }
        // The slot's own preset is exactly the standard target, so choosing it records nothing.
        #expect(presets[0].target == Challenge.Targets.standard[slot])
    }
    for glass in GoalWords.glassPresets {
        #expect(Challenge.WaterTarget(goal: 1_000, glass: glass).isValid)
    }
    for icon in GoalWords.icons { #expect(Challenge.isIconID(icon.id), "\(icon.id)") }
    #expect(Set(GoalWords.icons.map(\.id)).count == GoalWords.icons.count)
}

@Test func goalWordsReadAmountsIconsAndFallBackForUnknownIcons() {
    let standard = Challenge.Targets.standard
    #expect(GoalWords.detail(.workout, standard.workout) == "45 min · home or gym")
    #expect(GoalWords.detail(.walk, standard.walk) == "45 min")
    #expect(GoalWords.detail(.diet, standard.diet) == "Your own rules")
    #expect(GoalWords.detail(.bibleReading, standard.bibleReading) == "10 pages")
    #expect(GoalWords.spoken(.walk, standard.walk) == "Walk, 45 minutes")
    #expect(GoalWords.water(standard.water) == "4,000 ml · 450 ml glass")
    let devotional = Challenge.Target(name: "Devotional", amount: 1, unit: .chapters, icon: "bible")
    #expect(GoalWords.amount(devotional) == "1 chapter")
    #expect(GoalWords.spokenAmount(Challenge.Target(name: "Run", amount: 5, unit: .kilometres)) == "5 kilometres")
    #expect(GoalWords.amount(Challenge.Target(name: "Steps", amount: 10_000, unit: .steps)) == "10,000 steps")
    #expect(GoalWords.detail(.walk, Challenge.Target(name: "Garden")) == "Tick it when it's done")
    #expect(GoalWords.symbol(.bibleReading, devotional) == "book.closed")
    // An id from a newer version shows the slot's own icon.
    #expect(GoalWords.symbol(.walk, Challenge.Target(name: "Climb", icon: "climbing")) == "figure.walk")
    #expect(GoalWords.symbol(.diet, standard.diet) == "leaf")
}

@Test func repeatCaptionsNameEachRule() {
    #expect(GoalWords.repeatCaption(.once) == nil)
    #expect(GoalWords.repeatTitle(.once) == "Once")
    #expect(GoalWords.repeatCaption(.every(1)) == "every day")
    #expect(GoalWords.repeatCaption(.weekdays(Set(1...7))) == "every day")
    #expect(GoalWords.repeatCaption(.every(3)) == "every 3 days")
    #expect(GoalWords.repeatCaption(.weekdays(Set(1...5))) == "weekdays")
    #expect(GoalWords.repeatCaption(.weekdays([6, 7])) == "weekends")
    #expect(GoalWords.repeatCaption(.weekdays([7])) == "Sundays")
    #expect(GoalWords.repeatCaption(.weekdays([5, 1, 3])) == "Mon, Wed, Fri")
    #expect(GoalWords.repeatTitle(.weekdays(Set(1...5))) == "Weekdays")
    #expect(GoalWords.repeatPhrase(.weekdays([6, 7])) == "at weekends")
    #expect(GoalWords.repeatPhrase(.weekdays([7])) == "on Sundays")
    #expect(GoalWords.repeatPhrase(.every(2)) == "every 2 days")
}

@Test @MainActor func activityNamesHabitsByTheDaysTargetsAndWordsGoalChanges() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("phone-goals-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let tracker = goalsFixture(.historyGoals, directory: directory).tracker
    let challenge = try #require(tracker.challenge)
    let contexts = ActivityWords.contexts(on: tracker.today, in: challenge)
    let words = challenge.history(on: tracker.today).map { ActivityWords.short($0, in: contexts[$0.id]!) }
    #expect(words.contains("Gym complete"), "Ticks today use today's names")
    #expect(words.contains("No sugar clean"))
    #expect(words.contains("Water goal changed to 3,000 ml, 330 ml glass"))
    #expect(words.contains("Workout changed to Gym · 45 min"))
    #expect(words.contains("Walk changed to Yoga · 30 min"))
    #expect(words.contains("Diet renamed No sugar"))
    #expect(words.contains("Bible changed to Audiobook · 20 min"))
    let spoken = challenge.history(on: tracker.today).map { ActivityWords.long($0, in: contexts[$0.id]!) }
    #expect(spoken.contains("Walk changed to Yoga, 30 minutes"))
    // Two days ago keeps the standard names.
    let earlier = tracker.dates.calendar.date(byAdding: .day, value: -2, to: tracker.today)!
    let before = ActivityWords.contexts(on: earlier, in: challenge)
    let earlierWords = challenge.history(on: earlier).map { ActivityWords.short($0, in: before[$0.id]!) }
    #expect(earlierWords.contains("Walk complete"))
    #expect(earlierWords.contains("Bible reading complete"))
}

@Test @MainActor func scheduleWordingNamesTheExtra() {
    let id = UUID()
    let context = ActivityWords.Context(extraTitle: "Stretch")
    func activity(_ action: Challenge.Action) -> Challenge.Activity {
        Challenge.Activity(id: UUID(), day: PhoneFixtures.now, recordedAt: PhoneFixtures.now, action: action, undonePourID: nil)
    }
    #expect(ActivityWords.short(activity(.scheduleExtra(id: id, every: 1)), in: context) == "“Stretch” repeats every day")
    #expect(ActivityWords.short(activity(.scheduleExtra(id: id, weekdays: [1, 2, 3, 4, 5])), in: context) == "“Stretch” repeats on weekdays")
    #expect(ActivityWords.short(activity(.scheduleExtra(id: id)), in: context) == "“Stretch” no longer repeats")
    #expect(ActivityWords.icon(activity(.scheduleExtra(id: id))).0 == "repeat")
    #expect(ActivityWords.short(activity(.setWater(goal: 2_000, pour: 250))) == "Water goal changed to 2,000 ml, 250 ml glass")
}

@Test @MainActor func customGoalsFixtureJudgesTodayByItsGoalAndKeepsEarlierDays() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("phone-goals-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let tracker = goalsFixture(.todayGoals, directory: directory).tracker
    let streak = tracker.streaks?.current
    #expect(tracker.summary?.targets == PhoneFixtures.customTargets)
    #expect(tracker.todayTargets == PhoneFixtures.customTargets)
    tracker.addWater()
    #expect(tracker.summary?.waterMillilitres == 2_580, "+ pours today's 330 ml glass")
    tracker.addWater(); tracker.addWater()
    #expect(tracker.summary?.waterComplete == true, "3,240 ml meets today's 3,000 ml goal")
    tracker.toggle(.walk); tracker.toggle(.bibleReading)
    #expect(tracker.summary?.isComplete == true)
    #expect(tracker.streaks?.current == (streak ?? 0) + 1)
    let earlier = tracker.dates.calendar.date(byAdding: .day, value: -2, to: tracker.today)!
    #expect(tracker.challenge?.targets(on: earlier) == .standard)
    #expect(tracker.challenge?.summary(on: earlier, asOf: tracker.now).status == .complete)
}

@Test @MainActor func unmigratedServerKeepsGoalChangesAndSaysSo() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("phone-goals-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let tracker = goalsFixture(.goalsUnmigrated, directory: directory).tracker
    await tracker.sync(force: true)
    #expect(tracker.syncError == ChallengeSyncError.serverNeedsCustomGoalsUpdate.errorDescription)
    #expect(tracker.todayTargets == PhoneFixtures.customTargets)
    #expect((tracker.store?.pendingCount ?? 0) > 0)
}

@Test @MainActor func recurringFixtureShowsRepeatsBesideALateToDo() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("phone-goals-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let tracker = goalsFixture(.todayRecurring, directory: directory).tracker
    let summary = try #require(tracker.summary)
    #expect(summary.extras.map(\.title) == ["Stretch", "Pack lunch", "Call Mum", "Book dentist"])
    #expect(summary.extras.map(summary.isLate) == [false, false, false, true])
    #expect(summary.extrasDone == 2)
    #expect(tracker.activeExtras.count == 4)
    // Changing a repeat applies from today only.
    let pack = summary.extras[1]
    #expect(tracker.scheduleExtra(pack.id, .weekdays([6, 7])) == nil)
    #expect(tracker.summary?.extras.contains { $0.id == pack.id } == false, "Friday is no longer a Pack lunch day")
    let yesterday = tracker.dates.calendar.date(byAdding: .day, value: -1, to: tracker.today)!
    #expect(tracker.challenge?.summary(on: yesterday, asOf: tracker.now).extras.contains { $0.id == pack.id } == true)
}
