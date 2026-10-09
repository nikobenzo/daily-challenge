import AppKit
import SwiftUI

// MARK: Glass

/// NSVisualEffectView (.hudWindow in Dark, .popover in Light) under the glass tint.
/// Reduce Transparency drops the blur and uses the tint at full opacity; Increase
/// Contrast strengthens the border.
struct GlassBackground: View {
    var cornerRadius: CGFloat = Theme.Size.sheetRadius
    /// .circular when the radius is half the height (the footer capsule): macOS 27 draws
    /// continuous corners at that radius with flattened ends and stray stroke segments.
    var style: RoundedCornerStyle = .continuous
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: style)
        ZStack {
            if reduceTransparency {
                shape.fill(Theme.solidGlass)
            } else {
                VisualEffectBlur(material: scheme == .dark ? .hudWindow : .popover)
                    .clipShape(shape)
                shape.fill(Theme.glass)
            }
        }
        .overlay {
            // 1 pt inner top highlight, fading out before the sides.
            shape.inset(by: 0.5)
                .stroke(LinearGradient(colors: [Theme.glassHighlight, .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.08)),
                        lineWidth: 1)
        }
        .overlay {
            shape.strokeBorder(contrast == .increased ? Theme.textPrimary.opacity(0.7) : Theme.glassBorder, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> GlassEffectView {
        let view = GlassEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        return view
    }

    func updateNSView(_ view: GlassEffectView, context: Context) { view.material = material }
}

/// Our own blur; the popup window adapter leaves these alone and hides any other material.
final class GlassEffectView: NSVisualEffectView {}

extension View {
    /// The 420 pt glass sheet: rounded 28, hairline-separated sections inside.
    func glassSheet(cornerRadius: CGFloat = Theme.Size.sheetRadius, style: RoundedCornerStyle = .continuous) -> some View {
        background(GlassBackground(cornerRadius: cornerRadius, style: style))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: style))
    }
}

/// The boards' soft outer shadow (CSS `0 y blur`), drawn only outside the shape so it
/// never darkens the translucent glass. It is a pre-rendered image stretched along the
/// shape's straight sides rather than a Core Animation shadow: cacheDisplay (renders and
/// popup captures) draws CA shadow offsets upside down, an image looks the same everywhere,
/// and an animating height costs no blur per frame. Tinted with a dynamic colour token.
struct OuterShadow: View {
    let cornerRadius: CGFloat
    var style: RoundedCornerStyle = .continuous
    let color: Color
    let blur: CGFloat
    let y: CGFloat

