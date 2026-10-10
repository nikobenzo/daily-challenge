import ChallengeCore
import SwiftUI
import WidgetKit

struct WidgetSurface<Content: View>: View {
    let entry: ChallengeWidgetEntry
    let destination: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        Group {
            if entry.state == .ready { content() }
            else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Daily Challenge", systemImage: "drop.circle")
                        .font(.headline)
                    Text(entry.state.message).font(.subheadline)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .containerBackground(Theme.solidGlass, for: .widget)
        .widgetURL(URL(string: "daily-challenge://\(destination)")!)
        .privacySensitive()
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

struct WidgetHeading: View {
    let title: String
    let entry: ChallengeWidgetEntry
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer(minLength: 4)
            Text(entry.dateLabel).font(.system(size: 10)).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
    }
}

struct WaterWidgetView: View {
    let entry: ChallengeWidgetEntry
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var widgetFamily
    private var family: WidgetFamily { familyOverride ?? widgetFamily }
    var body: some View {
        let amount = entry.summary?.waterMillilitres ?? 0
        let small = family == .systemSmall
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeading(title: "Water", entry: entry)
            HStack(spacing: small ? 10 : 14) {
                WidgetJugView(fraction: Double(amount) / 4_000)
                    .frame(width: small ? 34 : 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(amount.formatted() + " ml").font(.system(size: small ? 19 : 28, weight: .semibold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
                    Text("4,000 ml / 4 L").font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    if !small {
                        Text(amount >= 4_000 ? "Goal met" : "Today's water").font(.caption).foregroundStyle(Theme.water)
                    }
                }
                .accessibilityElement(children: .combine)
                if !small {
                    Spacer(minLength: 0)
                    VStack(spacing: 8) { plus; minus }.frame(width: 104)
                }
            }.frame(maxHeight: .infinity)
            if small { HStack(spacing: 8) { minus.frame(width: 44); plus } }
        }
    }

    /// Minus targets today's latest active pour; with none it is disabled (and a
    /// stale invocation is a no-op in the recorder).
    private var canUndo: Bool { !(entry.summary?.activePours.isEmpty ?? true) }
    private var plus: some View {
        WidgetControl(request: entry.binding.map { WidgetActionRequest(.pour, binding: $0) }) {
            Label("450 ml", systemImage: "plus")
                .font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(Theme.textInverse)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(Capsule().fill(Theme.water))
                .accessibilityLabel("Add 450 ml")
        }
    }
    private var minus: some View {
        WidgetControl(request: entry.binding.map { WidgetActionRequest(.undoPour, binding: $0) }, enabled: canUndo) {
            Image(systemName: "minus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.water)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(Capsule().fill(Theme.accentTint))
                .opacity(canUndo ? 1 : 0.4)
                .accessibilityLabel("Undo latest pour")
        }
    }
}

/// Static gallon-style silhouette. The actual challenge goal remains 4 L.
struct WidgetJugShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.35, y: 0))
        for point in [CGPoint(x: w * 0.65, y: 0), CGPoint(x: w * 0.65, y: h * 0.12),
                      CGPoint(x: w * 0.9, y: h * 0.28), CGPoint(x: w * 0.96, y: h * 0.4),
                      CGPoint(x: w * 0.96, y: h * 0.9)] { p.addLine(to: point) }
        p.addQuadCurve(to: CGPoint(x: w * 0.85, y: h), control: CGPoint(x: w * 0.96, y: h))
        p.addLine(to: CGPoint(x: w * 0.15, y: h))
        p.addQuadCurve(to: CGPoint(x: w * 0.04, y: h * 0.9), control: CGPoint(x: w * 0.04, y: h))
        for point in [CGPoint(x: w * 0.04, y: h * 0.4), CGPoint(x: w * 0.1, y: h * 0.28),
                      CGPoint(x: w * 0.35, y: h * 0.12)] { p.addLine(to: point) }
        p.closeSubpath()
        return p
    }
}
struct WidgetJugView: View {
    let fraction: Double
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                WidgetJugShape().fill(Theme.ringTrack)
                Rectangle().fill(LinearGradient(colors: [Theme.jugTop, Theme.jugBottom], startPoint: .top, endPoint: .bottom))
                    .frame(height: proxy.size.height * min(1, max(0, fraction)))
                WidgetJugShape().stroke(Theme.water, lineWidth: 2)
                RoundedRectangle(cornerRadius: 5).fill(Theme.solidGlass)
                    .frame(width: proxy.size.width * 0.14, height: proxy.size.height * 0.18)
                    .offset(x: proxy.size.width * 0.27, y: -proxy.size.height * 0.48)
            }.clipShape(WidgetJugShape())
        }
    }
}

