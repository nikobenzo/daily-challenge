import ChallengeCore
import Foundation
@testable import ChallengeSyncKit
@testable import DailyChallengeProof

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

extension ChallengeDates {
    static let jersey = ChallengeDates(timeZone: Challenge.legacyTimeZone)
}

@MainActor extension TrackerModel {
    func startChallenge(on date: Date) { startChallenge(on: date, timeZone: Challenge.legacyTimeZone) }
}

@MainActor extension WaterReminderController {
    func refresh(waterMillilitres: Int?, nextDayWaterMillilitres: Int? = nil) {
        refresh(waterMillilitres: waterMillilitres, nextDayWaterMillilitres: nextDayWaterMillilitres,
                timeZone: Challenge.legacyTimeZone)
    }
}
