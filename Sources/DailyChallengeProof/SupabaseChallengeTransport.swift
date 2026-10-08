import ChallengeCore
import Foundation
import Supabase

/// Same transport and acknowledgment pattern as the diagnostic proof: immutable
/// insert-ignore, paginated reads, then compare actual rows before acknowledging.
@MainActor final class SupabaseChallengeTransport: ChallengeTransport {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }

    private func validate(_ ownerID: UUID) async throws {
        let session = try await client.auth.session
        guard session.user.id == ownerID else { throw ChallengeSyncError.wrongOwner }
    }

    func fetchChallenge(ownerID: UUID) async throws -> ChallengeRecord? {
        try await validate(ownerID)
        // "*" rather than a column list: a server without the timezone migration
        // returns no time_zone, which decodes as Jersey instead of failing the read.
        let rows: [ChallengeRecord] = try await client.from("challenges")
            .select("*").eq("owner_id", value: ownerID.uuidString).execute().value
        guard rows.count <= 1 else { throw ChallengeSyncError.conflictingChallenge }
        return rows.first
    }

    func insertChallenge(_ record: ChallengeRecord) async throws {
        try await validate(record.ownerID)
        do {
            try await client.from("challenges").upsert(record, onConflict: "owner_id", ignoreDuplicates: true).execute()
        } catch let error as PostgrestError where Self.isMissingTimeZoneColumn(error) {
            throw ChallengeSyncError.serverNeedsTimeZoneUpdate
        }
    }

    /// PostgREST reports an unknown payload column as PGRST204; PostgreSQL itself
    /// as 42703. Either means the owner has not applied the timezone migration.
    static func isMissingTimeZoneColumn(_ error: PostgrestError) -> Bool {
        ["PGRST204", "42703"].contains(error.code) && error.message.contains("time_zone")
    }

    func upload(_ events: [ChallengeEvent], ownerID: UUID) async throws {
        guard events.allSatisfy({ $0.ownerID == ownerID && $0.receivedAt == nil }) else { throw ChallengeSyncError.wrongOwner }
        // Parent pours must exist before any batch containing their undo. This
        // remains true even when a device clock moved backwards between edits.
        let ordered = events.filter { $0.activity.undonePourID == nil }
            + events.filter { $0.activity.undonePourID != nil }
        for offset in stride(from: 0, to: ordered.count, by: 200) {
            try await validate(ownerID)
            try await client.from("challenge_events")
                .upsert(Array(ordered[offset..<min(offset + 200, ordered.count)]),
                        onConflict: "owner_id,id", ignoreDuplicates: true).execute()
        }
    }

    func fetchEvents(ownerID: UUID, challengeID: UUID) async throws -> RemoteEvents {
        var result = RemoteEvents(events: [])
        var offset = 0
        while true {
            try await validate(ownerID)
            let page: [ServerRow<ChallengeEvent>] = try await client.from("challenge_events")
                .select("id,owner_id,challenge_id,activity,received_at")
                .eq("owner_id", value: ownerID.uuidString).eq("challenge_id", value: challengeID.uuidString)
                .order("id", ascending: true).range(from: offset, to: offset + 499).execute().value
            let readable = page.compactMap(\.value)
            result.events.append(contentsOf: readable)
            result.skipped += page.count - readable.count
            // Pages are counted in server rows, so a skipped row never ends paging early.
            if page.count < 500 { return result }
            offset += page.count
        }
    }
}

/// One server row decoded on its own. A row this app can't read (written before the
/// server checks existed, or by a newer client) is nil instead of failing its page,
/// so one bad row can't stop sync for the whole account. Only rows that decoded can
/// acknowledge a pending upload.
struct ServerRow<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: any Decoder) throws {
        value = try? decoder.singleValueContainer().decode(Value.self)
    }
}

/// Reported in the sync status, not as a failure: everything else still synced.
func skippedRowsNotice(_ count: Int) -> String? {
    guard count > 0 else { return nil }
    return count == 1
        ? "1 entry from the server could not be read and was skipped"
        : "\(count) entries from the server could not be read and were skipped"
}
