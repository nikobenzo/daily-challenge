import ChallengeCore
import Foundation
import Supabase
import Testing
@testable import ChallengeSyncKit

// Delete account: the client flow on a fake transport and temporary folders, and the SDK
// request on intercepted networking. No real account, Keychain or server is used.

@MainActor private final class FakeDeletion: AccountDeletionTransport {
    var calls: [UUID] = []
    var failure: (any Error)?
    func deleteAccount(ownerID: UUID) async throws {
        calls.append(ownerID)
        if let failure { throw failure }
    }
}

@MainActor private struct DeletionFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("account-deletion-\(UUID())")
    let owner = UUID(), other = UUID()
    let now = Date(timeIntervalSince1970: 1_791_554_400)
    let deletion = FakeDeletion()
    let auth: AuthModel
    let tracker: TrackerModel

    init() throws {
        // Another account that used this device keeps its history.
        var other = try ChallengeStore(ownerID: other, directory: directory)
        try other.start(on: now, timeZone: TimeZone(identifier: "Europe/Jersey")!)
        try other.record(.pour(450), on: now, at: now)
        auth = AuthModel(fixtureOwnerID: owner, email: "sam@example.invalid")
        auth.accountDeletion = deletion
        let now = now
        tracker = TrackerModel(directory: directory, clock: { now })
        auth.attachTracker(tracker)
        tracker.startChallenge(on: now, timeZone: TimeZone(identifier: "Europe/Jersey")!)
        tracker.addWater()
        tracker.toggle(.walk)
        // A migration-style backup beside the history belongs to the account too.
        let history = directory.appendingPathComponent("challenge-\(owner.uuidString.lowercased()).json")
        try FileManager.default.copyItem(at: history, to: history.appendingPathExtension("backup-20261011T120000Z-\(UUID())"))
        try Data("{}".utf8).write(to: directory.appendingPathComponent("celebrations-\(owner.uuidString).json"))
    }

    func files(of owner: UUID) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.lowercased().contains(owner.uuidString.lowercased()) }
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

@Test @MainActor func deletingTheAccountSignsOutAndRemovesOnlyThisAccountsLocalCopies() async throws {
    let f = try DeletionFixture(); defer { f.cleanup() }
    #expect(try f.files(of: f.owner).count == 3)
    #expect(f.tracker.store?.pendingCount == 3)

    #expect(await f.auth.deleteAccount(removingLocalData: f.tracker.removeLocalData))
    #expect(f.deletion.calls == [f.owner])
    #expect(f.auth.ownerID == nil && f.auth.signedInEmail == nil)
    #expect(f.auth.authStep == .signIn)
    #expect(f.auth.notice == "Your account and all its challenge history have been deleted.")
    #expect(f.auth.errorMessage == nil)
    #expect(!f.auth.isBusy)
    #expect(f.tracker.ownerID == nil && f.tracker.store == nil)
    // History, pending queue, backup and celebration ledger are gone; the other account's are not.
    #expect(try f.files(of: f.owner).isEmpty)
    let kept = try ChallengeStore(ownerID: f.other, directory: f.directory)
    #expect(kept.challenge?.summary(on: f.now, asOf: f.now).waterMillilitres == 450)
    // Signing in again later starts from an empty device, never the deleted history.
    #expect(try ChallengeStore(ownerID: f.owner, directory: f.directory).record == nil)
}

@Test @MainActor func anOfflineOrFailedDeletionChangesNothingOnTheDevice() async throws {
    let f = try DeletionFixture(); defer { f.cleanup() }
    let before = try f.files(of: f.owner).sorted()
    f.deletion.failure = URLError(.notConnectedToInternet)
    var removed = false

    #expect(!(await f.auth.deleteAccount(removingLocalData: { _ in removed = true })))
    #expect(!removed)
    #expect(f.auth.ownerID == f.owner)
    #expect(f.auth.errorMessage == "Your account was not deleted and nothing was removed. "
        + "Can't reach the server. Check your internet connection and try again.")
    #expect(f.auth.status == "Account not deleted")
    #expect(!f.auth.isBusy)
    #expect(f.tracker.ownerID == f.owner)
    #expect(f.tracker.store?.pendingCount == 3)
    #expect(try f.files(of: f.owner).sorted() == before)

    // A server without the migration says so, and the retry once it is applied succeeds.
    f.deletion.failure = AccountDeletionError.serverNeedsUpdate
    #expect(!(await f.auth.deleteAccount(removingLocalData: f.tracker.removeLocalData)))
    #expect(f.auth.errorMessage?.contains("needs the account deletion update") == true)
    #expect(f.tracker.store?.pendingCount == 3)
    f.deletion.failure = nil
    #expect(await f.auth.deleteAccount(removingLocalData: f.tracker.removeLocalData))
    #expect(f.deletion.calls == [f.owner, f.owner, f.owner])
    #expect(try f.files(of: f.owner).isEmpty)
}

@Test @MainActor func aDeletedAccountIsReportedEvenIfTheLocalCopyCannotBeRemoved() async throws {
    let f = try DeletionFixture(); defer { f.cleanup() }
    #expect(await f.auth.deleteAccount(removingLocalData: { _ in throw CocoaError(.fileWriteNoPermission) }))
    #expect(f.auth.ownerID == nil)
    #expect(f.auth.errorMessage?.hasPrefix("Your account and its synced history were deleted, but the copy on this device could not be removed") == true)
    #expect(f.auth.notice == nil)
}

