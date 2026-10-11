import Foundation
import Supabase

/// Deletes the signed-in account on the server: its Auth user and, through the owner
/// cascades, every challenge and diagnostic row (`20261011000100_account_deletion.sql`).
@MainActor public protocol AccountDeletionTransport {
    /// Returns only once the server has deleted the account. Calling it again for an
    /// account that is already gone also succeeds, so a lost response can be retried.
    func deleteAccount(ownerID: UUID) async throws
}

public enum AccountDeletionError: LocalizedError, Equatable {
    case serverNeedsUpdate, wrongAccount

    public var errorDescription: String? {
        switch self {
        case .serverNeedsUpdate: "The server needs the account deletion update first (see docs/production-sync.md)."
        case .wrongAccount: "The signed-in account changed. Open Account again and retry."
        }
    }
}

/// Calls the `delete_own_account` function with the session's own token and the
/// publishable key; it takes no account argument, so it can only delete the caller.
@MainActor public final class SupabaseAccountDeletion: AccountDeletionTransport {
    private let client: SupabaseClient
    public init(client: SupabaseClient) { self.client = client }

    public func deleteAccount(ownerID: UUID) async throws {
        let session = try await client.auth.session
        guard session.user.id == ownerID else { throw AccountDeletionError.wrongAccount }
        do {
            try await client.rpc("delete_own_account").execute()
        } catch let error as PostgrestError where Self.isMissingFunction(error) {
            throw AccountDeletionError.serverNeedsUpdate
        }
    }

    /// PostgREST reports an unknown function as PGRST202; PostgreSQL itself as 42883.
    /// Either means the owner has not applied the account deletion migration.
    public static func isMissingFunction(_ error: PostgrestError) -> Bool {
        ["PGRST202", "42883"].contains(error.code) && error.message.contains("delete_own_account")
    }
}
