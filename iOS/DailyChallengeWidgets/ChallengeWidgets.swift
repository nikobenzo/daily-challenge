import SwiftUI
import WidgetKit

@main
struct ChallengeWidgets: WidgetBundle {
    var body: some Widget {
        WaterWidget()
        RequirementsWidget()
        ExtrasWidget()
    }
}

struct WaterWidget: Widget {
    static let kind = "DailyChallenge.Water"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ChallengeWidgetProvider()) { entry in
            WidgetSurface(entry: entry, destination: "today") { WaterWidgetView(entry: entry) }
        }
        .configurationDisplayName("Water")
        .description("Log 450 ml pours toward 4,000 ml / 4 L, or undo today's latest pour.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
struct RequirementsWidget: Widget {
    static let kind = "DailyChallenge.Requirements"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ChallengeWidgetProvider()) { entry in
            WidgetSurface(entry: entry, destination: "today") { RequirementsWidgetView(entry: entry) }
        }
        .configurationDisplayName("Daily requirements")
        .description("Tick workout, walk, clean diet and Bible reading for your challenge day.")
        .supportedFamilies([.systemMedium])
    }
}
struct ExtrasWidget: Widget {
    static let kind = "DailyChallenge.Extras"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ChallengeWidgetProvider()) { entry in
            WidgetSurface(entry: entry, destination: "extras") { ExtrasWidgetView(entry: entry) }
        }
        .configurationDisplayName("Extras")
        .description("Tick your optional daily to-dos. Open the app to manage them.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
