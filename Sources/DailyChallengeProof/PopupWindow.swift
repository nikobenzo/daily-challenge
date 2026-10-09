import AppKit
import SwiftUI

/// The menu-bar item and the popup it opens: the app's own status item toggling a
/// borderless, non-activating, transparent panel that hosts TrackerPopup.
///
/// SwiftUI's MenuBarExtra(.window) is not used: on macOS 27 the system presents it through
/// a scene session that sizes the window from the root's minimum size, fills it with its own
/// backdrop and never animates or shrinks it, so the 420 pt glass sheet could not be shown
/// as designed (docs/design-system.md#popup-window).
@MainActor
final class PopupController: NSObject {
    let panel: PopupPanel
    private let statusItem: NSStatusItem
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []

    init(content: some View) {
        panel = PopupPanel(content: content)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggle)
            // Menu-bar items respond on press, like the system's own.
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        panel.dismiss = { [weak self] in self?.close() }
        updateGlyph()
    }

    /// Open from the click until close() starts the fade-out.
    private(set) var isOpen = false
    var statusButton: NSStatusBarButton? { statusItem.button }

    @objc func toggle() {
        if isOpen { close() } else { open() }
    }

    func open() {
        guard !isOpen, let button = statusItem.button else { return }
        isOpen = true
        panel.present(below: anchor(for: button))
        // Clicks in other apps, another app activating or a Space change close the popup;
        // clicks in our own popovers and the status item do not.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                // macOS 27 delivers status-item clicks through the system menu bar: a click on
                // our own item reaches this monitor too, and toggle() already handles it.
                guard let self, !Self.statusItemCopies().contains(where: { $0.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation) }) else { return }
                self.close()
            }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] event in
            let windowNumber = event.windowNumber, location = event.locationInWindow
            let outside = MainActor.assumeIsolated {
                guard let self, windowNumber == self.panel.windowNumber, !self.panel.isOnGlass(location) else { return false }
                self.close()
                return true
            }
            return outside ? nil : event
        }) { monitors.append(local) }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.close() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
        updateGlyph()
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        guard isOpen else { return }
        isOpen = false
        panel.dismissAnimated()
        updateGlyph()
    }

    /// drop.circle at rest, drop.circle.fill and highlighted while open.
    private func updateGlyph() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: isOpen ? "drop.circle.fill" : "drop.circle", accessibilityDescription: "Daily Challenge")
        image?.isTemplate = true
        button.image = image
        button.highlight(isOpen)
    }

    /// The status item's frame on screen. With a menu bar on every display the item is
    /// drawn once per display; open under the copy that was clicked.
    private func anchor(for button: NSStatusBarButton) -> CGRect {
        let mouse = NSEvent.mouseLocation
        if let clicked = Self.statusItemCopies().first(where: { $0.frame.insetBy(dx: -2, dy: -2).contains(mouse) }) { return clicked.frame }
        return button.window?.frame ?? CGRect(x: mouse.x, y: mouse.y, width: 0, height: 0)
    }

    /// The windows drawing our status item (the app has no other status items).
    private static func statusItemCopies() -> [NSWindow] {
        NSApp.windows.filter { NSStringFromClass(type(of: $0)) == "NSStatusBarWindow" && $0.isVisible }
    }
}

/// The popup window: transparent outside the glass, no window shadow (the sheet and the
/// footer draw the board's shadows, which follow the animated glass). The window starts at
/// the menu bar, the sheet 8 pt below it, so the shadow above the sheet is not cut off at
/// the window's edge. Its height follows AnimatedPopupStack through PopupWindowAdapter.
final class PopupPanel: NSPanel {
    /// Transparent room around the 420 pt sheet for its shadow (sides and bottom).
    static let margin = Theme.Size.shadowMargin
    /// Transparent room above the sheet: the gap under the menu bar.
    static let topMargin = Theme.Size.menuBarGap
    static let width = Theme.Size.panelWidth + 2 * margin

    var dismiss: (() -> Void)?
    /// The popup's content height (sheet + gap + footer), or nil before the first layout.
    private(set) var contentHeight: CGFloat?
    /// The status item's frame, once presented.
    private var anchor: CGRect?

