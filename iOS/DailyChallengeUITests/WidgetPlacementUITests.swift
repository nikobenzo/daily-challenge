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

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
}
