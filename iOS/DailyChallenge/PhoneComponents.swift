import ChallengeSyncKit
import SwiftUI

// iPhone-only pieces of the design system: the full-screen backdrop and the glass card
// that stands in for the Mac's popup sheet. Tokens and shared components come from
// Sources/DailyChallengeProof/Shared.

extension Theme {
    /// The backdrop the glass sits on (the Mac's sheet sits on the desktop instead).
    static let backdropTop = color(dark: hex(0x1A2260), light: hex(0xEAF1FF))
    static let backdropBottom = color(dark: hex(0x070A26), light: hex(0xD5E2FB))
    static let backdropGlow = color(dark: rgba(74, 128, 255, 0.35), light: rgba(111, 176, 255, 0.45))
}

struct PhoneBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.backdropTop, Theme.backdropBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.backdropGlow, .clear], center: .topTrailing, startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The Mac's glass sheet on a phone: rounded 28, translucent tint over a blur, 1 pt border
/// and top highlight. Reduce Transparency draws the tint opaque; Increase Contrast
/// strengthens the border. Sections inside are separated by hairlines.
struct GlassCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Size.sheetRadius, style: .continuous)
        VStack(spacing: 0, content: content)
            .background {
                if reduceTransparency {
                    shape.fill(Theme.solidGlass)
                } else {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Theme.glass)
                }
            }
            .overlay {
                shape.inset(by: 0.5)
                    .stroke(LinearGradient(colors: [Theme.glassHighlight, .clear], startPoint: .top,
                                           endPoint: .init(x: 0.5, y: 0.08)), lineWidth: 1)
            }
            .overlay {
                shape.strokeBorder(contrast == .increased ? Theme.textPrimary.opacity(0.7) : Theme.glassBorder, lineWidth: 1)
            }
            .clipShape(shape)
            .shadow(color: Theme.sheetShadow, radius: 24, y: 12)
    }
}

/// A screen: backdrop, scrolling content with the standard margins.
struct PhoneScreen<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if DEBUG
        ScrollViewReader { proxy in
            screen.task {
                if PhoneFixtures.isFixtureLaunch {
                    // iOS restores scene scroll positions between fixture launches.
                    // Reset explicitly so captures start at the requested surface.
                    try? await Task.sleep(for: .milliseconds(300))
                    proxy.scrollTo(PhoneFixtures.scrollAnchor ?? "fixture-screen-top", anchor: .top)
                }
            }
        }
        #else
        screen
        #endif
    }

    private var screen: some View {
        ScrollView {
            VStack(spacing: Theme.Space.m, content: content)
                .padding(.horizontal, Theme.Space.m)
                .padding(.bottom, Theme.Space.xl)
                .id("fixture-screen-top")
        }
        .scrollIndicators(.automatic)
        .background(PhoneBackdrop())
    }
}

/// App mark, name and the Day badge, the phone version of the popup header.
struct PhoneHeader<Trailing: View>: View {
    var title = "Daily Challenge"
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            AppMark(size: 30)
            Text(title).font(Theme.Fonts.screenTitle).tracking(Theme.Tracking.screenTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.top, Theme.Space.xs)
    }
}

extension PhoneHeader where Trailing == EmptyView {
    init(title: String = "Daily Challenge") { self.init(title: title) { EmptyView() } }
}

/// "Day 12" (green with a check once today is complete).
struct DayBadge: View {
    let tracker: TrackerModel

    var body: some View {
        let today = tracker.challenge?.summary(on: tracker.today, asOf: tracker.now)
        let complete = today?.isComplete == true
        let done = today.map { $0.completedHabits.count + ($0.waterComplete ? 1 : 0) + ($0.diet == .clean ? 1 : 0) } ?? 0
        Badge(symbol: complete ? "checkmark" : nil, text: "Day \(tracker.dayNumber)",
              fill: complete ? Theme.doneTint : Theme.dayBadgeFill,
              foreground: complete ? Theme.doneText : Theme.dayBadgeText, height: 30)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Day \(tracker.dayNumber)\(complete ? ", complete" : ", \(done) of 5 done")")
    }
}

/// The sync state as a chip: glyph and a short word or time; tapping syncs now.
struct SyncChip: View {
    let tracker: TrackerModel

    var body: some View {
        let state = tracker.syncState
        Button {
            guard tracker.syncActive, !tracker.isSyncing else { return }
            Task { await tracker.sync(force: true) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: SyncWords.symbol(state)).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SyncWords.tint(state))
                Text(SyncWords.shortText(state)).font(Theme.Fonts.badge).monospacedDigit()
                    .foregroundStyle(SyncWords.textTint(state))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(Capsule(style: .circular).fill(Theme.controlFill))
            .contentShape(Capsule(style: .circular))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tracker.syncState.plainText(on: .iPhone))
        .accessibilityHint(tracker.syncActive ? "Syncs your challenge now" : "")
        .accessibilityIdentifier("sync-status")
    }
}

/// The footer's sync glyphs and short words, as on the Mac.
enum SyncWords {
    static func symbol(_ state: SyncState) -> String {
        switch state {
        case .synced(_, true): "clock.badge.exclamationmark"
        case .synced: "checkmark.icloud"
        case .checking, .savedLocally: "icloud.and.arrow.up"
        case .awaitingCheck: "icloud"
        case .unavailable: "exclamationmark.icloud"
        case .localOnly: "icloud.slash"
        }
    }

    static func shortText(_ state: SyncState) -> String {
        switch state {
        case let .synced(date, _): date.formatted(date: .omitted, time: .shortened)
        case .checking: "Syncing"
        case let .savedLocally(pending): "\(pending) pending"
        case .awaitingCheck: "Checking"
        case .unavailable: "Retry"
        case .localOnly: "Local only"
        }
    }

    static func tint(_ state: SyncState) -> Color {
        switch state {
        case .synced(_, false): Theme.done
        case .synced(_, true), .unavailable: Theme.amber
        case .checking, .savedLocally, .awaitingCheck: Theme.accentText
        case .localOnly: Theme.textTertiary
        }
    }

    static func textTint(_ state: SyncState) -> Color {
        switch state {
        case .unavailable: Theme.amberText
        case .localOnly: Theme.textTertiary
        default: Theme.textSecondary
        }
    }
}

/// A centred icon, title, detail and actions: unavailable, checking and configuration states.
struct NoticeCard<Actions: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        GlassCard {
            VStack(spacing: 12) {
                HeroIcon(symbol: symbol)
                Text(title).font(Theme.Fonts.rowLabel).foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(detail).font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                actions()
            }
            .padding(.horizontal, Theme.Size.sectionHorizontal)
            .padding(.vertical, Theme.Space.xl)
            .frame(maxWidth: .infinity)
        }
    }
}

/// The tracker's last error under the content, dismissible.
struct ErrorBanner: View {
    let tracker: TrackerModel

    var body: some View {
        if let error = tracker.errorMessage {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.danger)
                    .accessibilityHidden(true)
                Text(error).font(Theme.Fonts.caption).foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button { tracker.dismissError() } label: { Image(systemName: "xmark") }
                    .buttonStyle(RoundIconStyle(size: 30))
                    .accessibilityLabel("Dismiss error")
            }
            .padding(Theme.Space.s)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.dangerTint))
        }
    }
}
