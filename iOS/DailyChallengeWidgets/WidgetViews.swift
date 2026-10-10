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
    @Environment(\.widgetFamily) private var family
    var body: some View {
        let amount = entry.summary?.waterMillilitres ?? 0
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeading(title: "Water", entry: entry)
            HStack(spacing: 14) {
                WidgetJugView(fraction: Double(amount) / 4_000)
                    .frame(width: family == .systemSmall ? 46 : 70)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(amount.formatted() + " ml").font(.system(size: family == .systemSmall ? 19 : 28, weight: .semibold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
                    Text("4,000 ml / 4 L").font(.caption).foregroundStyle(Theme.textSecondary)
                    if family == .systemMedium {
                        Text(amount >= 4_000 ? "Goal met" : "Today's water").font(.caption).foregroundStyle(Theme.water)
                        Text("Open to log a pour").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
            }.frame(maxHeight: .infinity)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Static gallon-style silhouette. The actual challenge goal remains 4 L.
struct WidgetJugShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.35, y: 0))
        p.addLines([CGPoint(x: w * 0.65, y: 0), CGPoint(x: w * 0.65, y: h * 0.12),
                    CGPoint(x: w * 0.9, y: h * 0.28), CGPoint(x: w * 0.96, y: h * 0.4),
                    CGPoint(x: w * 0.96, y: h * 0.9)])
        p.addQuadCurve(to: CGPoint(x: w * 0.85, y: h), control: CGPoint(x: w * 0.96, y: h))
        p.addLine(to: CGPoint(x: w * 0.15, y: h))
        p.addQuadCurve(to: CGPoint(x: w * 0.04, y: h * 0.9), control: CGPoint(x: w * 0.04, y: h))
        p.addLines([CGPoint(x: w * 0.04, y: h * 0.4), CGPoint(x: w * 0.1, y: h * 0.28),
                    CGPoint(x: w * 0.35, y: h * 0.12)])
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
                    .clipShape(WidgetJugShape())
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
                    row("Workout · 45 min", done: summary?.completedHabits.contains(.workout) == true)
                    row("Walk · 45 min", done: summary?.completedHabits.contains(.walk) == true)
                }
                VStack(alignment: .leading, spacing: 9) {
                    row(summary?.diet == .missed ? "Diet · missed" : "Clean diet", done: summary?.diet == .clean, missed: summary?.diet == .missed)
                    row("Bible · 10 pages", done: summary?.completedHabits.contains(.bibleReading) == true)
                }
            }.frame(maxHeight: .infinity)
            Text(entry.dayNumber.map { "Day \($0) · \(entry.streak) day streak" } ?? "Challenge starts soon")
                .font(.caption2).foregroundStyle(Theme.textSecondary)
        }
    }
    private func row(_ title: String, done: Bool, missed: Bool = false) -> some View {
        HStack(spacing: 7) { WidgetStatusRing(done: done, missed: missed); Text(title).font(.system(size: 12)).lineLimit(1).minimumScaleFactor(0.8) }
            .accessibilityElement(children: .ignore).accessibilityLabel(title + (done ? ", done" : missed ? "" : ", pending"))
    }
}
struct ExtrasWidgetView: View {
    let entry: ChallengeWidgetEntry
    @Environment(\.widgetFamily) private var family
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
                    HStack(spacing: 9) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? Theme.doneText : Theme.textTertiary).accessibilityHidden(true)
                        Text(extra.title).font(.system(size: typeSize.isAccessibilitySize ? 17 : 13)).lineLimit(1)
                    }.accessibilityElement(children: .ignore).accessibilityLabel(extra.title + (done ? ", done" : ", pending"))
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
