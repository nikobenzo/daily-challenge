import AppKit
import SwiftUI

private struct PopupVisibleKey: EnvironmentKey { static let defaultValue = false }
private struct MotionOverrideKey: EnvironmentKey { static let defaultValue: Bool? = nil }
extension EnvironmentValues {
    /// Fixture-only injection; nil follows the live system accessibility setting.
    var trackerReduceMotionOverride: Bool? {
        get { self[MotionOverrideKey.self] }
        set { self[MotionOverrideKey.self] = newValue }
    }
    var trackerPopupVisible: Bool {
        get { self[PopupVisibleKey.self] }
        set { self[PopupVisibleKey.self] = newValue }
    }
}

/// Whether the popup is on screen; the menu-bar glyph fills while it is open.
@MainActor @Observable
final class PopupPresence {
    var isOpen = false
}

/// MenuBarExtra may retain its SwiftUI tree after dismissal. Native occlusion,
/// not just onDisappear, gates all presentation clocks.
struct PopupVisibilityReader: NSViewRepresentable {
    let changed: (Bool) -> Void
    func makeNSView(context: Context) -> ObserverView { ObserverView(changed: changed) }
    func updateNSView(_ view: ObserverView, context: Context) { view.changed = changed }

    final class ObserverView: NSView {
        var changed: (Bool) -> Void
        init(changed: @escaping (Bool) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                NotificationCenter.default.addObserver(self, selector: #selector(report),
                    name: NSWindow.didChangeOcclusionStateNotification, object: window)
            }
            report()
        }
        @objc private func report() {
            let visible = window.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false
            // Never mutate SwiftUI state during a native view update.
            Task { @MainActor [weak self] in self?.changed(visible) }
        }
    }
}
