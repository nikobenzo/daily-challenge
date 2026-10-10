import ChallengeCore
import SwiftUI
import WidgetKit

// The widgets draw the app's design system: the Today jug (`JugDrawing`), the ring
// gauges (`RingGauge`) and the extras checkboxes, in `Theme` tokens. The container is
// the opaque `solidGlass` tint, so Reduce Transparency needs no separate fill. Every state
// has a glyph as well as a colour (check, dash, ×). Tinted and clear Home Screens render
// in WidgetKit's accented mode, where only opacity survives: filled controls switch to a
// translucent fill under full-opacity text, and the data marks are accentable.

extension EnvironmentValues {
    /// In-process renders cannot set WidgetKit's rendering mode; they set this instead.
    @Entry var widgetAccentedOverride: Bool? = nil
}

/// Text styles scale with the widget's Dynamic Type size (unlike `Theme.Fonts`, which
/// read the process's text size); sizes match the app's at the default size.
enum WidgetFont {
    // `.weight(_:)` rather than `system(_:design:weight:)`: SpringBoard drew the latter's
    // weights as regular on placed widgets (iOS 27 simulator), unlike in-process renders.
    static let total = Font.system(.title, design: .rounded).weight(.heavy)
    static let smallTotal = Font.system(.title2, design: .rounded).weight(.heavy)
    static let row = Font.subheadline.weight(.medium)
    static let heading = Font.subheadline.weight(.semibold)
    static let caption = Font.caption.weight(.semibold)
    static let pill = Font.subheadline.weight(.bold)
    static let eyebrow = Font.caption2.weight(.bold)
    static let date = Font.caption2.weight(.medium)
    static let ringLabel = Font.caption2.weight(.bold)
}

struct WidgetSurface<Content: View>: View {
    let entry: ChallengeWidgetEntry
    let destination: String
    @ViewBuilder let content: () -> Content
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            if entry.state == .ready { content() }
            else if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "drop").font(.system(size: 20, weight: .semibold))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Daily Challenge. " + entry.state.message)
            } else {
                WidgetStatusView(state: entry.state, compact: family == .systemSmall)
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .modifier(WidgetBackground(accessory: family == .accessoryCircular))
        .widgetURL(URL(string: "daily-challenge://\(destination)")!)
        .privacySensitive()
    }
}

private struct WidgetBackground: ViewModifier {
    let accessory: Bool
    func body(content: Content) -> some View {
        if accessory { content.containerBackground(.clear, for: .widget) }
        else { content.containerBackground(Theme.solidGlass, for: .widget) }
    }
}

/// Signed out, no challenge, or storage the widget cannot read: calm, no cached data.
/// Small stacks it top to bottom; medium and large centre it.
struct WidgetStatusView: View {
    let state: ChallengeWidgetEntry.State
    var compact = false
    var body: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        AppMark(size: 24)
                        Text("Daily Challenge").font(WidgetFont.heading).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                    message(WidgetFont.caption, alignment: .leading)
                    open
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(spacing: 8) {
                    AppMark(size: 32)
                    Text("Daily Challenge").font(WidgetFont.heading).lineLimit(1)
                    message(WidgetFont.row, alignment: .center)
                    open
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func message(_ font: Font, alignment: TextAlignment) -> some View {
        Text(state.message).font(font).foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var open: some View {
        HStack(spacing: 4) {
            Text("Open").font(WidgetFont.caption)
            Image(systemName: "arrow.up.forward").font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(Theme.accentText)
        .accessibilityHidden(true)
    }
}

/// Extension builds wrap a control in its App Intent button. The app target compiles
/// these views for in-process renders and draws the same label without an intent.
/// Without a binding (placeholders, previews) the label stays read-only.
struct WidgetControl<Label: View>: View {
    let request: WidgetActionRequest?
    var enabled = true
    @ViewBuilder let label: () -> Label
    var body: some View {
        #if WIDGET_EXTENSION
        if let request, enabled { WidgetIntentButton(request: request, label: label()) } else { label() }
        #else
        label()
        #endif
    }
}

/// "WATER" eyebrow and the quiet challenge-date label ("10 Oct · Jersey").
struct WidgetHeading: View {
    let title: String
    let entry: ChallengeWidgetEntry
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title.uppercased()).font(WidgetFont.eyebrow).tracking(Theme.Tracking.eyebrow)
                .foregroundStyle(Theme.textSecondary).lineLimit(1).fixedSize()
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            WidgetDateLabel(entry: entry)
        }
    }
}