@Test @MainActor func deletionNeedsASignedInAccountAndATransport() async throws {
    let signedOut = AuthModel(fixtureOwnerID: nil)
    let deletion = FakeDeletion()
    signedOut.accountDeletion = deletion
    #expect(!(await signedOut.deleteAccount(removingLocalData: { _ in Issue.record("Removed data while signed out") })))
    #expect(deletion.calls.isEmpty)
    let offlineFixture = AuthModel(fixtureOwnerID: UUID())
    #expect(!(await offlineFixture.deleteAccount(removingLocalData: { _ in Issue.record("Removed data without a server") })))
    #expect(offlineFixture.ownerID != nil)
}

// MARK: SDK request

private final class MemoryOnlyAuth: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { lock.withLock { _ = values.removeValue(forKey: key) } }
}

private final class DeletionWire: @unchecked Sendable {
    static let shared = DeletionWire()
    struct State {
        var unmigrated = false
        var requests: [(method: String, path: String, authorization: String?, apikey: String?, body: Data)] = []
    }
    private let lock = NSLock()
    private var states: [String: State] = [:]
    func change<T>(_ host: String, _ work: (inout State) -> T) -> T {
        lock.withLock {
            var state = states[host] ?? State()
            defer { states[host] = state }
            return work(&state)
        }
    }
    func remove(_ host: String) { lock.withLock { _ = states.removeValue(forKey: host) } }
}

private final class DeletionWireProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let url = request.url!
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while case let count = stream.read(&buffer, maxLength: buffer.count), count > 0 { body.append(contentsOf: buffer.prefix(count)) }
        }
        let (status, payload): (Int, Any) = DeletionWire.shared.change(url.host!) { state in
            state.requests.append((request.httpMethod ?? "", url.path, request.value(forHTTPHeaderField: "Authorization"),
                                   request.value(forHTTPHeaderField: "apikey"), body))
            if url.path == "/auth/v1/token" {
                return (200, [
                    "access_token": "synthetic-deletion-token", "refresh_token": "synthetic-refresh",
                    "token_type": "bearer", "expires_in": 3600, "expires_at": Date().timeIntervalSince1970 + 3600,
                    "user": ["id": "11111111-1111-4111-8111-111111111111", "aud": "authenticated",
                             "role": "authenticated", "email": "fixture@example.invalid", "app_metadata": [:],
                             "user_metadata": [:], "created_at": "2026-10-08T00:00:00Z",
                             "updated_at": "2026-10-08T00:00:00Z", "is_anonymous": false]
                ] as [String: Any])
            }
            if url.path == "/rest/v1/rpc/delete_own_account", state.unmigrated {
                return (404, ["code": "PGRST202", "details": NSNull(), "hint": NSNull(),
                              "message": "Could not find the function public.delete_own_account without parameters in the schema cache"])
            }
            if url.path == "/rest/v1/rpc/delete_own_account" { return (200, NSNull()) }
            if url.path == "/auth/v1/logout" { return (404, ["code": "user_not_found", "msg": "User from sub claim in JWT does not exist"]) }
            return (500, ["message": "Unexpected fixture request"])
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: payload, options: .fragmentsAllowed))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor private func deletionClient(host: String) -> SupabaseClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DeletionWireProtocol.self]
    return SupabaseClient(supabaseURL: URL(string: "https://\(host)")!, supabaseKey: "sb_publishable_synthetic_only",
                          options: .init(auth: .init(storage: MemoryOnlyAuth(), autoRefreshToken: false),
                                         global: .init(session: URLSession(configuration: configuration))))
}

@Test @MainActor func sdkDeletionCallsTheOwnAccountFunctionWithTheSessionAndPublishableKey() async throws {
    let host = "\(UUID().uuidString.lowercased()).invalid"
    defer { DeletionWire.shared.remove(host) }
    let client = deletionClient(host: host)
    let auth = AuthModel(client: client)
    auth.email = "fixture@example.invalid"
    auth.password = "synthetic-only"
    await auth.signIn()
    let owner = try #require(auth.ownerID)

    // The wrong account is refused before any request.
    let deletion = SupabaseAccountDeletion(client: client)
    await #expect(throws: AccountDeletionError.wrongAccount) { try await deletion.deleteAccount(ownerID: UUID()) }
    #expect(DeletionWire.shared.change(host) { $0.requests.filter { $0.path.hasPrefix("/rest/") }.isEmpty })

    // Unmigrated server: nothing is deleted or signed out.
    DeletionWire.shared.change(host) { $0.unmigrated = true }
    var removed: [UUID] = []
    #expect(!(await auth.deleteAccount(removingLocalData: { removed.append($0) })))
    #expect(auth.errorMessage == "Your account was not deleted and nothing was removed. "
        + AccountDeletionError.serverNeedsUpdate.localizedDescription)
    #expect(auth.ownerID == owner && removed.isEmpty)
    #expect(try await client.auth.session.user.id == owner)

    DeletionWire.shared.change(host) { $0.unmigrated = false }
    #expect(await auth.deleteAccount(removingLocalData: { removed.append($0) }))
    #expect(removed == [owner])
    #expect(auth.ownerID == nil)
    // The saved session is gone even though the server no longer knows the user.
    #expect(client.auth.currentSession == nil)
    let calls = DeletionWire.shared.change(host) { $0.requests.filter { $0.path == "/rest/v1/rpc/delete_own_account" } }
    #expect(calls.count == 2)
    for call in calls {
        #expect(call.method == "POST")
        #expect(call.authorization == "Bearer synthetic-deletion-token")
        #expect(call.apikey == "sb_publishable_synthetic_only")
        // No argument names an account: the server deletes only the token's own user.
        let arguments = try JSONSerialization.jsonObject(with: call.body.isEmpty ? Data("{}".utf8) : call.body, options: .fragmentsAllowed)
        #expect((arguments as? [String: Any])?.isEmpty == true)
    }
}
