import AppKit

struct FixtureVisibilityInterval {
    let expectedVisible: Bool
    private(set) var isValid = true

    init(expectedVisible: Bool, initialVisible: Bool) {
        self.expectedVisible = expectedVisible
        observe(initialVisible)
    }

    mutating func observe(_ visible: Bool) {
        isValid = isValid && visible == expectedVisible
    }
}

@MainActor final class FixtureVisibilityMonitor: NSObject {
    let window: NSWindow
    private var interval: FixtureVisibilityInterval?

    init(window: NSWindow) {
        self.window = window
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(changed),
            name: NSWindow.didChangeOcclusionStateNotification, object: window)
    }

    private var visible: Bool { window.isVisible && window.occlusionState.contains(.visible) }

    func begin(expectedVisible: Bool) {
        interval = FixtureVisibilityInterval(expectedVisible: expectedVisible, initialVisible: visible)
    }

    func validate() -> Bool {
        changed()
        return interval?.isValid == true
    }

    @objc private func changed() {
        interval?.observe(visible)
    }
}
