import AppKit
import SwiftUI

/// The popup panel keeps its SwiftUI tree between openings. Native occlusion,
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