    var body: some View {
        GeometryReader { proxy in
            // Enough straight side above and below the stretched row that the blur of the
            // corners never reaches it; a shorter shape (the footer) is drawn exactly.
            let core = min(proxy.size.height, 2 * (cornerRadius + blur + y))
            let image = Self.image(width: proxy.size.width, height: core, cornerRadius: cornerRadius,
                                   style: style, blur: blur, y: y)
            let top = (blur + core / 2).rounded(.down)
            let leading = ((image.size.width - 1) / 2).rounded(.down)
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable(capInsets: EdgeInsets(top: top, leading: leading, bottom: image.size.height - top - 1,
                                                 trailing: image.size.width - leading - 1), resizingMode: .stretch)
                .foregroundStyle(color)
                .frame(width: proxy.size.width + 2 * blur, height: proxy.size.height + 2 * blur + y)
                .offset(x: -blur, y: -blur)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct Key: Hashable {
        let width: CGFloat, height: CGFloat, cornerRadius: CGFloat, continuous: Bool, blur: CGFloat, y: CGFloat
    }
    @MainActor private static var cache: [Key: NSImage] = [:]

    /// The shadow of a black shape, with the shape itself cut out, at 2x.
    @MainActor static func image(width: CGFloat, height: CGFloat, cornerRadius: CGFloat, style: RoundedCornerStyle,
                                 blur: CGFloat, y: CGFloat) -> NSImage {
        let key = Key(width: width, height: height, cornerRadius: cornerRadius, continuous: style == .continuous, blur: blur, y: y)
        if let image = cache[key] { return image }
        let scale: CGFloat = 2
        let size = CGSize(width: width + 2 * blur, height: height + 2 * blur + y)
        guard size.width > 0, size.height > 0, let context = CGContext(
            data: nil, width: Int((size.width * scale).rounded(.up)), height: Int((size.height * scale).rounded(.up)),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return NSImage(size: .zero) }
        // Top-left origin in points; CG shadow geometry stays in pixels with y up.
        context.translateBy(x: 0, y: CGFloat(context.height))
        context.scaleBy(x: scale, y: -scale)
        let path = RoundedRectangle(cornerRadius: min(cornerRadius, height / 2), style: style)
            .path(in: CGRect(x: blur, y: blur, width: width, height: height)).cgPath
        let black = CGColor(gray: 0, alpha: 1)
        context.setShadow(offset: CGSize(width: 0, height: -y * scale), blur: blur * scale, color: black)
        context.setFillColor(black)
        context.addPath(path)
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setBlendMode(.clear)
        context.addPath(path)
        context.fillPath()
        let image = context.makeImage().map { NSImage(cgImage: $0, size: size) } ?? NSImage(size: .zero)
        cache[key] = image
        return image
    }
}

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

// MARK: Toggle, segmented and stepper

/// 52 × 30 track, 26 pt knob. Same accessibility as a native switch.
struct GlassToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 8)
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { configuration.isOn.toggle() }
            } label: {
                Capsule(style: .circular)
                    .fill(configuration.isOn ? Theme.toggleOn : Theme.toggleOff)
                    .frame(width: Theme.Size.toggle.width, height: Theme.Size.toggle.height)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(configuration.isOn ? Theme.toggleOnKnob : Theme.toggleOffKnob)
                            .frame(width: Theme.Size.toggleKnob, height: Theme.Size.toggleKnob)
                            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                            .padding(2)
                    }
                    .shadow(color: configuration.isOn ? Theme.primaryShadow.opacity(0.6) : .clear, radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .opacity(isEnabled ? 1 : 0.45)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

/// An icon-only segmented track: each cell is an SF Symbol (or short text) with a
/// tooltip and an accessibility label.
///
/// On macOS 26 and later the selected cell is Liquid Glass: one glass capsule in a
/// `GlassEffectContainer`, lightly tinted with `segmentGlassTint` over the translucent
/// track, that slides to the new cell. (Handing a `glassEffectID` from one cell to the next
/// jumps on macOS 27 instead of moving, measured on screen.) Reduce Transparency draws the
/// opaque `segmentSelected` pill, Reduce Motion cross-fades instead of sliding, and earlier
/// systems slide the opaque pill.
struct IconSegmented<Value: Hashable>: View {
    struct Option {
        let value: Value
        var symbol: String?
        var text: String?
        let label: String
    }

    /// How the selected cell is drawn.
    enum Indicator: Equatable {
        /// A Liquid Glass capsule (macOS 26 and later).
        case glass
        /// The same tint as a flat translucent capsule: in-process renders, which cannot draw glass.
        case flat
        /// The opaque `segmentSelected` pill: Reduce Transparency, and systems before macOS 26.
        case opaque

        static func resolve(liquidGlassAvailable: Bool, reduceTransparency: Bool, liquidGlassOverride: Bool?) -> Indicator {
            if reduceTransparency || !liquidGlassAvailable { return .opaque }
            return liquidGlassOverride == false ? .flat : .glass
        }
    }

    @Binding var selection: Value
    let options: [Option]
    var cell: CGSize = Theme.Size.segmentCell
    var track: CGFloat = Theme.Size.segmentTrack
    @Environment(\.trackerReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.trackerLiquidGlassOverride) private var liquidGlassOverride

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    private var indicator: Indicator {
        var available = false
        if #available(macOS 26, *) { available = true }
        return .resolve(liquidGlassAvailable: available, reduceTransparency: reduceTransparency, liquidGlassOverride: liquidGlassOverride)
    }

    var body: some View {
        cells
            .background { indicatorRow }
            .padding((track - cell.height) / 2)
            .background(Capsule(style: .circular).fill(Theme.controlFill))
            // The indicator and the icon colours move together, whoever changes the selection.
            .animation(reduceMotion ? Theme.Motion.crossFade : Theme.Motion.selection, value: selection)
    }

    private var cells: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button { selection = option.value } label: {
                    glyph(option)
                        .foregroundStyle(selected ? Theme.accentText : Theme.textSecondary)
                        .frame(width: cell.width, height: cell.height)
                        .contentShape(Capsule(style: .circular))
                }
                .buttonStyle(.plain)
                .help(option.label)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
    }

    @ViewBuilder private func glyph(_ option: Option) -> some View {
        if let symbol = option.symbol {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
        } else {
            Text(option.text ?? "").font(.system(size: 14, weight: .heavy))
        }
    }

    /// The one indicator, under the icons, offset to the selected cell. A glass container
    /// draws its glass above its own content, so the icons stay outside it. While the glass
    /// moves, macOS 27 still composites it over the glyph it passes for a few frames.
    @ViewBuilder private var indicatorRow: some View {
        let row = ZStack(alignment: .leading) {
            if let index = options.firstIndex(where: { $0.value == selection }) {
                selectedCell
                    .frame(width: cell.width, height: cell.height)
                    .offset(x: CGFloat(index) * (cell.width + 2))
                    // Reduce Motion: a new indicator fades in at the new cell instead of sliding.
                    .id(reduceMotion ? index : -1)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityHidden(true)
        if #available(macOS 26, *), indicator == .glass {
            GlassEffectContainer(spacing: 2) { row }
        } else {
            row
        }
    }

    @ViewBuilder private var selectedCell: some View {
        let shape = Capsule(style: .circular)
        switch indicator {
        case .glass:
            if #available(macOS 26, *) {
                // Not .interactive(): the buttons above take the clicks, and interactive glass
                // lifts over the icons while it moves (measured on screen, macOS 27).
                Color.clear.glassEffect(.regular.tint(Theme.segmentGlassTint), in: shape)
            }
        case .flat:
            shape.fill(Theme.segmentGlassTint).overlay(shape.strokeBorder(Theme.glassBorder, lineWidth: 0.5))
        case .opaque:
            shape.fill(Theme.segmentSelected).shadow(color: Theme.sheetShadow.opacity(0.5), radius: 2, y: 1)
        }
    }
}