    init(content: some View) {
        super.init(contentRect: CGRect(x: 0, y: 0, width: Self.width, height: 400),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: content
            .padding(EdgeInsets(top: Self.topMargin, leading: Self.margin, bottom: Self.margin, trailing: Self.margin)))
        // The panel sets its own frame; the hosting view never constrains it.
        host.sizingOptions = []
        contentView = host
        // Lay out once so the first open already knows its height.
        host.layoutSubtreeIfNeeded()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { dismiss?() }

    func present(below anchor: CGRect) {
        self.anchor = anchor
        alphaValue = 1
        contentView?.layoutSubtreeIfNeeded()
        if let contentHeight { setFrame(frame(for: contentHeight), display: false) }
        orderFrontRegardless()
        makeKey()
    }

    func dismissAnimated() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.alphaValue < 0.01 else { return }
                self.orderOut(nil)
                self.alphaValue = 1
            }
        })
    }

    /// Fits the window to the popup's content, keeping the top edge where it is.
    func fit(contentHeight height: CGFloat) {
        guard height > 0 else { return }
        contentHeight = height
        let target = frame(for: height)
        guard abs(target.height - frame.height) > 0.5 || abs(target.minX - frame.minX) > 0.5 || abs(target.maxY - frame.maxY) > 0.5 else { return }
        setFrame(target, display: isVisible)
    }

    /// Under the status item: the sheet's left edge at the item's, kept 8 pt inside the
    /// screen; the window's top at the menu bar, the sheet's Theme.Size.menuBarGap below.
    func frame(for contentHeight: CGFloat) -> CGRect {
        let height = contentHeight + Self.topMargin + Self.margin
        guard let anchor else { return CGRect(x: frame.minX, y: frame.maxY - height, width: Self.width, height: height) }
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        return Self.frame(contentHeight: contentHeight, anchor: anchor, visibleFrame: screen?.visibleFrame ?? anchor)
    }

    static func frame(contentHeight: CGFloat, anchor: CGRect, visibleFrame: CGRect) -> CGRect {
        let inset: CGFloat = 8
        let sheetX = min(max(anchor.minX, visibleFrame.minX + inset), visibleFrame.maxX - inset - Theme.Size.panelWidth)
        let top = min(anchor.minY, visibleFrame.maxY)
        let height = contentHeight + topMargin + margin
        return CGRect(x: sheetX - margin, y: top - height, width: width, height: height)
    }

    /// Whether a point (window coordinates) is on the sheet, in the gap or on the footer,
    /// rather than in the transparent shadow margin around them.
    func isOnGlass(_ point: CGPoint) -> Bool {
        let content = contentHeight ?? (frame.height - Self.topMargin - Self.margin)
        let glass = CGRect(x: Self.margin, y: frame.height - Self.topMargin - content, width: Theme.Size.panelWidth, height: content)
        return glass.contains(point)
    }
}

extension PopupPanel {
    /// The sheet's and the footer's own blur views, top first, in window coordinates.
    var glassFrames: [CGRect] {
        var frames: [CGRect] = []
        func walk(_ view: NSView) {
            if view is GlassEffectView { frames.append(view.convert(view.bounds, to: nil)) }
            view.subviews.forEach(walk)
        }
        if let root = contentView { walk(root) }
        return frames.sorted { $0.maxY > $1.maxY }
    }

    /// Any system material in the window other than our glass (MenuBarExtra's backdrop was one).
    var foreignMaterials: [String] {
        var found: [String] = []
        func walk(_ view: NSView) {
            if view is GlassEffectView { return }
            if view is NSVisualEffectView { found.append(NSStringFromClass(type(of: view))) }
            for sublayer in view.layer?.sublayers ?? [] where NSStringFromClass(type(of: sublayer)).contains("Backdrop") {
                found.append(NSStringFromClass(type(of: sublayer)))
            }
            view.subviews.forEach(walk)
        }
        if let root = contentView { walk(root) }
        return found
    }
}

/// Reports the popup's content height to the PopupPanel hosting it, after SwiftUI's own
/// update pass. Test hosts and fixture renders keep their own size.
struct PopupWindowAdapter: NSViewRepresentable {
    /// The popup's full content height (sheet + gap + footer), or nil before layout.
    let height: CGFloat?

    func makeNSView(context: Context) -> AdapterView { AdapterView() }

    func updateNSView(_ view: AdapterView, context: Context) {
        view.desiredHeight = height
        view.scheduleFit()
    }

    final class AdapterView: NSView {
        var desiredHeight: CGFloat?
        private var pendingFit = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleFit()
        }

        /// Never resize during SwiftUI's own update pass.
        func scheduleFit() {
            guard !pendingFit else { return }
            pendingFit = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                pendingFit = false
                guard let panel = window as? PopupPanel, let height = desiredHeight else { return }
                panel.fit(contentHeight: height)
            }
        }
    }
}

/// Animates the glass sheet's height whenever its content changes size and keeps the
/// popup window at least as tall as the animating glass, so nothing is cut: growing
/// enlarges the (transparent) window first, shrinking releases it after the animation.
/// The sheet and the footer cast the board's shadows, which move with the glass.
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
                .background {
                    OuterShadow(cornerRadius: Theme.Size.sheetRadius, color: Theme.sheetShadow,
                                blur: Theme.Size.sheetShadowBlur, y: Theme.Size.sheetShadowY)
                }
            footer()
                .frame(height: Theme.Size.footerHeight)
                .background {
                    OuterShadow(cornerRadius: Theme.Size.footerHeight / 2, style: .circular, color: Theme.footerShadow,
                                blur: Theme.Size.footerShadowBlur, y: Theme.Size.footerShadowY)
                }
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
