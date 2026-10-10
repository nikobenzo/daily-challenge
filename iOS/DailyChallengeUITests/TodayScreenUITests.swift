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

    @MainActor func testSharedStorageTodayAndRecoveryPresentation() {
        let app = launch("sharedToday")
        let water = app.descendants(matching: .any)["ring-water"]
        XCTAssertTrue(water.waitForExistence(timeout: 5))
        XCTAssertEqual(water.value as? String, "2,250 of 4,000 millilitres")
        app.buttons["water-add"].tap()
        XCTAssertEqual(water.value as? String, "2,700 of 4,000 millilitres")
        app.terminate()
        let recovery = launch("storageRecovery")
        XCTAssertTrue(recovery.staticTexts["History unavailable"].waitForExistence(timeout: 5))
        XCTAssertTrue(recovery.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Storage recovery is needed")).firstMatch.exists)
        XCTAssertFalse(recovery.buttons["Start challenge"].exists)
        XCTAssertTrue(recovery.buttons["Try again"].exists)
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

/// Extras use the same fixture-only launch path as the rest of the phone suite.
final class PhoneExtrasUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor private func launch(_ fixture: String, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-fixture", fixture]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"] }
        app.launch()
        return app
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, element.debugDescription)
    }

    @MainActor func testEmptyTodayAndAccountOpenTheSameManagementSheet() {
        let app = launch("today")
        let empty = app.buttons["extras-empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        reveal(empty, in: app); empty.tap()
        XCTAssertTrue(app.textFields["extras-new-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["extras-active-count"].label, "0/10 extras")
        app.buttons["Done"].tap()
        app.tabBars.buttons["Account"].tap()
        let account = app.buttons["account-extras"]
        reveal(account, in: app); account.tap()
        XCTAssertTrue(app.textFields["extras-new-title"].waitForExistence(timeout: 5))
    }

    @MainActor func testAddRenameAndArchiveRequireConfirmation() {
        let app = launch("today")
        let empty = app.buttons["extras-empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5)); reveal(empty, in: app); empty.tap()
        let field = app.textFields["extras-new-title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Stretch")
        app.buttons["extras-add"].tap()
        app.buttons["Rename Stretch"].tap()
        let rename = app.textFields["extras-rename-title"]
        rename.tap(); rename.typeText(" gently")
        app.buttons["Save name"].tap()
        app.buttons["Archive Stretch gently"].tap()
        XCTAssertTrue(app.staticTexts["It disappears from today on and can't be restored. Earlier days keep their ticks."].waitForExistence(timeout: 5))
        app.alerts["Archive extra?"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Archive Stretch gently"].exists)
        app.buttons["Archive Stretch gently"].tap()
        app.alerts["Archive extra?"].buttons["Archive Stretch gently"].tap()
        XCTAssertEqual(app.staticTexts["extras-active-count"].label, "0/10 extras")
    }

    @MainActor func testCapAndInvalidTitlesAreExplained() {
        let app = launch("extrasCap")
        let manage = app.buttons["extras-manage"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5)); reveal(manage, in: app); manage.tap()
        XCTAssertTrue(app.staticTexts["extras-cap"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["extras-active-count"].label, "10/10 extras")
        XCTAssertFalse(app.textFields["extras-new-title"].exists)
        app.buttons["Done"].tap()
        app.terminate()
        let emptyApp = launch("today")
        let empty = emptyApp.buttons["extras-empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5)); reveal(empty, in: emptyApp); empty.tap()
        XCTAssertFalse(emptyApp.buttons["extras-add"].isEnabled)
        let field = emptyApp.textFields["extras-new-title"]
        field.tap(); field.typeText(String(repeating: "a", count: 41))
        XCTAssertFalse(emptyApp.buttons["extras-add"].isEnabled)
        XCTAssertTrue(emptyApp.staticTexts["Use a name of 1–40 characters on one line."].exists)
    }

    @MainActor func testHistoricalExtrasAreLockedUntilEditAndRelockOnSelection() {
        let app = launch("historyExtras")
        let stretch = app.buttons.matching(NSPredicate(format: "label == %@", "Stretch")).firstMatch
        XCTAssertTrue(stretch.waitForExistence(timeout: 5)); reveal(stretch, in: app)
        XCTAssertFalse(stretch.isEnabled)
        app.buttons["history-edit"].tap()
        XCTAssertTrue(stretch.isEnabled)
        stretch.tap(); XCTAssertEqual(stretch.value as? String, "Done")
        app.swipeDown()
        let otherDay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "6 October 2026")).firstMatch
        reveal(otherDay, in: app); otherDay.tap()
        XCTAssertFalse(stretch.isEnabled)
        XCTAssertTrue(app.buttons["history-edit"].exists)
    }

    @MainActor func testManagementRemainsUsableAtAccessibilitySize() {
        let app = launch("todayExtras", large: true)
        let manage = app.buttons["extras-manage"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5)); reveal(manage, in: app); manage.tap()
        let rename = app.buttons["Rename Stretch"]
        reveal(rename, in: app); rename.tap()
        let cancel = app.buttons["Cancel"]
        reveal(cancel, in: app); cancel.tap()
        XCTAssertTrue(app.buttons["Done"].isHittable)
    }
}
