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

/// The production popup root. Keep the backing surface here, not in previews:
/// MenuBarExtra's window material otherwise blends the desktop behind the UI.
struct TrackerPopup: View {
    let model: TrackerModel
    let auth: ProofModel
    let appearance: AppAppearance
    var section: TrackerSection = .today

    var body: some View {
        TrackerView(model: model, auth: auth, section: section)
            .environment(appearance)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .trackerSurface()
    }
}

extension View {
    func trackerSurface() -> some View {
        background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    }

    func trackerCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(TrackerCard(cornerRadius: cornerRadius))
    }
}

private struct TrackerCard: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        content.background {
            if reduceTransparency || contrast == .increased {
                shape.fill(Color(nsColor: .controlBackgroundColor))
            } else {
                shape.fill(.regularMaterial)
            }
        }
        .overlay(shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 1 : 0), lineWidth: 1))
    }
}

struct AppearanceSettings: View {
    @Environment(AppAppearance.self) private var appearance

    var body: some View {
        @Bindable var appearance = appearance
        Picker("Appearance", selection: $appearance.preference) {
            ForEach(AppearancePreference.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .help("System follows macOS. This choice is saved only on this Mac.")
    }
}
