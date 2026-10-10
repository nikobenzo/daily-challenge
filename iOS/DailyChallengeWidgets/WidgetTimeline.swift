import ChallengeCore
import ChallengeSyncKit
import Foundation
import WidgetKit

/// No account information or credentials enter WidgetKit's cached entries.
struct ChallengeWidgetEntry: TimelineEntry, Sendable {
    enum State: String, Sendable {
        case ready, signedOut, noChallenge, unavailable
        var message: String {
            switch self {
            case .ready: ""
            case .signedOut: "Open Daily Challenge to sign in"
            case .noChallenge: "Open Daily Challenge to set up"
            case .unavailable: "Open Daily Challenge"
            }
        }
    }
    let date: Date
    let state: State
    let summary: Challenge.DailySummary?
    let dayNumber: Int?
    let streak: Int
    let dateLabel: String

    static func derive(_ challenge: Challenge?, at date: Date, state: State = .noChallenge) -> Self {
        guard let challenge else {
            return Self(date: date, state: state, summary: nil, dayNumber: nil, streak: 0, dateLabel: "")
        }
        let dates = ChallengeDates(timeZone: challenge.timeZone)
        let day = dates.calendar.startOfDay(for: date)
        let number = dates.calendar.dateComponents([.day], from: challenge.startDate, to: day).day! + 1
        return Self(date: date, state: .ready, summary: challenge.summary(on: date, asOf: date),
                    dayNumber: number > 0 ? number : nil, streak: challenge.streaks(asOf: date).current,
                    dateLabel: dates.label(date, format: "d MMM") + " · " + ChallengeDates.city(challenge.timeZone))
    }

    /// Gallery/placeholder data is always synthetic, even when signed in.
    static func sample(at date: Date) -> Self {
        let challenge = Challenge(ownerID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, startDate: date, timeZone: Challenge.legacyTimeZone)
        return derive(challenge, at: date)
    }
}

/// Calendar intervals, never 86,400-second arithmetic or device midnight.
enum WidgetDaySchedule {
    static func dates(now: Date, timeZone: TimeZone, days: Int = 3) -> [Date] {
        let calendar = ChallengeDates(timeZone: timeZone).calendar
        var result = [now]
        for _ in 0..<max(1, days) {
            result.append(calendar.dateInterval(of: .day, for: result.last!)!.end)
        }
        return result
    }
}

struct ChallengeWidgetProvider: TimelineProvider {
    private let read: () throws -> Challenge?
    private let clock: () -> Date

    init(store: PhoneSharedStore? = nil, clock: @escaping () -> Date = Date.init) {
        self.clock = clock
        let shared = store ?? Self.extensionStore()
        read = {
            guard let (_, store) = try shared.readActive() else { throw SignedOut() }
            return store.challenge
        }
    }
    private struct SignedOut: Error {}

    private static func extensionStore() -> PhoneSharedStore {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PhoneSharedStore.groupID)
        #if DEBUG
        // An explicit persisted fixture switch crosses the process boundary. It is
        // absent in Release, and fixture history never shares the production root.
        if let container, FileManager.default.fileExists(atPath: container.appendingPathComponent("widget-fixture-enabled").path) {
            return PhoneSharedStore(root: container.appendingPathComponent("WidgetFixtures"))
        }
        #endif
        return PhoneSharedStore(root: container?.appendingPathComponent("ChallengeHistory"))
    }

    func entries(now: Date) -> [ChallengeWidgetEntry] {
        do {
            let challenge = try read()
            return WidgetDaySchedule.dates(now: now, timeZone: challenge?.timeZone ?? Challenge.legacyTimeZone)
                .map { ChallengeWidgetEntry.derive(challenge, at: $0) }
        } catch {
            return [.derive(nil, at: now, state: error is SignedOut ? .signedOut : .unavailable)]
        }
    }

    func placeholder(in context: Context) -> ChallengeWidgetEntry { .sample(at: clock()) }
    func getSnapshot(in context: Context, completion: @escaping (ChallengeWidgetEntry) -> Void) {
        completion(context.isPreview ? .sample(at: clock()) : entries(now: clock())[0])
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ChallengeWidgetEntry>) -> Void) {
        let now = clock()
        let entries = entries(now: now)
        completion(Timeline(entries: entries, policy: .after(entries.count > 1 ? entries.last!.date : now.addingTimeInterval(900))))
    }
}
