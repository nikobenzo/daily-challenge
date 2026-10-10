import SwiftUI

// Design-system components that draw the same on macOS and iOS. Everything in this
// Shared folder compiles into both the Mac target and the iPhone app (iOS/project.yml),
// so it must not use AppKit or UIKit; platform-specific components stay in Components.swift.

struct HairlineDivider: View {
    var body: some View {
        Theme.hairline.frame(height: 1).accessibilityHidden(true)
    }
}

// MARK: Buttons

/// Primary CTA: blue gradient pill with a coloured shadow. Disabled fades it.
struct PrimaryPillStyle: ButtonStyle {
    var height: CGFloat = Theme.Size.pill
    var font: Font = Theme.Fonts.pill
    var expands = true
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(height: height)
            .background(Capsule(style: .circular).fill(Theme.primaryGradient))
            .overlay(Capsule(style: .circular).strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: isEnabled ? Theme.primaryShadow : .clear, radius: 8, y: 6)
            .focusHalo(isFocused, shape: Capsule(style: .circular))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .contentShape(Capsule(style: .circular))
    }
}

/// Translucent tinted pill on the glass (Sync now, Export, Check again…).
struct TintedPillStyle: ButtonStyle {
    var height: CGFloat = Theme.Size.pill
    var fill: Color = Theme.controlFill
    var foreground: Color = Theme.textPrimary
    var expands = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.pill)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .fixedSize(horizontal: !expands, vertical: false)
            .padding(.horizontal, 14)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(height: height)
            .background(Capsule(style: .circular).fill(fill))
            .focusHalo(isFocused, shape: Capsule(style: .circular))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .contentShape(Capsule(style: .circular))
    }
}

/// Round icon-only control (−, ⋯, refresh, wrench). Callers add help + accessibilityLabel.
struct RoundIconStyle: ButtonStyle {
    var size: CGFloat = Theme.Size.pill
    var fill: Color = Theme.controlFill
    var foreground: Color = Theme.textPrimary
    var border: Color = .clear
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
            .overlay(Circle().strokeBorder(border, lineWidth: 1.5))
            .focusHalo(isFocused, shape: Circle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Circle())
    }
}

/// Text link in the accent colour (Create account, Back to sign in…).
struct LinkStyle: ButtonStyle {
    var color: Color = Theme.accentText
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.link)
            .foregroundStyle(color)
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .contentShape(Rectangle())
    }
}

extension View {
    /// The design's focus state: 1.5 pt focus ring plus a 3 pt halo, replacing the
    /// system focus ring that custom shapes would otherwise get as a stray rectangle.
    func focusHalo<S: InsettableShape>(_ focused: Bool, shape: S) -> some View {
        overlay {
            if focused {
                shape.strokeBorder(Theme.focus, lineWidth: 1.5)
                    .background(shape.stroke(Theme.focusHalo, lineWidth: 6))
            }
        }
        .focusEffectDisabled()
    }
}

// MARK: Badges and marks

/// A small tinted capsule: Day 12, Today, streak best, update chip.
struct Badge: View {
    var symbol: String?
    var text: String?
    var fill: Color = Theme.controlFill
    var foreground: Color = Theme.textPrimary
    var border: Color = .clear
    var height: CGFloat = Theme.Size.badge
    var symbolColor: Color?

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(symbolColor ?? foreground)
            }
            if let text { Text(text).font(Theme.Fonts.badge).monospacedDigit() }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, text == nil ? 0 : 10)
        .frame(minWidth: height, minHeight: height)
        .background(Capsule(style: .circular).fill(fill))
        .overlay(Capsule(style: .circular).strokeBorder(border, lineWidth: 1))
        .fixedSize()
    }
}

/// The blue gradient tile with a white drop.
struct AppMark: View {
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(Theme.appMarkGradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "drop.fill").font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(.white)
            }
            .shadow(color: Theme.primaryShadow.opacity(0.6), radius: 4, y: 2)
            .accessibilityHidden(true)
    }
}

/// The round gradient hero on auth screens.
struct HeroIcon: View {
    let symbol: String
    var dot = false