struct WidgetDateLabel: View {
    let entry: ChallengeWidgetEntry
    var body: some View {
        Text(entry.dateLabel).font(WidgetFont.date).foregroundStyle(Theme.textTertiary)
            .lineLimit(1).minimumScaleFactor(0.8)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .layoutPriority(-1)
            .accessibilityLabel("Challenge day " + entry.dateLabel)
    }
}

// MARK: Water

/// The app's jug, still: no slosh, pour or celebration clocks in the extension.
struct WidgetJugView: View {
    let millilitres: Int
    let height: CGFloat
    var body: some View {
        let canonical = CGSize(width: Theme.Size.jug.width + 8, height: Theme.Size.jug.height + 14)
        let scale = height / canonical.height
        JugDrawing(millilitres: millilitres, level: min(1, max(0, Double(millilitres) / 4_000)))
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: canonical.width * scale, height: height, alignment: .topLeading)
            .widgetAccentable()
            .accessibilityHidden(true)
    }
}

struct WaterWidgetView: View {
    let entry: ChallengeWidgetEntry
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var widgetFamily
    private var family: WidgetFamily { familyOverride ?? widgetFamily }
    private var amount: Int { entry.summary?.waterMillilitres ?? 0 }
    private var goalMet: Bool { amount >= 4_000 }

