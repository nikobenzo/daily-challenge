import ChallengeCore
import Foundation

/// A finite presentation clock. No timer is needed outside this interval.
public struct WaterMotion: Equatable, Sendable {
    public static let duration: TimeInterval = 1.2
    public let from: Int
    public let to: Int
    public let started: Date
    public let initialLevel: Double

    public init(from: Int, to: Int, started: Date, presentationLevel: Double? = nil) {
        self.from = from
        self.to = to
        self.started = started
        initialLevel = presentationLevel ?? Double(min(4_000, from)) / 4_000
    }

    public func isActive(at date: Date, visible: Bool, reduceMotion: Bool) -> Bool {
        visible && !reduceMotion && date >= started && date < started.addingTimeInterval(Self.duration)
    }

    public func progress(at date: Date) -> Double {
        min(1, max(0, date.timeIntervalSince(started) / Self.duration))
    }

    public func level(at date: Date) -> Double {
        let p = min(1, progress(at: date) / 0.55)
        let eased = 1 - pow(1 - p, 3)
        let targetLevel = Double(min(4_000, to)) / 4_000
        return initialLevel + (targetLevel - initialLevel) * eased
    }

    public func slosh(at date: Date) -> Double {
        let p = progress(at: date)
        return sin(p * .pi * 6) * pow(1 - p, 2) * 9
    }

    public var frameDates: [Date] { finiteFrames(started: started, duration: Self.duration) }
    public var spills: Bool { to > 4_000 && to > from }
}

public enum CompletionCelebration: String, Codable, Sendable { case daily, milestone, extras }

/// Separate from synced history and backups. Observed completions are consumed even
/// on open/sync/import, so undo/recomplete cannot replay an existing achievement.
/// A failed/corrupt ledger suppresses effects rather than risking replay.
public struct CelebrationLedger {
    public let file: URL

    public init(file: URL) { self.file = file }

    /// Extras have their own key: ticking the last extra today celebrates once, even
    /// on a day the five were already complete, and never after undo and re-tick.
    public func observe(_ challenge: Challenge, challengeID: UUID, now: Date,
                        localCompletionDay: Date? = nil, localExtrasDay: Date? = nil) -> CompletionCelebration? {
        do {
            var seen: Set<String> = FileManager.default.fileExists(atPath: file.path)
                ? try JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: file)) : []
            let today = challenge.calendar.startOfDay(for: now)
            func key(_ kind: String, _ day: Date) -> String {
                "\(challengeID.uuidString)/\(kind)/\(day.timeIntervalSince1970)"
            }
            let completeDays = Set(challenge.allActivities.map(\.day)).filter {
                challenge.summary(on: $0, asOf: now).isComplete
            }
            let milestones = challenge.streaks(asOf: now).milestones
            let eligible = localCompletionDay == today && completeDays.contains(today)
            let daily = eligible && !seen.contains(key("day", today))
            let milestone = eligible && milestones.contains(today) && !seen.contains(key("milestone", today))
            let extrasDays = Set(challenge.allActivities.map(\.day)).filter {
                challenge.summary(on: $0, asOf: now).allExtrasDone
            }
            let extras = localExtrasDay == today && extrasDays.contains(today) && !seen.contains(key("extras", today))
            let previous = seen
            completeDays.forEach { seen.insert(key("day", $0)) }
            milestones.forEach { seen.insert(key("milestone", $0)) }
            extrasDays.forEach { seen.insert(key("extras", $0)) }
            if seen != previous {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(seen).write(to: file, options: .atomic)
            }
            return milestone ? .milestone : daily ? .daily : extras ? .extras : nil
        } catch { return nil }
    }
}

public enum CompletionPresentation { case idle, highlight, animated }

public struct CelebrationEvent: Equatable, Sendable {
    public let id = UUID()
    public let kind: CompletionCelebration
    public let started: Date

    public init(kind: CompletionCelebration, started: Date) {
        self.kind = kind
        self.started = started
    }
    public var duration: TimeInterval { kind == .milestone ? 3 : 1.8 }
    public var frameDates: [Date] { finiteFrames(started: started, duration: duration) }

    public func presentation(at date: Date, visible: Bool, reduceMotion: Bool) -> CompletionPresentation {
        guard visible, date >= started, date < started.addingTimeInterval(duration) else { return .idle }
        return reduceMotion ? .highlight : .animated
    }
}

private func finiteFrames(started: Date, duration: TimeInterval) -> [Date] {
    (0...Int(duration * 30)).map { started.addingTimeInterval(Double($0) / 30) }
}

/// Only a finite task owns frame delivery. No SwiftUI display-link/timeline
/// scheduler survives settling; cancellation also prevents later frame writes.
@MainActor public func renderFiniteFrames(_ dates: [Date], update: (Date) -> Void) async throws {
    for date in dates {
        let delay = date.timeIntervalSinceNow
        guard delay > 0 else { continue } // skip missed frames, never catch up in a burst
        try await Task.sleep(for: .seconds(delay))
        try Task.checkCancellation()
        update(Date())
    }
}