/// "−  90 min  +" pill stepper.
struct PillStepper: View {
    let text: String
    let accessibilityText: String
    let decrement: (() -> Void)?
    let increment: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            step("minus", action: decrement, label: "Decrease")
            Text(text).font(Theme.Fonts.pill).monospacedDigit().foregroundStyle(Theme.textPrimary)
                .frame(minWidth: 52)
            step("plus", action: increment, label: "Increase")
        }
        .padding(.horizontal, 4)
        .frame(height: Theme.Size.segmentTrack)
        .background(Capsule(style: .circular).fill(Theme.controlFill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(text)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: increment?()
            case .decrement: decrement?()
            @unknown default: break
            }
        }
    }

    private func step(_ symbol: String, action: (() -> Void)?, label: String) -> some View {
        Button { action?() } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                .frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textPrimary)
        .disabled(action == nil)
        .opacity(action == nil ? 0.35 : 1)
        .help(label)
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

/// 46 pt capsule field with a leading icon, focus ring + halo, error and valid states,
/// and an eye button that reveals a password.
struct GlassField<Focus: Hashable>: View {
    let symbol: String
    let placeholder: String
    @Binding var text: String
    var secure = false
    var invalid = false
    var valid = false
    var monospaced = false
    var contentType: NSTextContentType?
    let focus: FocusState<Focus?>.Binding
    let equals: Focus
    var onSubmit: () -> Void = {}
    @State private var reveal = false

    var body: some View {
        let focused = focus.wrappedValue == equals
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                .foregroundStyle(invalid ? Theme.danger : focused ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Group {
                if secure && !reveal {
                    SecureField(placeholder, text: $text, prompt: prompt)
                } else {
                    TextField(placeholder, text: $text, prompt: prompt)
                }
            }
            .textFieldStyle(.plain)
            .font(monospaced ? .system(size: 18, weight: .bold, design: .rounded).monospacedDigit() : Theme.Fonts.field)
            .tracking(monospaced ? 2 : 0)
            .foregroundStyle(Theme.textPrimary)
            .textContentType(contentType)
            .focused(focus, equals: equals)
            .onSubmit(onSubmit)
            if invalid {
                Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.danger).accessibilityHidden(true)
            } else if valid {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.done)
                    .accessibilityHidden(true)
            } else if secure {
                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye").foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help(reveal ? "Hide password" : "Show password")
                .accessibilityLabel(reveal ? "Hide password" : "Show password")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Theme.Size.field)
        .background(Capsule(style: .circular).fill(invalid ? Theme.dangerTint : Theme.fieldFill))
        .background {
            if focused { Capsule(style: .circular).stroke(invalid ? Theme.dangerTint : Theme.focusHalo, lineWidth: 6) }
        }
        .overlay {
            Capsule(style: .circular).strokeBorder(invalid ? Theme.dangerRing : focused ? Theme.focus : Theme.controlFill,
                                   lineWidth: invalid || focused ? 1.5 : 1)
        }
        .contentShape(Capsule(style: .circular))
    }

    private var prompt: Text { Text(placeholder).foregroundStyle(Theme.textTertiary) }
}

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
            Eyebrow(text: label, color: labelColor, font: Theme.Fonts.ringLabel, tracking: Theme.Tracking.ringLabel)
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