struct WidgetStatusRing: View {
    let done: Bool
    var missed = false
    var body: some View {
        ZStack {
            Circle().stroke(Theme.ringTrack, lineWidth: 3)
            if done || missed { Circle().stroke(missed ? Theme.danger : Theme.done, lineWidth: 3) }
            if done || missed { Image(systemName: missed ? "xmark" : "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(missed ? Theme.danger : Theme.doneText) }
        }.frame(width: 23, height: 23).accessibilityHidden(true)
    }
}
struct RequirementsWidgetView: View {
    let entry: ChallengeWidgetEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeading(title: "Challenge", entry: entry)
            let summary = entry.summary
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 9) {
                    habit(.workout, "Workout · 45 min")
                    habit(.walk, "Walk · 45 min")
                }
                VStack(alignment: .leading, spacing: 9) {
                    diet
                    habit(.bibleReading, "Bible · 10 pages")
                }
            }.frame(maxHeight: .infinity)
            Text(entry.dayNumber.map { "Day \($0) · \(entry.streak) day streak" } ?? "Challenge starts soon")
                .font(.caption2).foregroundStyle(Theme.textSecondary)
        }
    }
    private func habit(_ habit: Challenge.Habit, _ title: String) -> some View {
        WidgetControl(request: entry.binding.map { WidgetActionRequest(.toggleHabit(habit), binding: $0) }) {
            row(title, done: entry.summary?.completedHabits.contains(habit) == true)
        }
    }
    /// D-W1: pending ↔ clean from the widget. A missed day is never changed here;
    /// its row links into the app, which keeps the full cycle.
    @ViewBuilder private var diet: some View {
        if entry.summary?.diet == .missed {
            Link(destination: URL(string: "daily-challenge://today")!) {
                row("Diet · missed", done: false, missed: true).foregroundStyle(Theme.textPrimary)
            }.tint(Theme.textPrimary)
        } else {
            WidgetControl(request: entry.binding.map { WidgetActionRequest(.toggleDiet, binding: $0) }) {
                row("Clean diet", done: entry.summary?.diet == .clean)
            }
        }
    }
    private func row(_ title: String, done: Bool, missed: Bool = false) -> some View {
        HStack(spacing: 7) { WidgetStatusRing(done: done, missed: missed); Text(title).font(.system(size: 12)).lineLimit(1).minimumScaleFactor(0.8) }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading).contentShape(Rectangle())
            .accessibilityElement(children: .ignore).accessibilityLabel(title + (done ? ", done" : missed ? "" : ", pending"))
    }
}
struct ExtrasWidgetView: View {
    let entry: ChallengeWidgetEntry
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var widgetFamily
    private var family: WidgetFamily { familyOverride ?? widgetFamily }
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let summary = entry.summary
        let extras = summary?.extras ?? []
        let limit = typeSize.isAccessibilitySize ? (family == .systemLarge ? 5 : 1) : (family == .systemLarge ? 10 : 3)
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeading(title: "Extras · \(summary?.extrasDone ?? 0)/\(extras.count)", entry: entry)
            if extras.isEmpty {
                Label("Extras · Add your own to-dos", systemImage: "checklist")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    .frame(maxHeight: .infinity, alignment: .leading)
            } else {
                ForEach(extras.prefix(limit)) { extra in
                    let done = summary?.completedExtras.contains(extra.id) == true
                    WidgetControl(request: entry.binding.map { WidgetActionRequest(.toggleExtra(extra.id), binding: $0) }) {
                        HStack(spacing: 9) {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? Theme.doneText : Theme.textTertiary).accessibilityHidden(true)
                            Text(extra.title).font(.system(size: typeSize.isAccessibilitySize ? 17 : 13)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        .accessibilityElement(children: .ignore).accessibilityLabel(extra.title + (done ? ", done" : ", pending"))
                    }
                }
                Spacer(minLength: 0)
                if extras.count > limit {
                    Link("Open all \(extras.count) extras", destination: URL(string: "daily-challenge://extras")!)
                        .font(.caption).foregroundStyle(Theme.accentText)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
