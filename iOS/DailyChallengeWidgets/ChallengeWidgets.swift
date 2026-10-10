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
        .description("Today's water toward 4,000 ml / 4 L. Open the app to log a pour.")
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
        .description("Workout, walk, diet and Bible reading for your challenge day.")
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
        .description("Your optional daily to-dos. Open the app to manage or tick them.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
