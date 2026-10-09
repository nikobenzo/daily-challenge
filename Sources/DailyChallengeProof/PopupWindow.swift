import AppKit
import SwiftUI

/// Configures the real MenuBarExtra panel hosting the popup: transparent outside the
/// glass sheet and footer, any system material behind them masked out, a shadow that
/// follows the glass, and a content height that tracks the SwiftUI layout with the top
/// edge anchored under the menu bar. Only the MenuBarExtra panel is touched; test hosts
/// and other windows keep their own size and background.
struct PopupWindowAdapter: NSViewRepresentable {
    /// The popup's full content height (sheet + gap + footer), or nil before layout.
    let height: CGFloat?

    func makeNSView(context: Context) -> AdapterView { AdapterView() }

    func updateNSView(_ view: AdapterView, context: Context) {
        view.desiredHeight = height
        view.apply()
    }

    final class AdapterView: NSView {
        var desiredHeight: CGFloat?
        private var pendingResize = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        static func isMenuBarPanel(_ window: NSWindow) -> Bool {
            window is NSPanel || NSStringFromClass(type(of: window)).contains("MenuBarExtra")
        }

        func apply() {
            guard let window, Self.isMenuBarPanel(window) else { return }
            if window.isOpaque { window.isOpaque = false }
            if window.backgroundColor != .clear { window.backgroundColor = .clear }
            maskForeignMaterials(in: window.contentView?.superview ?? window.contentView)
            scheduleResize()
            window.invalidateShadow()
        }

        /// The system material would otherwise show in the gap between the sheet and the
        /// footer and around the 28 pt corners. Its subviews (our content) stay visible:
        /// maskImage only masks the material itself.
        private func maskForeignMaterials(in view: NSView?) {
            guard let view else { return }
            if let effect = view as? NSVisualEffectView, !(effect is GlassEffectView), effect.maskImage !== Self.clearMask {
                effect.maskImage = Self.clearMask
            }
            view.subviews.forEach(maskForeignMaterials)
        }

        private static let clearMask = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { _ in true }

        /// Never resize during SwiftUI's own update pass.
        private func scheduleResize() {
            guard !pendingResize else { return }
            pendingResize = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                pendingResize = false
                guard let window, let height = desiredHeight, height > 0 else { return }
                let content = window.contentRect(forFrameRect: window.frame)
                guard abs(content.height - height) > 0.5 else { return }
                var frame = window.frame
                let delta = height - content.height
                frame.size.height += delta
                frame.origin.y -= delta // keep the top edge under the menu bar
                window.setFrame(frame, display: true, animate: false)
                window.invalidateShadow()
            }
        }
    }
}

/// Animates the glass sheet's height whenever its content changes size and keeps the
/// popup window at least as tall as the animating glass, so nothing is cut: growing
/// enlarges the (transparent) window first, shrinking releases it after the animation.
struct AnimatedPopupStack<Sheet: View, Footer: View>: View {
    @ViewBuilder var sheet: () -> Sheet
    @ViewBuilder var footer: () -> Footer
    @Environment(\.trackerReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var displayed: CGFloat?
    @State private var held: CGFloat?
    @State private var settle: Task<Void, Never>?

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    private var chrome: CGFloat { Theme.Size.footerGap + Theme.Size.footerHeight }

    var body: some View {
        VStack(spacing: Theme.Size.footerGap) {
            sheet()
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { update(to: $0) }
                .frame(height: displayed, alignment: .top)
                .glassSheet()
            footer()
                .frame(height: Theme.Size.footerHeight)
        }
        .frame(width: Theme.Size.panelWidth)
        .frame(height: held, alignment: .top)
        // Controls draw the design's own focus halo (focusHalo) instead.
        .focusEffectDisabled()
        .background(PopupWindowAdapter(height: held))
    }

    private func update(to natural: CGFloat) {
        guard let current = displayed else {
            displayed = natural
            held = natural + chrome
            return
        }
        guard abs(natural - current) > 0.5 else { return }
        settle?.cancel()
        let total = natural + chrome
        if natural > current { held = total } else { held = max(held ?? 0, current + chrome) }
        withAnimation(reduceMotion ? Theme.Motion.reducedResize : Theme.Motion.sectionResize) { displayed = natural }
        guard natural < current else { return }
        settle = Task { @MainActor in
            try? await Task.sleep(for: Theme.Motion.resizeHold)
            guard !Task.isCancelled else { return }
            held = total
        }
    }
}