    var body: some View {
        // Fixed widget sizes: the jug, total and controls stop growing at the largest
        // standard text size; VoiceOver still reads the full value.
        switch family {
        case .accessoryCircular: WaterAccessoryView(entry: entry)
        case .systemSmall: small.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        default: medium.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeading(title: "Water", entry: entry)
            HStack(alignment: .center, spacing: 8) {
                WidgetJugView(millilitres: amount, height: 68)
                VStack(alignment: .leading, spacing: 1) {
                    Text(amount.formatted()).font(WidgetFont.smallTotal).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("ml / 4,000").font(WidgetFont.caption)
                        .foregroundStyle(goalMet ? Theme.doneText : Theme.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .modifier(WaterValue(amount: amount))
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) { minus(size: 36); plus(height: 36) }
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            WidgetJugView(millilitres: amount, height: 124)
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeading(title: "Water", entry: entry)
                Spacer(minLength: 2)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(amount.formatted()) ml").font(WidgetFont.total).tracking(-0.6).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.6).layoutPriority(1)
                        Text("/ 4,000").font(WidgetFont.caption)
                            .foregroundStyle(goalMet ? Theme.doneText : Theme.textSecondary).lineLimit(1)
                    }
                    Text(goalMet ? "Goal met · 4 L" : "\((4_000 - amount).formatted()) ml to go · 4 L goal")
                        .font(WidgetFont.caption).foregroundStyle(goalMet ? Theme.doneText : Theme.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .modifier(WaterValue(amount: amount))
                Spacer(minLength: 6)
                HStack(spacing: 10) { minus(size: 40); plus(height: 40) }
            }
        }
    }

    /// Minus targets today's latest active pour; with none it is disabled (and a
    /// stale invocation is a no-op in the recorder).
    private var canUndo: Bool { !(entry.summary?.activePours.isEmpty ?? true) }

    /// Primary gradient pill until the goal is met, then the quieter tinted pill (as in Today).
    private func plus(height: CGFloat) -> some View {
        WidgetControl(request: entry.binding.map { WidgetActionRequest(.pour, binding: $0) }) {
            PourPill(height: height, quiet: goalMet)
        }
    }

    private func minus(size: CGFloat) -> some View {
        WidgetControl(request: entry.binding.map { WidgetActionRequest(.undoPour, binding: $0) }, enabled: canUndo) {
            Image(systemName: "minus")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: size, height: size)
                .background(Circle().fill(Theme.controlFill))
                .opacity(canUndo ? 1 : 0.4)
                .contentShape(Circle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(canUndo ? "Undo latest pour" : "Undo latest pour, no pour today")
        }
    }
}

/// Water's spoken value: the actual millilitres (uncapped) against the 4,000 ml goal.
private struct WaterValue: ViewModifier {
    let amount: Int
    func body(content: Content) -> some View {
        content.accessibilityElement(children: .ignore)
            .accessibilityLabel("Water, \(amount.formatted()) of 4,000 millilitres" + (amount > 4_000 ? ", goal exceeded" : amount == 4_000 ? ", goal met" : ""))
    }
}

struct PourPill: View {
    let height: CGFloat
    let quiet: Bool
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.widgetAccentedOverride) private var override
    var body: some View {
        let accented = override ?? (mode == .accented)
        HStack(spacing: 5) {
            Image(systemName: "plus").font(.system(size: 13, weight: .heavy))
            Text("450 ml").font(WidgetFont.pill).lineLimit(1).minimumScaleFactor(0.7)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .foregroundStyle(accented || quiet ? Theme.textPrimary : .white)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background {
            if accented { Capsule(style: .circular).fill(.white.opacity(0.22)) }
            else if quiet { Capsule(style: .circular).fill(Theme.controlFill) }
            else {
                Capsule(style: .circular).fill(Theme.primaryGradient)
                    .overlay(Capsule(style: .circular).strokeBorder(.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: Theme.primaryShadow, radius: 5, y: 3)
            }
        }
        .contentShape(Capsule(style: .circular))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Add 450 ml")
    }
}

/// D-W2: Lock Screen water only, read-only, redacted while locked (privacy-sensitive
/// surface). Litres to one decimal, rounded down so 3,990 ml never reads 4.0; the ring
/// clamps at the goal while the number stays uncapped.
struct WaterAccessoryView: View {
    let entry: ChallengeWidgetEntry
    var body: some View {
        let amount = entry.summary?.waterMillilitres ?? 0
        Gauge(value: Double(min(amount, 4_000)), in: 0...4_000) {
            Image(systemName: "drop.fill")
        } currentValueLabel: {
            Text((Double(amount) / 1_000).formatted(.number.precision(.fractionLength(1)).rounded(rule: .down)))
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Water, \(amount.formatted()) of 4,000 millilitres")
    }
}

// MARK: Requirements

struct RequirementsWidgetView: View {
    let entry: ChallengeWidgetEntry
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                dayBadge
                streak
                Spacer(minLength: 4)
                WidgetDateLabel(entry: entry)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            HStack(alignment: .top, spacing: 0) {
                habit(.workout, "Workout", "45 min · home / gym", "dumbbell")
                habit(.walk, "Walk", "45 minutes", "figure.walk")
                diet
                habit(.bibleReading, "Bible", "10 pages", "book")
            }
            // Fixed 64 pt rings in four equal columns: the labels stop at extra large.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .frame(maxHeight: .infinity)
        }
    }

    /// "Day 12", green with a check once all five are complete (as in Today).
    private var dayBadge: some View {
        let complete = entry.summary?.isComplete == true
        let text = entry.dayNumber.map { "Day \($0)" } ?? "Starts soon"
        return HStack(spacing: 4) {
            if complete { Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)) }
            Text(text).font(WidgetFont.caption).monospacedDigit().lineLimit(1)
        }
        .foregroundStyle(complete ? Theme.doneText : Theme.dayBadgeText)
        .padding(.horizontal, 9).frame(minHeight: 22)
        .background(Capsule(style: .circular).fill(complete ? Theme.doneTint : Theme.dayBadgeFill))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.dayNumber.map { "Day \($0) of 75" + (complete ? ", all five complete" : "") } ?? "Challenge starts soon")
    }

    private var streak: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill").font(.system(size: 12))
                .foregroundStyle(LinearGradient(colors: [Theme.amber, Theme.amberText], startPoint: .top, endPoint: .bottom))
            Text("\(entry.streak)").font(WidgetFont.caption).monospacedDigit().foregroundStyle(Theme.amberText)
            Text("/ 75").font(WidgetFont.date).foregroundStyle(Theme.textSecondary)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current streak: \(entry.streak) days")
    }

    private func habit(_ habit: Challenge.Habit, _ title: String, _ detail: String, _ icon: String) -> some View {
        let done = entry.summary?.completedHabits.contains(habit) == true
        return WidgetControl(request: entry.binding.map { WidgetActionRequest(.toggleHabit(habit), binding: $0) }) {
            ring(icon, title, done ? .done : .pending,
                 spoken: "\(title), \(detail), \(done ? "done" : "pending")")
        }
    }

    /// D-W1: pending ↔ clean from the widget. A missed day is never changed here;
    /// its ring links into the app, which keeps the full cycle.
    @ViewBuilder private var diet: some View {
        if entry.summary?.diet == .missed {
            Link(destination: URL(string: "daily-challenge://today")!) {
                ring("leaf", "Diet", .missed, spoken: "Clean diet, missed. Opens Daily Challenge to change it")
            }
        } else {
            let clean = entry.summary?.diet == .clean
            WidgetControl(request: entry.binding.map { WidgetActionRequest(.toggleDiet, binding: $0) }) {
                ring("leaf", "Diet", clean ? .done : .pending,
                     spoken: "Clean diet, your own rules, \(clean ? "done" : "pending")")
            }
        }
    }

    private func ring(_ icon: String, _ title: String, _ state: RingGauge.State, spoken: String) -> some View {
        RingGauge(symbol: icon, label: title, state: state, labelFont: WidgetFont.ringLabel)
            .widgetAccentable(state != .pending)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
    }
}

