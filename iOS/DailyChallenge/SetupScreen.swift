import ChallengeCore
import ChallengeSyncKit
import SwiftUI

/// Shown only after the server confirmed this account has no challenge yet (an existing
/// one is adopted by sync instead). Start date and zone cannot change once started.
struct SetupScreen: View {
    @Bindable var tracker: TrackerModel
    @State private var startDate = Date()
    /// Defaults to the phone's zone.
    @State private var timeZone = TimeZone.current
    @State private var choosingZone = false

    var body: some View {
        let dates = ChallengeDates(timeZone: timeZone)
        PhoneScreen {
            PhoneHeader { SyncChip(tracker: tracker) }
            GlassCard {
                VStack(spacing: 6) {
                    Text("Your next 75 days").font(Theme.Fonts.screenTitle).tracking(Theme.Tracking.screenTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Every day, midnight to midnight, all five.")
                        .font(Theme.Fonts.link).foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, Theme.Space.xl)
                HStack(spacing: 0) {
                    requirement("drop.fill", "4,000 ml", detail: "4 litres of water", tint: Theme.water)
                    requirement("dumbbell", "45 min", detail: "45-minute workout, home or gym")
                    requirement("figure.walk", "45 min", detail: "45-minute walk")
                    requirement("leaf", "Clean diet", detail: "Clean diet, your own rules")
                    requirement("book", "10 pages", detail: "10 Bible pages")
                }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .padding(.horizontal, Theme.Space.xs)
                .padding(.vertical, Theme.Space.l)
                HairlineDivider()
                VStack(spacing: 0) {
                    DatePicker(selection: $startDate, in: ...tracker.now, displayedComponents: .date) {
                        Label("Start", systemImage: "calendar").font(Theme.Fonts.rowLabel).foregroundStyle(Theme.textPrimary)
                    }
                    .environment(\.timeZone, timeZone)
                    .environment(\.calendar, dates.calendar)
                    .frame(minHeight: 52)
                    .accessibilityIdentifier("setup-start")
                    Theme.hairline.frame(height: 1)
                    Button { choosingZone = true } label: {
                        HStack {
                            Label("Time zone", systemImage: "globe").font(Theme.Fonts.rowLabel)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(TimeZoneChoices.title(timeZone, at: tracker.now)).font(Theme.Fonts.field)
                                .foregroundStyle(Theme.textSecondary)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Time zone")
                    .accessibilityValue(TimeZoneChoices.title(timeZone, at: tracker.now))
                    .accessibilityHint("The city whose midnight starts each challenge day")
                    .accessibilityIdentifier("setup-zone")
                }
                .padding(.horizontal, Theme.Size.sectionHorizontal)
                HairlineDivider()
                Button { tracker.startChallenge(on: startDate, timeZone: timeZone) } label: {
                    Label("Start challenge", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryPillStyle(height: Theme.Size.largePill, font: Theme.Fonts.appName))
                .padding(.horizontal, Theme.Size.sectionHorizontal)
                .padding(.vertical, Theme.Space.l)
                .accessibilityIdentifier("setup-start-challenge")
            }
            ErrorBanner(tracker: tracker)
            Text(rules).font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Space.xs)
        }
        .sheet(isPresented: $choosingZone) {
            TimeZoneSheet(selection: $timeZone, now: tracker.now)
        }
    }

    private var rules: String {
        "Days follow \(timeZone.identifier), midnight to midnight, including daylight saving. "
            + "The start date and time zone can't be changed after you start. "
            + "Closed unfinished days break the streak. Tracking continues beyond 75. "
            + "Use the same account on your Mac: activity saves on this iPhone first, then syncs."
    }

    private func requirement(_ symbol: String, _ label: String, detail: String, tint: Color = Theme.textPrimary) -> some View {
        VStack(spacing: 8) {
            Circle().stroke(Theme.ringTrack, lineWidth: Theme.Size.ringStroke)
                .padding(Theme.Size.ringStroke / 2)
                .frame(width: 56, height: 56)
                .overlay { Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint) }
            Eyebrow(text: label, color: Theme.textSecondary, font: Theme.Fonts.ringLabel, tracking: Theme.Tracking.ringLabel)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail)
    }
}

/// Searchable by city, region or zone name, grouped by region, with this iPhone's zone first.
struct TimeZoneSheet: View {
    @Binding var selection: TimeZone
    let now: Date
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let groups = TimeZoneChoices.groups(matching: query)
        NavigationStack {
            List {
                if query.isEmpty {
                    Section("This iPhone") { row(.current) }
                }
                ForEach(groups, id: \.region) { group in
                    Section(group.region) {
                        ForEach(group.zones, id: \.identifier) { row($0) }
                    }
                }
            }
            .overlay {
                if groups.isEmpty {
                    ContentUnavailableView("No matching city", systemImage: "globe",
                                           description: Text("Try a nearby larger city in the same time zone."))
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search for your city")
            .navigationTitle("Time zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func row(_ zone: TimeZone) -> some View {
        Button {
            selection = zone
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ChallengeDates.city(zone)).foregroundStyle(.primary)
                    Text(zone.identifier).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(ChallengeDates.offset(zone, at: now)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Image(systemName: "checkmark").font(.caption.weight(.bold))
                    .opacity(zone.identifier == selection.identifier ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ChallengeDates.city(zone)), \(zone.identifier), \(ChallengeDates.offset(zone, at: now))")
        .accessibilityAddTraits(zone.identifier == selection.identifier ? .isSelected : [])
    }
}
