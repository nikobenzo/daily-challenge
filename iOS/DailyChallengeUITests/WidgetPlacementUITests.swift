import ObjectiveC
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

    /// Tap mapping on the placed widgets (`-widget-fixture extras-eight`: eight extras,
    /// two Cyrillic, four ticked). Every tap must flip exactly the tapped row, read back
    /// from SpringBoard's accessibility tree: one row at a time with the timeline
    /// settled, then rapid taps before it reloads. `WIDGET_PLACE=1` places Extras large
    /// and Daily requirements (layout c) or Extras medium and Daily requirements (layout d).
    @MainActor func testWidgetTapMapping() throws {
        guard ProcessInfo.processInfo.arguments.contains("-capture-widgets") else {
            throw XCTSkip("Use the WidgetCapture scheme on an isolated simulator")
        }
        let environment = ProcessInfo.processInfo.environment
        let layout = environment["WIDGET_LAYOUT"] ?? "c"
        let app = XCUIApplication(bundleIdentifier: "app.daily-challenge.ios")
        let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        continueAfterFailure = true
        if environment["WIDGET_PLACE"] == "1" {
            app.launchArguments = ["-widget-fixture", "extras-eight"]
            app.launch()
            XCTAssertTrue(app.buttons["water-add"].waitForExistence(timeout: 10))
            XCUIDevice.shared.press(.home)
            board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 1.5)
            let extras = layout == "d" ? (3, "extras-medium", "Extras", "Medium") : (4, "extras-large", "Extras", "Large")
            for (page, name, title, family) in [(2, "requirements-medium", "Daily requirements", "Medium"), extras] {
                addWidget(board, page: page, name: name, title: title, family: family)
            }
            let done = board.buttons["Done"]
            if done.waitForExistence(timeout: 5) { done.tap() }
            sleep(2)
        }
        app.launchArguments = ["-widget-fixture", "extras-eight"]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)
        sleep(2)
        XCUIDevice.shared.press(.home)
        app.terminate()
        let titles = layout == "d" ? Array(Self.tapTitles.prefix(3)) : Self.tapTitles
        var expected = Dictionary(uniqueKeysWithValues: titles.map { ($0, Self.tapDone.contains($0)) })
        let first = row(board, titles[0])
        for (from, to) in [(0.1, 0.9), (0.1, 0.9), (0.9, 0.1), (0.9, 0.1), (0.9, 0.1)] where !first.waitForExistence(timeout: 4) {
            board.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: board.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.5)))
            sleep(1)
        }
        XCTAssertTrue(first.waitForExistence(timeout: 15), board.debugDescription)
        sleep(3)
        capture(board, "tap-\(layout)-before")
        XCTAssertEqual(states(board, titles), expected, "fixture state")

        // `WIDGET_RAPID_ROUNDS=n` measures only n rapid rounds, `WIDGET_RAPID_GAP_MS` apart.
        let stress = environment["WIDGET_RAPID_ROUNDS"].flatMap(Int.init)
        // Settled: one row at a time, waiting for the reload to land before the next tap.
        for (index, title) in (stress == nil ? titles + titles.reversed() : []).enumerated() {
            row(board, title).tap()
            expected[title]!.toggle()
            XCTAssertTrue(wait(board, title, done: expected[title]!), "tap \(index) on \(title) never flipped it")
            sleep(1)
            let read = states(board, titles)
            XCTAssertEqual(read, expected, "settled tap \(index) on \(title)")
            capture(board, "tap-\(layout)-settled-\(index)")
        }
        // Rapid, as a person taps: XCUITest normally waits for SpringBoard to go idle
        // (the reload to land) before each event, which hides overlapping intents. Tap
        // fixed row coordinates with that wait skipped; a 300 ms gap plus the event's own
        // cost lands taps about 0.8 s apart, the pace of the recording.
        let frames = Dictionary(uniqueKeysWithValues: titles.map { ($0, row(board, $0).frame) })
        let rapid = titles.count > 3 ? [titles[7], titles[6], titles[5], titles[4], titles[3], titles[2], titles[1]] : [titles[2], titles[1], titles[0]]
        let gap = useconds_t((environment["WIDGET_RAPID_GAP_MS"].flatMap(Int.init) ?? 300) * 1_000)
        var lost = 0
        for round in 0..<(stress ?? 2) {
            Self.skipQuiescence(true)
            for title in rapid {
                board.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: frames[title]!.midX, dy: frames[title]!.midY)).tap()
                expected[title]!.toggle()
                usleep(gap)
            }
            Self.skipQuiescence(false)
            sleep(8)
            let read = states(board, titles)
            let missed = titles.filter { read[$0] != expected[$0] }
            lost += missed.count
            XCTAssertEqual(read, expected, "after rapid round \(round) \(rapid): lost \(missed)")
            capture(board, "tap-\(layout)-rapid-\(round)")
            expected = read // a lost tap is reported once, not in every later round
        }
        let report = XCTAttachment(string: "rapid taps \(gap / 1_000) ms apart: lost \(lost) of \(rapid.count * (stress ?? 2))")
        report.name = "tap-\(layout)-rapid-summary"; report.lifetime = .keepAlways; add(report)
        if stress != nil { return }
        // Daily requirements share the intent path: workout off, walk on, Bible on, then back.
        var rings = ["Workout": true, "Walk": false, "Bible": false]
        for name in ["Workout", "Walk", "Bible", "Walk", "Workout", "Bible"] {
            board.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ", ")).firstMatch.tap()
            rings[name]!.toggle()
            let label = rings[name]! ? "done" : "pending"
            let ring = board.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", name + ", ", ", " + label)).firstMatch
            XCTAssertTrue(ring.waitForExistence(timeout: 10), "\(name) never became \(label)")
            sleep(1)
            for (other, done) in rings {
                let read = board.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", other + ", ")).firstMatch.label
                XCTAssertTrue(read.hasSuffix(done ? ", done" : ", pending"), "after \(name): \(read)")
            }
        }
        // The same rings back to back, at the rapid pace.
        let ringFrames = Dictionary(uniqueKeysWithValues: rings.keys.map { name in
            (name, board.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ", ")).firstMatch.frame)
        })
        Self.skipQuiescence(true)
        for name in ["Walk", "Bible", "Workout", "Bible", "Walk"] {
            board.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: ringFrames[name]!.midX, dy: ringFrames[name]!.midY)).tap()
            rings[name]!.toggle()
            usleep(gap)
        }
        Self.skipQuiescence(false)
        sleep(8)
        for (name, done) in rings {
            let read = board.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ", ")).firstMatch.label
            XCTAssertTrue(read.hasSuffix(done ? ", done" : ", pending"), "after rapid ring taps: \(read)")
        }
        capture(board, "tap-\(layout)-requirements")
    }

    /// XCUITest's idle waits before and after each synthesized event (private
    /// XCUIApplicationProcess switches); restored right after the rapid taps.
    static func skipQuiescence(_ skip: Bool) {
        guard let process = NSClassFromString("XCUIApplicationProcess") else { return XCTFail("no XCUIApplicationProcess") }
        for name in ["shouldSkipPreEventQuiescence", "shouldSkipPostEventQuiescence"] {
            guard let method = class_getInstanceMethod(process, NSSelectorFromString(name)) else { return XCTFail("no \(name)") }
            let body: @convention(block) (AnyObject) -> Bool = { _ in skip }
            method_setImplementation(method, imp_implementationWithBlock(body))
        }
    }

    static let tapTitles = ["Testing1", "Go shopping", "Get fairy", "Cancel subscription", "Call mama", "Позвонить маме", "Света", "Игорь"]
    static let tapDone: Set<String> = ["Testing1", "Call mama", "Позвонить маме", "Света"]

    @MainActor private func row(_ board: XCUIApplication, _ title: String) -> XCUIElement {
        board.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title + ", ")).firstMatch
    }

    @MainActor private func wait(_ board: XCUIApplication, _ title: String, done: Bool) -> Bool {
        board.buttons.matching(NSPredicate(format: "label == %@", title + (done ? ", done" : ", pending"))).firstMatch
            .waitForExistence(timeout: 10)
    }

    @MainActor private func states(_ board: XCUIApplication, _ titles: [String]) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: titles.map { ($0, row(board, $0).label.hasSuffix(", done")) })
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

    /// Widget animations on the placed layout a (`WIDGET_PLACE=1` places it first): reseed
    /// `partial`, then tap + and − , the walk ring and the "Read a chapter" extra on and off,
    /// pausing after each so the simulator recording that `capture-widgets.sh` mode
    /// `animations` runs around this test shows every entry change.
    @MainActor func testWidgetAnimations() throws {
        guard ProcessInfo.processInfo.arguments.contains("-capture-widgets") else {
            throw XCTSkip("Use the WidgetCapture scheme on an isolated simulator")
        }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "app.daily-challenge.ios")
        let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launchArguments = ["-widget-fixture", "partial"]
        app.launch()
        XCTAssertTrue(app.buttons["water-add"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        if ProcessInfo.processInfo.environment["WIDGET_PLACE"] == "1" {
            board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 1.5)
            for (page, name, title, family) in [(3, "extras-medium", "Extras", "Medium"),
                                                (2, "requirements-medium", "Daily requirements", "Medium"),
                                                (1, "water-medium", "Water", "Medium")] {
                addWidget(board, page: page, name: name, title: title, family: family)
            }
            let done = board.buttons["Done"]
            if done.waitForExistence(timeout: 5) { done.tap() }
        }
        app.terminate()
        showWidgetPage(board)
        sleep(4)
        for label in ["Add 450 ml", "Add 450 ml", "Undo latest pour", "Walk, 45 minutes, pending", "Walk, 45 minutes, done",
                      "Read a chapter, pending", "Read a chapter, done"] {
            let control = board.buttons[label].firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 10), board.debugDescription)
            control.tap()
            sleep(4) // the intent commits, WidgetKit reloads and animates the new entry
        }
        capture(board, "home-placed-animations-after")
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
            if variant == "carry-over" { labels.append("Stretch, late, pending") }
            if layout == "a" {
                labels.append(["pending", "empty"].contains(variant) ? "Workout, 45 minutes, home or gym, pending" : "Workout, 45 minutes, home or gym, done")
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
