import AppKit
import SwiftUI

/// The Daily Challenge design system (Paper file "Daily Challenge · Design System").
/// Every colour is one dynamic token that resolves against the drawing appearance,
/// so the device-local Appearance setting (System / Light / Dark), popovers and
/// in-process renders all pick the matching palette without extra plumbing.
enum Theme {
    // MARK: Glass

    static let glass = color(dark: rgba(34, 38, 98, 0.62), light: rgba(255, 255, 255, 0.66))
    /// The same tint without transparency: Reduce Transparency and standalone surfaces.
    static let solidGlass = color(dark: rgba(34, 38, 98), light: rgba(246, 248, 253))
    static let glassBorder = color(dark: rgba(255, 255, 255, 0.16), light: rgba(255, 255, 255, 0.9))
    static let glassHighlight = color(dark: rgba(255, 255, 255, 0.18), light: rgba(255, 255, 255, 0.9))
    static let sheetShadow = color(dark: rgba(8, 10, 40, 0.45), light: rgba(30, 40, 90, 0.22))
    static let footerShadow = color(dark: rgba(8, 10, 40, 0.40), light: rgba(30, 40, 90, 0.18))
    static let hairline = color(dark: rgba(255, 255, 255, 0.10), light: rgba(15, 23, 42, 0.08))

    // MARK: Controls

    static let controlFill = color(dark: rgba(255, 255, 255, 0.12), light: rgba(15, 23, 42, 0.07))
    static let fieldFill = color(dark: rgba(255, 255, 255, 0.10), light: rgba(255, 255, 255, 0.8))
    static let primaryTop = color(dark: hex(0x4A80FF), light: hex(0x3B72FF))
    static let primaryBottom = color(dark: hex(0x2A5BE8), light: hex(0x1F56E0))
    static let primaryShadow = color(dark: rgba(42, 91, 232, 0.45), light: rgba(31, 86, 224, 0.35))
    static let toggleOn = color(dark: hex(0x2F6BFF), light: hex(0x1F56E0))
    static let toggleOnKnob = color(dark: hex(0xE6EEFF), light: hex(0xFFFFFF))
    static let toggleOff = color(dark: rgba(255, 255, 255, 0.18), light: rgba(15, 23, 42, 0.14))
    static let toggleOffKnob = color(dark: hex(0xE6E8F2), light: hex(0xFFFFFF))
    /// The selected cell of a segmented track (boards: lifted white cell in Light).
    static let segmentSelected = color(dark: rgba(255, 255, 255, 0.18), light: hex(0xFFFFFF))
    /// The same cell as a light tint on the Liquid Glass indicator, so the sheet shows through.
    static let segmentGlassTint = color(dark: rgba(255, 255, 255, 0.18), light: rgba(255, 255, 255, 0.4))
    static let focus = color(dark: hex(0x6FA0FF), light: hex(0x1F56E0))
    static let focusHalo = color(dark: rgba(111, 160, 255, 0.25), light: rgba(31, 86, 224, 0.18))

    // MARK: Meaning

    static let water = color(dark: hex(0x5EA8FF), light: hex(0x2E66F0))
    static let jugTop = color(dark: hex(0x8CC4FF), light: hex(0x6FB0FF))
    static let jugBottom = color(dark: hex(0x2E66F0), light: hex(0x1F56E0))
    static let accentText = color(dark: hex(0x8CC4FF), light: hex(0x1F56E0))
    static let accentTint = color(dark: rgba(140, 196, 255, 0.16), light: rgba(31, 86, 224, 0.10))
    static let done = color(dark: hex(0x4DF0A3), light: hex(0x22C06A))
    static let doneText = color(dark: hex(0x8DFFC6), light: hex(0x15803D))
    static let doneTint = color(dark: rgba(77, 240, 163, 0.18), light: rgba(34, 192, 106, 0.14))
    /// Numerals on a filled green day disc: dark numerals in Dark, white in Light.
    static let onDone = color(dark: hex(0x0B2A1C), light: hex(0xFFFFFF))
    static let amber = color(dark: hex(0xFF9F3D), light: hex(0xF28C28))
    static let amberText = color(dark: hex(0xFFC27A), light: hex(0xB45309))
    static let amberTint = color(dark: rgba(255, 178, 74, 0.22), light: rgba(242, 140, 40, 0.16))
    static let danger = color(dark: hex(0xFF8A8A), light: hex(0xC62828))
    static let dangerRing = color(dark: hex(0xFF7A7A), light: hex(0xC62828))
    static let dangerTint = color(dark: rgba(255, 138, 138, 0.16), light: rgba(198, 40, 40, 0.10))

    // MARK: Text

    static let textPrimary = color(dark: hex(0xFFFFFF), light: hex(0x0F172A))
    static let textSecondary = color(dark: hex(0xC9CFF5), light: hex(0x5B6478))
    static let textTertiary = color(dark: hex(0xA9B1DC), light: hex(0x8A94A8))
    /// Text on the selected calendar disc, which is the text-primary colour.
    static let textInverse = color(dark: hex(0x0F172A), light: hex(0xFFFFFF))
    static let futureDay = color(dark: rgba(255, 255, 255, 0.35), light: hex(0xB7BFCF))
    static let ringTrack = color(dark: rgba(255, 255, 255, 0.14), light: rgba(15, 23, 42, 0.10))
    static let appMarkTop = color(dark: hex(0x3D74FF), light: hex(0x2E66F0))
    static let appMarkBottom = color(dark: hex(0x1A3FA8), light: hex(0x0B2A8A))

