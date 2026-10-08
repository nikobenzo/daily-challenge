import ChallengeCore
import Foundation

// Fixtures written before per-challenge timezones describe Jersey challenges.
// Production code always passes a zone; these keep those fixtures explicit.
extension Challenge {
    init(ownerID: UUID, startDate: Date) {
        self.init(ownerID: ownerID, startDate: startDate, timeZone: Challenge.legacyTimeZone)
    }
}

extension ChallengeRecord {
    init(id: UUID = UUID(), ownerID: UUID, startDate: Date) {
        self.init(id: id, ownerID: ownerID, startDate: startDate, timeZone: Challenge.legacyTimeZone)
    }
}

extension ChallengeStore {
    mutating func start(on date: Date) throws { try start(on: date, timeZone: Challenge.legacyTimeZone) }
}

extension WaterReminderPlanner {
    init(clock: @escaping () -> Date) { self.init(timeZone: Challenge.legacyTimeZone, clock: clock) }
}

func zone(_ identifier: String) -> TimeZone { Challenge.canonicalTimeZone(identifier)! }
