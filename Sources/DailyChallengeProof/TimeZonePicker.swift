import ChallengeCore
import ChallengeSyncKit
import SwiftUI

/// Setup-only choice of the zone whose midnights bound every challenge day. A
/// started or adopted challenge never shows it: the zone cannot change later.
struct TimeZonePicker: View {
    @Binding var selection: TimeZone
    let now: Date
    @State private var choosing = false

    var body: some View {
        SettingRow(symbol: "globe", title: "Timezone") {
            Button { choosing = true } label: { chip(TimeZoneChoices.title(selection, at: now)) }
                .buttonStyle(.plain)
                .accessibilityLabel("Time zone")
                .accessibilityValue(TimeZoneChoices.title(selection, at: now))
                .help("Choose the city whose midnight starts each challenge day")
                .popover(isPresented: $choosing, arrowEdge: .bottom) {
                    TimeZoneList(selection: $selection, now: now) { choosing = false }
                }
        }
    }
}

/// Searchable by city, region or zone name ("Sydney", "Australia", "Eastern"),
/// grouped by region when not searching, with this Mac's zone first.
struct TimeZoneList: View {
    @Binding var selection: TimeZone
    let now: Date
    let done: () -> Void
    @State var query = ""

    var body: some View {
        let groups = TimeZoneChoices.groups(matching: query)
        return VStack(alignment: .leading, spacing: 8) {
            TextField("Search for your city", text: $query).textFieldStyle(.roundedBorder)
            List {
                if query.isEmpty {
                    Section("This Mac") { row(.current) }
                }
                ForEach(groups, id: \.region) { group in
                    Section(group.region) {
                        ForEach(group.zones, id: \.identifier) { row($0) }
                    }
                }
            }
            .overlay {
                if groups.isEmpty {
                    Text("No matching city. Try a nearby larger city in the same time zone.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                }
            }
        }
        .padding(12)
        .frame(width: 320, height: 380)
        .trackerSurface()
    }

    private func row(_ zone: TimeZone) -> some View {
        Button {
            selection = zone
            done()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(ChallengeDates.city(zone))
                    Text(zone.identifier).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(ChallengeDates.offset(zone, at: now)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Image(systemName: "checkmark").font(.caption)
                    .opacity(zone.identifier == selection.identifier ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ChallengeDates.city(zone)), \(zone.identifier), \(ChallengeDates.offset(zone, at: now))")
        .accessibilityAddTraits(zone.identifier == selection.identifier ? .isSelected : [])
    }
}
