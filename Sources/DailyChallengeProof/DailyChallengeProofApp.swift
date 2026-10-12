import AppKit
import ChallengeSyncKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var popup: PopupController?
    private var welcome: WelcomeController?
    private var reminderLifecycle: MacReminderLifecycle?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, also when run without the bundle's LSUIElement.
        NSApp.setActivationPolicy(.accessory)
        // Developer-only popup verification on offline fixtures; nil in normal use.
        if let probe = PopupProbe.current {
            let models = probe.models()
            let popup = PopupController(content: TrackerPopup(model: models.tracker, auth: models.auth,
                                                              appearance: models.appearance, section: probe.section)
                .environment(SoftwareUpdates(fixtureAvailableVersion: nil)))
            self.popup = popup
            if probe.screen.isWelcome {
                welcome = WelcomeController(auth: models.auth, tracker: models.tracker, popup: popup,
                                            firstRun: FirstRunStore(defaults: models.defaults),
                                            hasLocalHistory: FirstRunStore.hasLocalHistory(in: models.directory),
                                            reduceMotion: probe.reduceMotion)
                welcome?.start()
                Task { await probe.runWelcome(popup, welcome: welcome!, tracker: models.tracker) }
            } else {
                Task { await probe.run(popup) }
            }
            return
        }
        let auth = ProofModel()
        let tracker = TrackerModel()
        let reminders = WaterReminderController(defaults: .standard, center: NativeWaterNotificationCenter(), wording: .mac)
        tracker.reminders = reminders
        let lifecycle = MacReminderLifecycle(reminders: reminders)
        lifecycle.start { [weak tracker] in tracker?.refreshReminders() }
        reminderLifecycle = lifecycle
        auth.attachTracker(tracker)
        auth.start()
        // The app's single Sparkle updater; it checks daily once started.
        let updates = SoftwareUpdates()
        let popup = PopupController(content: TrackerPopup(model: tracker, auth: auth, appearance: AppAppearance())
            .environment(updates))
        self.popup = popup
        // First launch: a welcome window with the steps, until signed in with a challenge.
        welcome = WelcomeController(auth: auth, tracker: tracker, popup: popup, firstRun: FirstRunStore(defaults: .standard),
                                    hasLocalHistory: FirstRunStore.hasLocalHistory(in: TrackerModel.defaultDirectory))
        welcome?.start()
    }

    /// Opening the app again while it runs (Finder, Spotlight, `open`) shows where it lives:
    /// the welcome window while it is up, otherwise the popup under the menu-bar item.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if welcome?.bringToFront() != true { popup?.open() }
        return false
    }
}

/// The app's main menu. It is never shown (the app has no menu bar of its own), but its key
/// equivalents are how text fields get Cut, Copy, Paste, Select All and Undo, and how
/// Command-W closes the welcome window and Command-Q quits.
enum AppMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu
            main.addItem(item)
        }
        func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return item
        }
        submenu("Daily Challenge", [item("Quit Daily Challenge", #selector(NSApplication.terminate(_:)), "q")])
        submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a")
        ])
        submenu("Window", [item("Close", #selector(NSWindow.performClose(_:)), "w")])
        return main
    }
}
