import SwiftUI

private struct PopupVisibleKey: EnvironmentKey { static let defaultValue = false }
private struct MotionOverrideKey: EnvironmentKey { static let defaultValue: Bool? = nil }
private struct LiquidGlassOverrideKey: EnvironmentKey { static let defaultValue: Bool? = nil }
extension EnvironmentValues {
    /// Fixture-only: false draws Liquid Glass controls as their flat translucent fallback.
    /// In-process renders (cacheDisplay) cannot draw Liquid Glass and drop everything the
    /// glass samples behind it. nil uses Liquid Glass wherever the system has it.
    var trackerLiquidGlassOverride: Bool? {
        get { self[LiquidGlassOverrideKey.self] }
        set { self[LiquidGlassOverrideKey.self] = newValue }
    }
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