    // Board-derived pairings (not separate tokens in the report's table).
    static let dayBadgeFill = color(dark: rgba(255, 255, 255, 0.12), light: rgba(31, 86, 224, 0.10))
    static let dayBadgeText = color(dark: hex(0xFFFFFF), light: hex(0x1F56E0))
    static let bestBadgeFill = color(dark: rgba(255, 255, 255, 0.12), light: rgba(242, 140, 40, 0.16))
    static let bestBadgeText = color(dark: hex(0xFFFFFF), light: hex(0xB45309))
    static let jugOutline = color(dark: hex(0xC9CFF5), light: hex(0x8A94A8))
    static let jugGlass = color(dark: rgba(255, 255, 255, 0.10), light: rgba(255, 255, 255, 0.6))

    static var primaryGradient: LinearGradient {
        LinearGradient(colors: [primaryTop, primaryBottom], startPoint: .top, endPoint: .bottom)
    }
    static var appMarkGradient: LinearGradient {
        LinearGradient(colors: [appMarkTop, appMarkBottom], startPoint: .top, endPoint: .bottom)
    }
    static var jugGradient: LinearGradient {
        LinearGradient(colors: [jugTop, jugBottom], startPoint: .top, endPoint: .bottom)
    }

    // MARK: Type scale (SF Pro; rounded design for counts)

    enum Fonts {
        static let hero = Font.system(size: 32, weight: .heavy, design: .rounded)
        static let screenTitle = Font.system(size: 24, weight: .heavy)
        static let streak = Font.system(size: 22, weight: .heavy, design: .rounded)
        static let appName = Font.system(size: 16, weight: .bold)
        static let rowLabel = Font.system(size: 16, weight: .semibold)
        static let pill = Font.system(size: 15, weight: .bold)
        static let field = Font.system(size: 14, weight: .medium)
        static let link = Font.system(size: 13, weight: .bold)
        static let caption = Font.system(size: 12, weight: .semibold)
        static let badge = Font.system(size: 12, weight: .bold)
        static let ringLabel = Font.system(size: 10, weight: .bold)
        static let eyebrow = Font.system(size: 10, weight: .bold)
    }

    /// Tracking in points for the sizes above (em × size).
    enum Tracking {
        static let hero: CGFloat = -0.96
        static let screenTitle: CGFloat = -0.48
        static let appName: CGFloat = -0.16
        static let ringLabel: CGFloat = 0.6
        static let eyebrow: CGFloat = 0.8
    }

    // MARK: Spacing, radii and sizes

    enum Space {
        static let xxs: CGFloat = 4, xs: CGFloat = 8, s: CGFloat = 12, m: CGFloat = 16
        static let l: CGFloat = 20, xl: CGFloat = 24, xxl: CGFloat = 30
    }

    enum Size {
        static let panelWidth: CGFloat = 420
        static let sheetRadius: CGFloat = 28
        static let footerHeight: CGFloat = 56
        static let footerGap: CGFloat = 12
        /// Board shadows (CSS 0 24 60 and 0 18 40): blur and downward offset.
        static let sheetShadowBlur: CGFloat = 60
        static let sheetShadowY: CGFloat = 24
        static let footerShadowBlur: CGFloat = 40
        static let footerShadowY: CGFloat = 18
        /// Transparent room around the sheet in the popup window for its shadow.
        static let shadowMargin: CGFloat = 60
        /// The sheet's top edge under the menu bar (Menu bar presence board).
        static let menuBarGap: CGFloat = 8
        static let headerHeight: CGFloat = 60
        static let sectionHorizontal: CGFloat = 20
        static let sectionVertical: CGFloat = 16
        static let pill: CGFloat = 42
        static let largePill: CGFloat = 48
        static let field: CGFloat = 46
        static let segmentTrack: CGFloat = 36
        static let segmentCell = CGSize(width: 44, height: 30)
        static let appearanceTrack: CGFloat = 34
        static let appearanceCell = CGSize(width: 40, height: 28)
        static let toggle = CGSize(width: 52, height: 30)
        static let toggleKnob: CGFloat = 26
        static let badge: CGFloat = 24
        static let iconChip: CGFloat = 32
        static let ring: CGFloat = 64
        static let ringStroke: CGFloat = 6
        static let jug = CGSize(width: 88, height: 112)
        static let calendarDay: CGFloat = 30
        /// History and Account share one content height (report §5), so switching
        /// between them never resizes; Today is shorter.
        static let wideSectionHeight: CGFloat = 600
    }

    enum Motion {
        static let sectionResize = Animation.easeInOut(duration: 0.28)
        static let reducedResize = Animation.linear(duration: 0.12)
        static let crossFade = Animation.easeInOut(duration: 0.2)
        /// The segmented indicator sliding to a new cell, in step with the section resize.
        static let selection = Animation.easeInOut(duration: 0.28)
        static let ring = Animation.easeInOut(duration: 0.35)
        static let band = Animation.easeOut(duration: 0.4)
        /// How long a shrinking window keeps its old height so the glass can animate.
        static let resizeHold: Duration = .milliseconds(320)
    }

    // MARK: Helpers

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
            .map { $0 == .darkAqua || $0 == .accessibilityHighContrastDarkAqua } ?? false
    }

    static func color(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { isDark($0) ? dark : light })
    }

    static func rgba(_ red: Int, _ green: Int, _ blue: Int, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: alpha)
    }

    static func hex(_ value: Int) -> NSColor {
        rgba((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    }
}
