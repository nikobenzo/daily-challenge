import XCTest

/// Custom daily goals and repeating extras in the real app on Debug fixtures (`-fixture`):
/// no account, Keychain or network.
final class GoalsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ fixture: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-fixture", fixture] + extra
        app.launch()
        return app
    }

    @MainActor func testSetupShowsTheStandardFiveAndAcceptingThemIsOneTap() {
        let app = launch("setup")
        let water = app.buttons["goal-water"]
        XCTAssertTrue(water.waitForExistence(timeout: 5))
        XCTAssertEqual(water.label, "Water")
        XCTAssertEqual(water.value as? String, "Goal 4,000 millilitres, 450 millilitre glass")
        XCTAssertEqual(app.buttons["goal-walk"].label, "Walk")
        XCTAssertEqual(app.buttons["goal-bibleReading"].label, "Bible")
        app.buttons["setup-start-challenge"].tap()
        let ring = app.descendants(matching: .any)["ring-water"]
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        XCTAssertEqual(ring.value as? String, "0 of 4,000 millilitres")
        XCTAssertEqual(app.buttons["ring-walk"].label, "Walk, 45 minutes")
    }

    @MainActor func testSetupEditorsChangeTheFiveBeforeStarting() {
        let app = launch("setup")
        XCTAssertTrue(app.buttons["goal-walk"].waitForExistence(timeout: 5))
        app.buttons["goal-walk"].tap()
        XCTAssertTrue(app.buttons["Yoga"].waitForExistence(timeout: 5))
        app.buttons["Yoga"].tap()
        app.buttons["goal-done"].tap()
        XCTAssertTrue(app.buttons["goal-walk"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["goal-walk"].label, "Yoga")
        XCTAssertEqual(app.buttons["goal-walk"].value as? String, "Second activity, 30 minutes")

        app.buttons["goal-water"].tap()
        XCTAssertTrue(app.buttons["330 ml"].waitForExistence(timeout: 5))
        app.buttons["330 ml"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["water-goal"].value as? String, "4,000 millilitres")
        app.buttons["goal-done"].tap()
        XCTAssertTrue(app.buttons["goal-water"].waitForExistence(timeout: 5))
        XCTAssertTrue((app.buttons["goal-water"].value as? String)?.hasSuffix("330 millilitre glass") == true)

        app.buttons["setup-start-challenge"].tap()
        XCTAssertTrue(app.buttons["ring-walk"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["ring-walk"].label, "Yoga, 30 minutes")
        XCTAssertEqual(app.buttons["water-add"].label, "Add 330 millilitres of water")
        app.buttons["water-add"].tap()
        XCTAssertTrue((app.descendants(matching: .any)["ring-water"].value as? String)?.hasPrefix("330 of ") == true)
    }

    @MainActor func testEditorsRefuseValuesOutsideTheLimits() {
        let app = launch("setup", ["-edit-goal", "walk"])
        let amount = app.textFields["target-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.press(forDuration: 1.2)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        amount.typeText(XCUIKeyboardKey.delete.rawValue + "400")
        XCTAssertTrue(app.descendants(matching: .any)["target-amount-problem"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["goal-done"].isEnabled)
        app.buttons["Less"].tap()
        XCTAssertEqual(amount.value as? String, "300")
        XCTAssertTrue(app.buttons["goal-done"].isEnabled)

        let name = app.textFields["target-name"]
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "A name that is far too long")
        XCTAssertEqual(app.staticTexts["target-name-help"].label, "Use a name of 1 to 20 characters on one line.")
        XCTAssertFalse(app.buttons["goal-done"].isEnabled)
        app.terminate()

        let water = launch("setup", ["-edit-goal", "water"])
        XCTAssertTrue(water.buttons["glass-other"].waitForExistence(timeout: 5))
        water.buttons["glass-other"].tap()
        let other = water.textFields["glass-other-amount"]
        XCTAssertTrue(other.waitForExistence(timeout: 3))
        other.typeText("40")
        XCTAssertTrue(water.descendants(matching: .any)["water-problem"].label.hasSuffix("A glass or bottle is 50 to 1,000 ml."))
        XCTAssertFalse(water.buttons["goal-done"].isEnabled)
    }

    @MainActor func testDailyGoalsChangeTheGlassFromToday() {
        let app = launch("account", ["-daily-goals", "-edit-goal", "water"])
        XCTAssertTrue(app.buttons["250 ml"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Changes apply from today")).firstMatch.exists)
        app.buttons["250 ml"].tap()
        app.buttons["goal-done"].tap()
        let row = app.buttons["goal-water"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.value as? String, "Goal 4,000 millilitres, 250 millilitre glass")
        XCTAssertEqual(app.staticTexts["goals-applies"].label, "Changes apply from today, Fri 9 Oct. Earlier days keep the goals they had.")
        app.buttons["Done"].tap()
        app.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["water-add"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["water-add"].label, "Add 250 millilitres of water")
    }

    @MainActor func testCustomGoalsShowOnTodayAndInHistory() {
        let app = launch("todayGoals")
        let ring = app.descendants(matching: .any)["ring-water"]
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        XCTAssertEqual(ring.value as? String, "2,250 of 3,000 millilitres")
        XCTAssertEqual(app.buttons["ring-workout"].label, "Gym, 45 minutes")
        XCTAssertEqual(app.buttons["ring-walk"].label, "Yoga, 30 minutes")
        XCTAssertEqual(app.buttons["ring-diet"].label, "No sugar, your own rules")
        XCTAssertEqual(app.buttons["ring-bibleReading"].label, "Audiobook, 20 minutes")
        app.terminate()
        let before = launch("historyGoalsBefore", ["-fixture-scroll-to", "fixture-history-day"])
        let total = before.descendants(matching: .any)["water-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.hasSuffix("of 4,000 millilitres"), "Earlier days keep the standard goal")
        XCTAssertTrue(before.buttons["Walk, 45 minutes"].exists)
    }

    @MainActor func testUnmigratedServerSaysChangesWaitHere() {
        let app = launch("goalsUnmigrated", ["-daily-goals"])
        XCTAssertTrue(app.descendants(matching: .any)["goals-server-notice"].waitForExistence(timeout: 8))
    }

    @MainActor func testRepeatPickerSetsHowAnExtraRepeats() {
        let app = launch("todayRecurring", ["-fixture-scroll-to", "fixture-extras"])
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Stretch, every day")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Book dentist, late")).firstMatch.exists)
        app.terminate()

        let manage = launch("todayRecurring", ["-manage-extras"])
        let repeatButton = manage.buttons.matching(identifier: "extras-repeat").firstMatch
        XCTAssertTrue(repeatButton.waitForExistence(timeout: 5))
        XCTAssertEqual(repeatButton.label, "Repeat Stretch")
        XCTAssertEqual(repeatButton.value as? String, "Every day")
        repeatButton.tap()
        XCTAssertTrue(manage.buttons["repeat-Choose days"].waitForExistence(timeout: 5))
        manage.buttons["repeat-Choose days"].tap()
        XCTAssertEqual(manage.staticTexts["repeat-explanation"].label, "Choose at least one day.")
        XCTAssertFalse(manage.buttons["repeat-done"].isEnabled)
        manage.buttons["Saturday"].tap()
        manage.buttons["Sunday"].tap()
        manage.buttons["repeat-done"].tap()
        XCTAssertTrue(repeatButton.waitForExistence(timeout: 5))
        XCTAssertEqual(repeatButton.value as? String, "Weekends")
    }
}
