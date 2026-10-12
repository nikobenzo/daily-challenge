import AppKit
import ChallengeSyncKit
import Observation
import SwiftUI

/// What the welcome window shows; the controller keeps it current.
@MainActor @Observable
final class WelcomeModel {
    var step = WelcomeStep.menuBar
    /// Setup finished while the window was up: the celebration replaces the steps.
    var celebrating = false
    /// "Mon 12 Oct", the challenge's first day, once it starts.
    var startLabel = ""
    /// Opens the popup at the sign-in screen (or setup once signed in).
    var openPopup: (AuthStep?) -> Void = { _ in }
    var close: () -> Void = {}
}

/// The first-run welcome window (docs/tracker-interface.md#first-launch). Shown at launch
/// until this Mac has an account signed in with a challenge, never for existing users;
/// it follows the real auth and tracker state, celebrates when the challenge starts and
/// then closes itself.
@MainActor
final class WelcomeController: NSObject, NSWindowDelegate {
    /// How long the celebration stays up before the window closes itself.
    static let celebrationHold: Duration = .seconds(8)

    let model = WelcomeModel()
    private let auth: ProofModel
    private let tracker: TrackerModel
    private weak var popup: PopupController?
    private let firstRun: FirstRunStore
    private let hasLocalHistory: Bool
    private let reduceMotion: Bool?
    private(set) var window: NSWindow?
    private var openedPopup = false
    /// Closed by the person this launch; it comes back at the next launch until setup is done.
    private var dismissed = false
    private var settled = false
    private var closeTask: Task<Void, Never>?

    init(auth: ProofModel, tracker: TrackerModel, popup: PopupController?, firstRun: FirstRunStore,
         hasLocalHistory: Bool, reduceMotion: Bool? = nil) {
        self.auth = auth
        self.tracker = tracker
        self.popup = popup
        self.firstRun = firstRun
        self.hasLocalHistory = hasLocalHistory
        self.reduceMotion = reduceMotion
        super.init()
        model.openPopup = { [weak self] step in self?.openPopup(at: step) }
        model.close = { [weak self] in self?.window?.performClose(nil) }
        popup?.onOpen = { [weak self] in
            guard let self, !openedPopup else { return }
            openedPopup = true
            evaluate()
        }
    }

    var state: FirstRunState {
        FirstRunState(finished: firstRun.finished, hasLocalHistory: hasLocalHistory, sessionRestored: auth.sessionRestored,
                      signedIn: auth.ownerID != nil, hasChallenge: tracker.challenge != nil, openedPopup: openedPopup)
    }

    func start() { evaluate() }

    /// Brings the window forward if it is up; false when there is none.
    @discardableResult func bringToFront() -> Bool {
        guard let window, window.isVisible else { return false }
        NSApp.activate()
        window.orderFrontRegardless()
        window.makeKey()
        return true
    }

    private func evaluate() {
        guard !settled else { return }
        // Re-evaluate whenever the session, the account or the challenge changes.
        withObservationTracking {
            _ = (auth.sessionRestored, auth.ownerID, tracker.challenge)
        } onChange: { [weak self] in
            Task { @MainActor in self?.evaluate() }
        }
        switch state.decision {
        case .wait:
            return
        case .finished:
            settled = true
            firstRun.finished = true
            if let window, window.isVisible { celebrate(in: window) }
        case .show(let step):
            model.step = step
            if window == nil, !dismissed { present() }
        }
    }

    private func openPopup(at step: AuthStep?) {
        if let step, auth.ownerID == nil { auth.show(step) }
        popup?.open()
    }

    private func present() {
        let hosting = NSHostingView(rootView: WelcomeView(model: model)
            .environment(\.trackerReduceMotionOverride, reduceMotion))
        let window = WelcomeWindow(contentRect: CGRect(origin: .zero, size: hosting.fittingSize),
                                   styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Welcome to Daily Challenge"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.delegate = self
        let size = hosting.fittingSize
        let anchor = popup?.statusButton?.window?.frame
        let screen = NSScreen.screens.first { anchor.map($0.frame.intersects) ?? false } ?? NSScreen.main
        window.setFrame(Self.frame(size: window.frameRect(forContentRect: CGRect(origin: .zero, size: size)).size,
                                   statusItem: anchor, visibleFrame: screen?.visibleFrame ?? CGRect(origin: .zero, size: size)),
                        display: false)
        self.window = window
        // In front even when macOS keeps another app active (a launch from Terminal).
        NSApp.activate()
        window.orderFrontRegardless()
        window.makeKey()
    }

    /// Under the menu bar and to the left of the status item, where the popup opens, so
    /// the two never overlap; centred when the item is too far left for that.
    nonisolated static func frame(size: CGSize, statusItem: CGRect?, visibleFrame: CGRect) -> CGRect {
        let gap: CGFloat = 24
        let top = visibleFrame.maxY - gap
        let centred = visibleFrame.midX - size.width / 2
        var x = centred
        if let statusItem {
            // The popup's glass starts at the item's left edge.
            let besidePopup = statusItem.minX - gap - size.width
            if besidePopup >= visibleFrame.minX + gap { x = min(centred, besidePopup) }
        }
        x = min(max(x, visibleFrame.minX + gap), visibleFrame.maxX - gap - size.width)
        return CGRect(x: x, y: max(visibleFrame.minY, top - size.height), width: size.width, height: size.height)
    }

    private func celebrate(in window: NSWindow) {
        model.startLabel = tracker.challenge.map { tracker.dates.label($0.startDate) } ?? ""
        model.celebrating = true
        // In front of other windows, without taking the keyboard from the popup.
        window.orderFront(nil)
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.celebrationHold)
            guard !Task.isCancelled else { return }
            self?.window?.close()
        }
    }

    func windowWillClose(_ notification: Notification) {
        closeTask?.cancel()
        dismissed = true
        window = nil
    }
}

/// Escape closes the welcome window, as it does a sheet.
final class WelcomeWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}
