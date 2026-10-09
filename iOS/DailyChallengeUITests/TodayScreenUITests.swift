import XCTest

/// Drives the real app on Debug fixtures (`-fixture`): no account, Keychain or network.
final class TodayScreenUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ fixture: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-fixture", fixture] + extra
        app.launch()
        return app
    }

    @MainActor func testTodayShowsTheFiveRingsJugAndStreak() {
        let app = launch("today")
        for ring in ["ring-water", "ring-workout", "ring-walk", "ring-diet", "ring-bibleReading"] {
            XCTAssertTrue(app.descendants(matching: .any)[ring].waitForExistence(timeout: 5), ring)
        }
        XCTAssertEqual(app.descendants(matching: .any)["ring-water"].value as? String, "2,250 of 4,000 millilitres")
        XCTAssertTrue(app.descendants(matching: .any)["water-jug"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["streak-current"].label, "Current streak: 6 days. Goal: 75 days.")
        XCTAssertTrue(app.staticTexts["Day 12"].exists || app.descendants(matching: .any)["Day 12, 2 of 5 done"].exists)
    }

    @MainActor func testPouringUndoingAndCompletingAHabit() {
        let app = launch("today")
        let water = app.descendants(matching: .any)["ring-water"]
        XCTAssertTrue(water.waitForExistence(timeout: 5))
        app.buttons["water-add"].tap()
        XCTAssertEqual(water.value as? String, "2,700 of 4,000 millilitres")
        app.buttons["water-undo"].tap()
        XCTAssertEqual(water.value as? String, "2,250 of 4,000 millilitres")

        let walk = app.buttons["ring-walk"]
        XCTAssertEqual(walk.value as? String, "Not complete")
        walk.tap()
        XCTAssertEqual(walk.value as? String, "Complete")
        walk.tap()
        XCTAssertEqual(walk.value as? String, "Not complete")
    }

    @MainActor func testCompletingAllFiveShowsTheBand() {
        let app = launch("today")
        XCTAssertTrue(app.buttons["ring-walk"].waitForExistence(timeout: 5))
        app.buttons["ring-walk"].tap()
        app.buttons["ring-bibleReading"].tap()
        for _ in 0..<4 { app.buttons["water-add"].tap() }
        XCTAssertTrue(app.staticTexts["All five complete!"].waitForExistence(timeout: 5))
    }

    @MainActor func testHistoryNeedsTheEditUnlockBeforeALateEntry() {
        let app = launch("history")
        let edit = app.buttons["history-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["water-add"].isEnabled)
        edit.tap()
        XCTAssertTrue(app.descendants(matching: .any)["history-editing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["water-add"].isEnabled)
    }

    @MainActor func testAccountShowsTheSignedInEmailAndReminders() {
        let app = launch("account")
        let email = app.staticTexts["account-email"].firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        XCTAssertTrue(email.label.hasPrefix("sam@example.com"), email.label)
        XCTAssertTrue(app.staticTexts["reminders-status"].firstMatch.label.contains("on this iPhone"))
        XCTAssertTrue(app.buttons["account-sign-out"].exists)
    }

    @MainActor func testSignInIsTheSignedOutScreen() {
        let app = launch("signIn")
        XCTAssertTrue(app.staticTexts["auth-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["auth-title"].label, "Sign in")
        app.buttons["auth-create-account"].tap()
        XCTAssertEqual(app.staticTexts["auth-title"].label, "Create account")
    }

    @MainActor func testTodayStaysUsableAtAnAccessibilityTextSize() {
        let app = launch("today", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        XCTAssertTrue(app.buttons["ring-walk"].waitForExistence(timeout: 5))
        app.buttons["ring-walk"].tap()
        XCTAssertEqual(app.buttons["ring-walk"].value as? String, "Complete")
        app.swipeUp()
        XCTAssertTrue(app.buttons["water-add"].exists)
    }
}
