import XCTest

/// Run explicitly on a disposable simulator; records the real SpringBoard UI.
final class WidgetPlacementUITests: XCTestCase {
    @MainActor func testPlaceWidgets() throws {
        // Opt in through a launch argument in the dedicated capture scheme.
        guard ProcessInfo.processInfo.arguments.contains("-capture-widgets") else {
            throw XCTSkip("Use the WidgetCapture scheme on an isolated simulator")
        }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "app.daily-challenge.ios")
        app.launchArguments = ["-widget-fixture", "partial"]
        app.launch()
        XCTAssertTrue(app.buttons["water-add"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        capture(board, "home-before-placement")
        for (page, name) in ["water-small", "water-medium", "requirements-medium", "extras-medium", "extras-large"].enumerated() {
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 1.5)
        capture(board, "home-edit-menu")
        let edit = board.buttons["Edit"]
        if edit.waitForExistence(timeout: 5) { edit.tap() }
        capture(board, "home-edit-options")
        let add = board.buttons["Add Widget"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), board.debugDescription)
        add.tap()
        capture(board, "widget-gallery")
        let search = board.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), board.debugDescription)
        search.tap()
        search.typeText("Daily Challenge")
        capture(board, "widget-search")
        let result = board.cells["Daily Challenge"]
        XCTAssertTrue(result.waitForExistence(timeout: 5), board.debugDescription)
        result.tap()
        capture(board, "daily-challenge-gallery")
        for _ in 0..<page {
            board.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: board.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)))
        }
        capture(board, "gallery-" + name)
        let addWidget = board.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "Add Widget")).firstMatch
        XCTAssertTrue(addWidget.waitForExistence(timeout: 5), board.debugDescription)
        addWidget.tap()
        let done = board.buttons["Done"]
        if done.waitForExistence(timeout: 5) { done.tap() }
        capture(board, "home-placed-" + name)
        }
    }

    @MainActor func testCaptureGalleryOnly() throws {
        guard ProcessInfo.processInfo.arguments.contains("-capture-widget-gallery") else {
            throw XCTSkip("Use the WidgetGalleryCapture scheme on an isolated simulator")
        }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "app.daily-challenge.ios")
        app.launchArguments = ["-widget-fixture", "partial"]
        app.launch()
        XCTAssertTrue(app.buttons["water-add"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 1.5)
        let edit = board.buttons["Edit"]
        if edit.waitForExistence(timeout: 5) { edit.tap() }
        let add = board.buttons["Add Widget"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let search = board.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Daily Challenge")
        let result = board.cells["Daily Challenge"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        for (index, name) in ["water-small", "water-medium", "requirements-medium", "extras-medium", "extras-large"].enumerated() {
            if index > 0 {
                board.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.6))
                    .press(forDuration: 0.1, thenDragTo: board.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.6)))
            }
            let title = index < 2 ? "Water" : index == 2 ? "Daily requirements" : "Extras"
            let preview = board.buttons["Daily Challenge, " + title]
            XCTAssertTrue(preview.waitForExistence(timeout: 5), board.debugDescription)
            let family = index == 0 ? "Small" : index == 4 ? "Large" : "Medium"
            XCTAssertTrue((preview.value as? String)?.contains(family) == true)
            capture(board, "gallery-" + name)
        }
    }

    /// Phase 4 end to end, offline: place the three kinds, terminate the fixture app,
    /// tap the placed widgets' controls (App Intents run in the extension), then
    /// relaunch on the same fixture history without reseeding and read Today/History.
    @MainActor func testWidgetActionsOffline() throws {
        guard ProcessInfo.processInfo.arguments.contains("-capture-widgets") else {
            throw XCTSkip("Use the WidgetCapture scheme on an isolated simulator")
        }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "app.daily-challenge.ios")
        app.launchArguments = ["-widget-fixture", "partial"] // 2,250 ml, workout and clean diet, 1/3 extras
        app.launch()
        XCTAssertTrue(app.buttons["water-add"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 1.5)
        for (page, name, title, family) in [(3, "extras-medium", "Extras", "Medium"),
                                            (2, "requirements-medium", "Daily requirements", "Medium"),
                                            (1, "water-medium", "Water", "Medium")] {
            let result = board.cells["Daily Challenge"], search = board.searchFields.firstMatch
            // One bounded retry: just after boot the first Add Widget tap can be dropped.
            for _ in 0..<2 where !search.exists && !result.exists {
                let edit = board.buttons["Edit"]
                XCTAssertTrue(edit.waitForExistence(timeout: 5), board.debugDescription)
                edit.tap()
                let add = board.buttons["Add Widget"]
                XCTAssertTrue(add.waitForExistence(timeout: 5), board.debugDescription)
                add.tap()
                _ = search.waitForExistence(timeout: 5)
            }
            if !result.waitForExistence(timeout: 2) {
                XCTAssertTrue(search.waitForExistence(timeout: 5), board.debugDescription)
                search.tap(); search.typeText("Daily Challenge")
            }
            XCTAssertTrue(result.waitForExistence(timeout: 5), board.debugDescription)
            result.tap()
            for _ in 0..<page {
                board.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.6))
                    .press(forDuration: 0.1, thenDragTo: board.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.6)))
            }
            let preview = board.buttons["Daily Challenge, " + title]
            XCTAssertTrue(preview.waitForExistence(timeout: 5), board.debugDescription)
            XCTAssertTrue((preview.value as? String)?.contains(family) == true, board.debugDescription)
            capture(board, "gallery-" + name)
            let addWidget = board.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "Add Widget")).firstMatch
            XCTAssertTrue(addWidget.waitForExistence(timeout: 5), board.debugDescription)
            addWidget.tap()
            sleep(2)
        }
        let done = board.buttons["Done"]
        if done.waitForExistence(timeout: 5) { done.tap() }
        app.terminate()
        XCTAssertEqual(app.state, .notRunning)
        sleep(3)
        capture(board, "home-placed-actions-before")
        // Extras and walk first, then plus twice and minus once: 2,250 + 450 + 450 − 450 = 2,700 ml.
        // The water total is awaited last, so the final capture shows every redraw.
        for label in ["Read a chapter, pending", "Walk · 45 min, pending", "Add 450 ml", "Add 450 ml", "Undo latest pour"] {
            let control = board.buttons[label].firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 10), board.debugDescription)
            control.tap()
            sleep(3) // the intent commits, then WidgetKit reloads the timeline
        }
        XCTAssertEqual(app.state, .notRunning)
        let updated = board.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "2,700 ml")).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 10), board.debugDescription)
        let extras = board.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Extras · 2/3")).firstMatch
        XCTAssertTrue(extras.waitForExistence(timeout: 20), board.debugDescription)
        // The accessibility tree updates before SpringBoard redraws the last-tapped
        // widget's image; let the touch interaction end before the pixel capture.
        // A tap on empty wallpaper (between the last widget and Search) does nothing.
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.785)).tap()
        sleep(6)
        capture(board, "home-placed-actions-after")
        app.launchArguments = ["-widget-fixture", "reopen"]
        app.launch()
        let total = app.descendants(matching: .any)["water-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        XCTAssertEqual(total.label, "2,700 of 4,000 millilitres")
        XCTAssertEqual(app.buttons["ring-walk"].value as? String, "Complete")
        XCTAssertEqual(app.descendants(matching: .any)["extras-count"].label, "Extras, 2 of 3 done")
        capture(app, "app-today-after-widget-actions")
        app.tabBars.buttons["History"].tap()
        sleep(2)
        capture(app, "app-history-after-widget-actions")
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
}
