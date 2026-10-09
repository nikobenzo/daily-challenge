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