// MARK: Extras

struct ExtrasWidgetView: View {
    let entry: ChallengeWidgetEntry
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var widgetFamily
    private var family: WidgetFamily { familyOverride ?? widgetFamily }
    @Environment(\.dynamicTypeSize) private var typeSize

    /// No scrolling in a widget: medium shows three rows, large all ten at standard
    /// sizes. Accessibility sizes show fewer rows; the overflow link stays.
    static func visibleRows(large: Bool, accessibility: Bool) -> Int {
        accessibility ? (large ? 5 : 1) : (large ? 10 : 3)
    }

    var body: some View {
        let summary = entry.summary
        let extras = summary?.extras ?? []
        let large = family == .systemLarge
        let limit = Self.visibleRows(large: large, accessibility: typeSize.isAccessibilitySize)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label {
                    Text(extras.isEmpty ? "Extras" : "Extras · \(summary?.extrasDone ?? 0)/\(extras.count)")
                } icon: {
                    Image(systemName: "checklist")
                }
                .font(WidgetFont.heading).foregroundStyle(Theme.textSecondary).lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(extras.isEmpty ? "Extras" : "Extras, \(summary?.extrasDone ?? 0) of \(extras.count) done")
                .accessibilityAddTraits(.isHeader)
                .layoutPriority(1)
                Spacer(minLength: 4)
                WidgetDateLabel(entry: entry)
            }
            if extras.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add your own to-dos").font(WidgetFont.row)
                    Text("Optional daily ticks that never affect the five or your streak.")
                        .font(WidgetFont.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .accessibilityElement(children: .combine)
            } else {
                ForEach(extras.prefix(limit)) { extra in
                    row(extra, done: summary?.completedExtras.contains(extra.id) == true, large: large)
                }
                Spacer(minLength: 0)
                if extras.count > limit {
                    Link(destination: URL(string: "daily-challenge://extras")!) {
                        HStack(spacing: 3) {
                            Text("Open all \(extras.count) extras")
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                        }
                        .font(WidgetFont.caption).foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityLabel("Open all \(extras.count) extras")
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The app's checklist row: filled green check or empty circle, title dimmed when done.
    private func row(_ extra: Challenge.Extra, done: Bool, large: Bool) -> some View {
        WidgetControl(request: entry.binding.map { WidgetActionRequest(.toggleExtra(extra.id), binding: $0) }) {
            HStack(spacing: 10) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21)).foregroundStyle(done ? Theme.done : Theme.textTertiary)
                    .widgetAccentable(done)
                Text(extra.title).font(WidgetFont.row)
                    .foregroundStyle(done ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, minHeight: large ? 28 : 27, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(extra.title + (done ? ", done" : ", pending"))
        }
    }
}
