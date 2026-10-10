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
        // A freshly installed extension can take a few seconds to reach the gallery.
        for _ in 0..<3 where !result.waitForExistence(timeout: 5) {
            board.buttons["Clear text"].tap()
            sleep(5)
            search.typeText("Daily Challenge")
        }
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
            addWidget(board, page: page, name: name, title: title, family: family)
        }
        let done = board.buttons["Done"]
        if done.waitForExistence(timeout: 5) { done.tap() }
        app.terminate()
        XCTAssertEqual(app.state, .notRunning)
        sleep(3)
        capture(board, "home-placed-actions-before")
        // Extras and walk first, then plus twice and minus once: 2,250 + 450 + 450 − 450 = 2,700 ml.
        // The water total is awaited last, so the final capture shows every redraw.
        for label in ["Read a chapter, pending", "Walk, 45 minutes, pending", "Add 450 ml", "Add 450 ml", "Undo latest pour"] {
            let control = board.buttons[label].firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 10), board.debugDescription)
            control.tap()
            sleep(3) // the intent commits, then WidgetKit reloads the timeline
        }
        XCTAssertEqual(app.state, .notRunning)
        let updated = board.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Water, 2,700 of 4,000 millilitres")).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 10), board.debugDescription)
        let extras = board.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Extras, 2 of 3 done")).firstMatch
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

    /// Phase 5, driven only through SpringBoard XCUITest. Environment (set by
    /// `iOS/scripts/capture-widgets.sh` through `TEST_RUNNER_` variables):
    /// `WIDGET_LAYOUT` a = Water, Daily requirements and Extras medium; b = Water small and
    /// Extras large. `WIDGET_PLACE=1` places the layout first; otherwise the widgets placed
    /// by an earlier run stay. `WIDGET_HOME_STYLE` tinted|clear switches the Home Screen
    /// style. Each `WIDGET_VARIANTS` entry relaunches `-widget-fixture <variant>`, which
    /// reseeds the synthetic group and reloads timelines, then captures the placed
    /// widgets with `WIDGET_TAG` in the name. Spoken values are asserted from SpringBoard.
    @MainActor func testPhase5Home() throws {
        guard ProcessInfo.processInfo.arguments.contains("-capture-widgets") else {
            throw XCTSkip("Use the WidgetCapture scheme on an isolated simulator")
        }
        let environment = ProcessInfo.processInfo.environment
        let layout = environment["WIDGET_LAYOUT"] ?? "a"
        let variants = (environment["WIDGET_VARIANTS"] ?? "partial").split(separator: ",").map(String.init)
        let tag = environment["WIDGET_TAG"].map { "-" + $0 } ?? ""
        let app = XCUIApplication(bundleIdentifier: "app.daily-challenge.ios")
        let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if environment["WIDGET_PLACE"] == "1" {
            continueAfterFailure = false
            app.launchArguments = ["-widget-fixture", "partial"]
            app.launch()
            XCTAssertTrue(app.buttons["water-add"].waitForExistence(timeout: 10))
            XCUIDevice.shared.press(.home)
            board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 1.5)
            let pages = layout == "b"
                ? [(4, "extras-large", "Extras", "Large"), (0, "water-small", "Water", "Small")]
                : [(3, "extras-medium", "Extras", "Medium"), (2, "requirements-medium", "Daily requirements", "Medium"),
                   (1, "water-medium", "Water", "Medium")]
            for (page, name, title, family) in pages { addWidget(board, page: page, name: name, title: title, family: family) }
            let done = board.buttons["Done"]
            if done.waitForExistence(timeout: 5) { done.tap() }
            sleep(2)
            capture(board, "debug-after-placement")
        }
        if let style = environment["WIDGET_HOME_STYLE"] { setHomeStyle(board, style) }
        continueAfterFailure = true
        for variant in variants {
            app.launchArguments = ["-widget-fixture", variant]
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 10)
            sleep(2)
            XCUIDevice.shared.press(.home)
            app.terminate()
            showWidgetPage(board)
            for expected in Self.spoken(variant, layout: layout) {
                let element = board.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", expected)).firstMatch
                XCTAssertTrue(element.waitForExistence(timeout: 15), "\(variant): no SpringBoard element reads \"\(expected)\"")
            }
            sleep(4) // the accessibility tree can update before SpringBoard redraws pixels
            capture(board, "home-placed-\(layout)-\(variant)\(tag)")
        }
    }

    /// D-W2 Lock Screen ring on the simulator's Cover Sheet: pull it down, long-press,
    /// Customise → Lock Screen → add the Daily Challenge water ring, then relaunch each
    /// `WIDGET_VARIANTS` fixture and capture the Cover Sheet. A simulator has no passcode,
    /// so this is the unlocked presentation; the redacted (locked) rendering is not shown here.
    @MainActor func testPhase5LockScreen() throws {
        guard ProcessInfo.processInfo.arguments.contains("-capture-widgets") else {
            throw XCTSkip("Use the WidgetCapture scheme on an isolated simulator")
        }
        continueAfterFailure = false
        let variants = (ProcessInfo.processInfo.environment["WIDGET_VARIANTS"] ?? "partial").split(separator: ",").map(String.init)
        let app = XCUIApplication(bundleIdentifier: "app.daily-challenge.ios")
        let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launchArguments = ["-widget-fixture", "partial"]
        app.launch()
        XCTAssertTrue(app.buttons["water-add"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        showCoverSheet(board)
        capture(board, "debug-lock-cover")
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(forDuration: 2)
        sleep(1)
        capture(board, "debug-lock-gallery")
        let customise = board.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Customi")).firstMatch
        XCTAssertTrue(customise.waitForExistence(timeout: 5), board.debugDescription)
        customise.tap()
        sleep(1)
        capture(board, "debug-lock-customise")
        let lockScreen = board.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Lock Screen")).firstMatch
        if lockScreen.waitForExistence(timeout: 5) { lockScreen.tap(); sleep(2) }
        capture(board, "debug-lock-editor")
        let addWidgets = board.buttons.matching(identifier: "grouped-widgets-reticle-view").firstMatch
        XCTAssertTrue(addWidgets.waitForExistence(timeout: 5), board.debugDescription)
        addWidgets.tap()
        sleep(2)
        capture(board, "debug-lock-picker")
        // The picker lists apps alphabetically; expand the sheet and scroll to Daily Challenge.
        let entry = board.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "Daily Challenge")).firstMatch
        let grabber = board.buttons["Sheet Grabber"]
        if grabber.exists {
            grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
            sleep(1)
        }
        for _ in 0..<6 where !(entry.exists && entry.isHittable) {
            board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
            sleep(1)
        }
        capture(board, "lock-gallery-water-circular")
        XCTAssertTrue(entry.waitForExistence(timeout: 5), board.debugDescription)
        entry.tap()
        sleep(2)
        let preview = board.buttons["Daily Challenge, Water"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5), board.debugDescription)
        XCTAssertEqual(preview.value as? String, "Widget, Circular")
        preview.tap()
        sleep(2)
        capture(board, "debug-lock-added")
        let close = board.buttons.matching(NSPredicate(format: "label ==[c] %@", "close")).firstMatch
        if close.waitForExistence(timeout: 3) { close.tap(); sleep(1) }
        // Close returns to the app list; drag the picker sheet away to reach Done.
        let sheet = board.buttons["Sheet Grabber"]
        if sheet.waitForExistence(timeout: 3) {
            sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
            sleep(2)
        }
        capture(board, "debug-lock-closed")
        let done = board.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "editing-done", "Done")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 8), board.debugDescription)
        done.tap()
        sleep(2)
        // Done returns to the wallpaper switcher; choosing the edited poster shows it.
        let poster = board.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", "posterboard-posteruuid")).firstMatch
        if poster.waitForExistence(timeout: 5) { poster.tap(); sleep(2) }
        capture(board, "debug-lock-after-done")
        continueAfterFailure = true
        for variant in variants {
            app.launchArguments = ["-widget-fixture", variant]
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 10)
            sleep(2)
            XCUIDevice.shared.press(.home)
            app.terminate()
            showCoverSheet(board)
            for expected in Self.spoken(variant, layout: "lock").prefix(1) {
                let element = board.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", expected)).firstMatch
                XCTAssertTrue(element.waitForExistence(timeout: 15), "\(variant): no Lock Screen element reads \"\(expected)\"")
            }
            sleep(3)
            capture(board, "lock-placed-water-\(variant)")
            XCUIDevice.shared.press(.home)
            sleep(1)
        }
    }

    @MainActor private func showCoverSheet(_ board: XCUIApplication) {
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.005))
            .press(forDuration: 0.05, thenDragTo: board.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7)))
        sleep(2)
    }

    /// Home can return to a page other than the placed widgets' page: look right, then left.
    @MainActor private func showWidgetPage(_ board: XCUIApplication) {
        let widget = board.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@ OR label CONTAINS %@", "Water, ", "Open Daily Challenge")).firstMatch
        for (index, (from, to)) in [(0.1, 0.9), (0.1, 0.9), (0.9, 0.1), (0.9, 0.1), (0.9, 0.1)].enumerated()
            where !widget.waitForExistence(timeout: 4) {
            capture(board, "debug-page-\(index)")
            board.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: board.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.5)))
            sleep(1)
        }
    }

    /// What VoiceOver reads from the placed widgets for each fixture variant.
    static func spoken(_ variant: String, layout: String) -> [String] {
        let water = ["empty": "0", "pending": "0", "extras-empty": "0", "full": "4,000", "complete": "4,000", "overflow": "4,500"][variant] ?? "2,250"
        switch variant {
        case "signed-out": return ["Open Daily Challenge to sign in"]
        case "setup": return ["Open Daily Challenge to set up"]
        case "unavailable": return ["Open Daily Challenge"]
        default:
            var labels = ["Water, \(water) of 4,000 millilitres"]
            let extras: [String: String?] = ["extras-ten": "1 of 10", "long-names": "1 of 10", "overflow": "1 of 10", "extras-empty": nil, "empty": nil]
            if let count = extras[variant] ?? "1 of 3" { labels.append("Extras, \(count) done") }
            if layout == "a" {
                labels.append(["pending", "empty"].contains(variant) ? "Workout, 45 min · home / gym, pending" : "Workout, 45 min · home / gym, done")
                if variant == "missed" { labels.append("Clean diet, missed") }
            }
            return labels
        }
    }

    /// Edit → Add Widget → Daily Challenge → gallery page → Add Widget (Phase 4 procedure).
    @MainActor private func addWidget(_ board: XCUIApplication, page: Int, name: String, title: String, family: String) {
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
        // A freshly installed extension can take a few seconds to reach the gallery.
        for _ in 0..<3 where !result.waitForExistence(timeout: 5) {
            board.buttons["Clear text"].tap()
            sleep(5)
            search.typeText("Daily Challenge")
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

    /// Home Screen Edit → Customize → Tinted / Clear / Default, then dismiss.
    @MainActor private func setHomeStyle(_ board: XCUIApplication, _ style: String) {
        XCUIDevice.shared.press(.home)
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)).press(forDuration: 1.5)
        let edit = board.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), board.debugDescription)
        edit.tap()
        let customize = board.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Customi")).firstMatch
        XCTAssertTrue(customize.waitForExistence(timeout: 5), board.debugDescription)
        customize.tap()
        capture(board, "debug-customise")
        let option = board.buttons[style.capitalized]
        XCTAssertTrue(option.waitForExistence(timeout: 5), board.debugDescription)
        option.tap()
        sleep(1)
        capture(board, "home-customize-\(style)")
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        sleep(1)
        let done = board.buttons["Done"]
        if done.waitForExistence(timeout: 3) { done.tap() }
        sleep(1)
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
}
