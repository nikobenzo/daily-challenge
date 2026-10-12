import Foundation

/// The welcome window's four steps, in order (docs/tracker-interface.md#first-launch).
enum WelcomeStep: Int, CaseIterable, Comparable {
    case menuBar, account, startDate, logDay

    static func < (lhs: WelcomeStep, rhs: WelcomeStep) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What decides whether this Mac still needs the welcome window.
struct FirstRunState: Equatable {
    /// Stored on this Mac once setup finished here or an existing user was seen.
    var finished = false
    /// A challenge file of any account already on this Mac: an upgraded install.
    var hasLocalHistory = false
    /// The saved session has been read; before that, signed out may only mean "not yet".
    var sessionRestored = false
    var signedIn = false
    var hasChallenge = false
    /// The popup has been opened from the menu bar item at least once.
    var openedPopup = false

    enum Decision: Equatable {
        /// Waiting for the saved session before deciding.
        case wait
        /// Existing user or setup done: never show the welcome window again on this Mac.
        case finished
        /// Show (or keep showing) the welcome window at this step.
        case show(WelcomeStep)
    }

    var decision: Decision {
        if finished || hasLocalHistory { return .finished }
        guard sessionRestored else { return .wait }
        if signedIn { return hasChallenge ? .finished : .show(.startDate) }
        return .show(openedPopup ? .account : .menuBar)
    }
}

/// The device-local record that the welcome window is no longer needed. Like the
/// appearance choice, it is never synced: each Mac shows its own first run once.
@MainActor
struct FirstRunStore {
    static let finishedKey = "firstRunFinished"
    let defaults: UserDefaults

    var finished: Bool {
        get { defaults.bool(forKey: Self.finishedKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.finishedKey) }
    }

    /// Whether any account's challenge file (`challenge-<owner>.json`) is in the directory.
    nonisolated static func hasLocalHistory(in directory: URL) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.contains { $0.hasPrefix("challenge-") && $0.hasSuffix(".json") }
    }
}
