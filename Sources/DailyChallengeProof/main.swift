import AppKit

// A plain AppKit entry point rather than a SwiftUI App. The app's only window is its own
// popup panel (PopupController), and a SwiftUI App must declare at least one scene: with
// `Settings { EmptyView() }` as that scene, macOS opened an empty "Daily Challenge Settings"
// window at every launch (docs/tracker-interface.md#first-launch). With no scene, nothing
// can open a window the app did not create itself.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.mainMenu = AppMenu.make()
NSApplication.shared.run()
