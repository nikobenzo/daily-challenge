import AppKit
import Combine
import Observation
import SwiftUI

/// Device-local presentation only; never stored in a challenge or auth record.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    func appearanceName(increasedContrast: Bool = false) -> NSAppearance.Name? {
        switch self {
        case .system: nil
        case .light: increasedContrast ? .accessibilityHighContrastAqua : .aqua
        case .dark: increasedContrast ? .accessibilityHighContrastDarkAqua : .darkAqua
        }
    }

    func appearance(increasedContrast: Bool = false) -> NSAppearance? {
        appearanceName(increasedContrast: increasedContrast).flatMap { NSAppearance(named: $0) }
    }
}

@MainActor @Observable
final class AppAppearance {
    static let storageKey = "appearancePreference"
    private let defaults: UserDefaults
    private var accessibilityChanges: AnyCancellable?
    var preference: AppearancePreference {
        didSet {
            defaults.set(preference.rawValue, forKey: Self.storageKey)
            apply()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preference = AppearancePreference(rawValue: defaults.string(forKey: Self.storageKey) ?? "") ?? .system
        apply()
        accessibilityChanges = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.apply() }
            }
    }

    private func apply() {
        // AppKit owns native controls, menu-bar windows and popovers. A nil
        // override restores live macOS inheritance, rather than sampling it once.
        NSApplication.shared.appearance = preference.appearance(
            increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        )
    }
}

/// The production popup root. The glass sheet and the detached footer are drawn by
/// TrackerView; the popup panel around them stays transparent (PopupPanel), so a window
/// still resizing around the animated glass never shows an unfilled band.
struct TrackerPopup: View {
    let model: TrackerModel
    let auth: ProofModel
    let appearance: AppAppearance
    var section: TrackerSection = .today

    var body: some View {
        TrackerView(model: model, auth: auth, section: section)
            .environment(appearance)
            // minHeight 0: a window not yet grown to the content still shows it from the top.
            // The width keeps the sheet's 420 pt minimum, so no host can squeeze or clip it.
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
    }
}

extension View {
    /// An opaque themed surface for popovers and standalone renders, where no glass sheet exists.
    func trackerSurface() -> some View {
        background(Theme.solidGlass.ignoresSafeArea())
    }
}

/// Appearance row: A (System) / sun (Light) / moon (Dark), icon-only with tooltips.
struct AppearanceSettings: View {
    @Environment(AppAppearance.self) private var appearance

    var body: some View {
        @Bindable var appearance = appearance
        SettingRow(symbol: "circle.lefthalf.filled", title: "Appearance") {
            IconSegmented(selection: $appearance.preference, options: [
                .init(value: .system, text: "A", label: "System: follows macOS"),
                .init(value: .light, symbol: "sun.max", label: "Light"),
                .init(value: .dark, symbol: "moon", label: "Dark")
            ], cell: Theme.Size.appearanceCell, track: Theme.Size.appearanceTrack)
        }
        .help("System follows macOS. This choice is saved only on this Mac.")
    }
}