    var body: some View {
        Circle().fill(Theme.primaryGradient)
            .frame(width: 60, height: 60)
            .overlay { Image(systemName: symbol).font(.system(size: 24, weight: .semibold)).foregroundStyle(.white) }
            .overlay(alignment: .topTrailing) {
                if dot {
                    Circle().fill(Theme.done).frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(Theme.glass, lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }
            .shadow(color: Theme.primaryShadow, radius: 12, y: 6)
            .accessibilityHidden(true)
    }
}

/// A settings row: fixed icon column, label, trailing control.
struct SettingRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var tint: Color = Theme.textPrimary
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                .frame(width: 24).foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title).font(Theme.Fonts.rowLabel).foregroundStyle(tint)
                .lineLimit(1).fixedSize()
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: 44)
    }
}

/// Small caps label with tracking: ring labels and section eyebrows.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.textSecondary
    var font: Font = Theme.Fonts.eyebrow
    var tracking: CGFloat = Theme.Tracking.eyebrow

    var body: some View {
        Text(text.uppercased()).font(font).tracking(tracking).foregroundStyle(color)
    }
}

// MARK: Fields

/// Error text below a field, in the danger colour with the field's exclamation icon.
struct FieldError: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.danger)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityLabel("Error: \(text)")
    }
}

// MARK: Ring gauge

/// 64 pt ring, stroke 6. Every state has a glyph, not only a colour: pending shows
/// a dash, progress a percentage, done a check, missed a dashed red ring with ×.
struct RingGauge: View {
    enum State: Equatable { case pending, progress(Double), done, missed }

    let symbol: String
    let label: String
    let state: State
    var showsPercent = false
    /// Widgets pass a text-style font: `Theme.Fonts` scales with the process's text size,
    /// which a widget's Dynamic Type limit cannot cap.
    var labelFont: Font = Theme.Fonts.ringLabel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SwiftUI.State private var pop = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Theme.ringTrack, lineWidth: Theme.Size.ringStroke)
                    .opacity(state == .missed ? 0 : 1)
                switch state {
                case .missed:
                    Circle().stroke(Theme.dangerRing, style: StrokeStyle(lineWidth: Theme.Size.ringStroke, lineCap: .round, dash: [3, 6]))
                case .done:
                    Circle().stroke(Theme.done, lineWidth: Theme.Size.ringStroke)
                case .progress(let value):
                    Circle().trim(from: 0, to: max(0.001, min(1, value)))
                        .stroke(Theme.water, style: StrokeStyle(lineWidth: Theme.Size.ringStroke, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                case .pending:
                    EmptyView()
                }
                VStack(spacing: 3) {
                    Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(iconColor)
                    glyph
                }
            }
            .padding(Theme.Size.ringStroke / 2)
            .frame(width: Theme.Size.ring, height: Theme.Size.ring)
            .scaleEffect(pop ? 1.06 : 1)
            .animation(reduceMotion ? nil : Theme.Motion.ring, value: state)
            Eyebrow(text: label, color: labelColor, font: labelFont, tracking: Theme.Tracking.ringLabel)
                .lineLimit(1).fixedSize()
        }
        .onChange(of: state) { old, new in
            guard new == .done, old != .done, !reduceMotion else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { pop = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pop = false }
            }
        }
    }

    @ViewBuilder private var glyph: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.done)
        case .missed:
            Image(systemName: "xmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.dangerRing)
        case .progress(let value) where showsPercent:
            Text("\(Int((min(1, value) * 100).rounded()))%").font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
        case .pending where showsPercent:
            Text("0%").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Theme.textTertiary)
        default:
            Capsule(style: .circular).fill(Theme.textTertiary.opacity(0.7)).frame(width: 12, height: 4)
        }
    }

    private var iconColor: Color {
        switch state {
        case .pending: Theme.textTertiary
        case .missed: Theme.dangerRing
        case .done, .progress: Theme.textPrimary
        }
    }

    private var labelColor: Color {
        switch state {
        case .pending: Theme.textTertiary
        case .missed: Theme.danger
        case .done, .progress: Theme.textSecondary
        }
    }
}
