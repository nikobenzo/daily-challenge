import ChallengeCore
import Foundation

/// Opt-in synchronous storage boundary. Implementations serialize across processes,
/// load afresh, validate account visibility and publish metadata before releasing.
/// No operation passed here may await networking. Default TrackerModel callers do
/// not use this seam and retain their private, single-writer storage behaviour.
public protocol TrackerStoreAccess {
    func observeCompletion(ownerID: UUID, now: Date, localCompletionDay: Date?, localExtrasDay: Date?) throws -> CompletionCelebration?
    func activate(ownerID: UUID?) throws -> ChallengeStore?
    func transaction<Result>(ownerID: UUID, _ operation: (inout ChallengeStore) throws -> Result) throws -> (ChallengeStore, Result)
}

public extension TrackerStoreAccess {
    func observeCompletion(ownerID: UUID, now: Date, localCompletionDay: Date?, localExtrasDay: Date?) throws -> CompletionCelebration? { nil }
}
