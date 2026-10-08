import ChallengeCore
import Foundation
import Supabase
import Testing
@testable import DailyChallengeProof

private final class MemoryOnlyAuth: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { lock.withLock { _ = values.removeValue(forKey: key) } }
}

private final class WireFixture: @unchecked Sendable {
    static let shared = WireFixture()
    let lock = NSLock()
    struct State {
        var header: [String: Any]?
        var events: [[String: Any]] = []
        var restCalls = 0
        var refreshCalls = 0
        var expireSession = false
        var invalidWire = false
        var pageSizes: [Int] = []
        /// A server the owner has not yet given the timezone migration.
        var unmigrated = false
        var challengeSelects: [String] = []
        /// Event IDs stored as rows this app can't read, like rows written before the server checks.
        var unreadableIDs: Set<String> = []
    }
    private var states: [String: State] = [:]
    func change<T>(_ host: String, _ work: (inout State) throws -> T) rethrows -> T {
        try lock.withLock {
            var state = states[host] ?? State()
            defer { states[host] = state }
            return try work(&state)
        }
    }
    func remove(_ host: String) { lock.withLock { _ = states.removeValue(forKey: host) } }
}

private final class ChallengeWireProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        do {
            let url = request.url!
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 2048)
                while true {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count < 0 { throw URLError(.cannotDecodeRawData) }
                    if count == 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            let (status, payload): (Int, Any) = try WireFixture.shared.change(url.host!) { state in
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []
                if url.path == "/auth/v1/token" {
                    if query.contains(URLQueryItem(name: "grant_type", value: "refresh_token")) {
                        state.refreshCalls += 1
                        return (400, ["code": "refresh_token_not_found", "msg": "Synthetic expired session"])
                    }
                    return (200, [
                        "access_token": "synthetic-production-sync-token", "refresh_token": "synthetic-refresh",
                        "token_type": "bearer", "expires_in": state.expireSession ? -60 : 3600,
                        "expires_at": Date().timeIntervalSince1970 + (state.expireSession ? -60 : 3600),
                        "user": ["id": "11111111-1111-4111-8111-111111111111", "aud": "authenticated",
                                 "role": "authenticated", "email": "fixture@example.invalid", "app_metadata": [:],
                                 "user_metadata": [:], "created_at": "2026-10-08T00:00:00Z",
                                 "updated_at": "2026-10-08T00:00:00Z", "is_anonymous": false]
                    ] as [String: Any])
                }
                state.restCalls += 1
                if request.value(forHTTPHeaderField: "Authorization") != "Bearer synthetic-production-sync-token" {
                    state.invalidWire = true
                }
                if request.httpMethod == "POST" {
                    if request.value(forHTTPHeaderField: "Prefer")?.contains("resolution=ignore-duplicates") != true {
                        state.invalidWire = true
                    }
                    let json = try JSONSerialization.jsonObject(with: body)
                    if url.path == "/rest/v1/challenges", state.unmigrated,
                       (json as? [String: Any])?["time_zone"] != nil {
                        return (400, ["code": "PGRST204", "details": NSNull(), "hint": NSNull(),
                                      "message": "Could not find the 'time_zone' column of 'challenges' in the schema cache"])
                    }
                    if url.path == "/rest/v1/challenges" {
                        state.header = state.header ?? (json as? [String: Any])
                    } else if url.path == "/rest/v1/challenge_events", let events = json as? [[String: Any]] {
                        for var event in events {
                            if event["received_at"] != nil { state.invalidWire = true }
                            guard let activity = event["activity"] as? [String: Any], activity["recordedAt"] is NSNumber,
                                  event["owner_id"] as? String == "11111111-1111-4111-8111-111111111111" else {
                                state.invalidWire = true; continue
                            }
                            if !state.events.contains(where: { $0["id"] as? String == event["id"] as? String }) {
                                event["received_at"] = "2026-10-08T12:00:00+00:00"
                                if let id = event["id"] as? String, state.unreadableIDs.contains(id.lowercased()) {
                                    event["activity"] = ["shape": "from a future client"]
                                }
                                state.events.append(event)
                            }
                        }
                    } else { state.invalidWire = true }
                    return (201, [:])
                }
                if !query.contains(URLQueryItem(name: "owner_id", value: "eq.11111111-1111-4111-8111-111111111111")) {
                    state.invalidWire = true
                }
                if url.path == "/rest/v1/challenges" {
                    state.challengeSelects.append(query.first(where: { $0.name == "select" })?.value ?? "")
                    var header = state.header
                    if state.unmigrated { header?.removeValue(forKey: "time_zone") }
                    return (200, header.map { [$0] } ?? [])
                }
                if url.path == "/rest/v1/challenge_events" {
                    let offset = Int(query.first(where: { $0.name == "offset" })?.value ?? "0") ?? 0
                    let limit = Int(query.first(where: { $0.name == "limit" })?.value ?? "500") ?? 500
                    let sorted = state.events.sorted { ($0["id"] as! String) < ($1["id"] as! String) }
                    let page = Array(sorted.dropFirst(offset).prefix(limit))
                    state.pageSizes.append(page.count)
                    return (200, page)
                }
                state.invalidWire = true
                return (404, ["message": "Unexpected fixture request"])
            }
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: payload))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
}

@MainActor private func wireClient(host: String) -> SupabaseClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ChallengeWireProtocol.self]
    return SupabaseClient(supabaseURL: URL(string: "https://\(host)")!, supabaseKey: "sb_publishable_synthetic_only",
                          options: .init(auth: .init(storage: MemoryOnlyAuth(), autoRefreshToken: false),
                                         global: .init(session: URLSession(configuration: configuration))))
}

@Test @MainActor func sdkProductionTransportUsesAuthenticatedImmutableBatchesAndPagination() async throws {
    let host = "\(UUID().uuidString.lowercased()).invalid"
    defer { WireFixture.shared.remove(host) }
    let client = wireClient(host: host)
    let session = try await client.auth.signIn(email: "fixture@example.invalid", password: "synthetic-only")
    let transport = SupabaseChallengeTransport(client: client)
    let now = Date(timeIntervalSince1970: 1_791_460_800.123456)
    let challenge = Challenge(ownerID: session.user.id, startDate: now)
    let header = ChallengeRecord(ownerID: session.user.id, startDate: challenge.startDate)
    try await transport.insertChallenge(header)
    #expect(try await transport.fetchChallenge(ownerID: session.user.id) == header)
    let events = (0..<501).map { index in
        ChallengeEvent(ownerID: session.user.id, challengeID: header.id,
                       activity: .init(id: UUID(), day: challenge.startDate, recordedAt: now.addingTimeInterval(Double(index)),
                                       action: .pour(450), undonePourID: nil, deviceID: "fixture"))
    }
    try await transport.upload(events, ownerID: session.user.id)
    try await transport.upload(events, ownerID: session.user.id)
    let fetched = try await transport.fetchEvents(ownerID: session.user.id, challengeID: header.id)
    let remote = fetched.events
    #expect(fetched.skipped == 0)
    #expect(remote.count == 501)
    #expect(Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0.activity) }) == Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0.activity) }))
    WireFixture.shared.change(host) { state in
        #expect(!state.invalidWire)
        #expect(state.pageSizes == [500, 1])
    }
    let before = WireFixture.shared.change(host) { $0.restCalls }
    do {
        _ = try await transport.fetchChallenge(ownerID: UUID())
        Issue.record("Wrong-account request was accepted")
    } catch {}
    #expect(WireFixture.shared.change(host) { $0.restCalls } == before)
}

@Test @MainActor func expiredSDKSessionPreservesDurableProductionQueueWithoutSendingWrites() async throws {
    let host = "\(UUID().uuidString.lowercased()).invalid"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { WireFixture.shared.remove(host); try? FileManager.default.removeItem(at: directory) }
    WireFixture.shared.change(host) { $0.expireSession = true }
    let client = wireClient(host: host)
    let session = try await client.auth.signIn(email: "fixture@example.invalid", password: "synthetic-only")
    let now = Date(timeIntervalSince1970: 1_791_460_800)
    var store = try ChallengeStore(ownerID: session.user.id, directory: directory)
    try store.start(on: now); try store.record(.pour(900), on: now, at: now)
    let model = TrackerModel(directory: directory, clock: { now })
    model.configureSync(SupabaseChallengeTransport(client: client))
    model.activate(ownerID: session.user.id)
    await model.sync(force: true)
    #expect(model.syncError != nil)
    #expect(model.store?.pendingCount == 2)
    #expect(try ChallengeStore(ownerID: session.user.id, directory: directory).pendingCount == 2)
    WireFixture.shared.change(host) { state in
        #expect(state.refreshCalls > 0)
        #expect(state.restCalls == 0)
    }
}

@Test @MainActor func sdkTransportWritesTheZoneAndReadsAnUnmigratedServerAsJersey() async throws {
    let host = "\(UUID().uuidString.lowercased()).invalid"
    defer { WireFixture.shared.remove(host) }
    let client = wireClient(host: host)
    let session = try await client.auth.signIn(email: "fixture@example.invalid", password: "synthetic-only")
    let transport = SupabaseChallengeTransport(client: client)
    let sydney = TimeZone(identifier: "Australia/Sydney")!
    let start = Challenge(ownerID: session.user.id, startDate: Date(timeIntervalSince1970: 1_791_460_800), timeZone: sydney).startDate
    let header = ChallengeRecord(ownerID: session.user.id, startDate: start, timeZone: sydney)
    try await transport.insertChallenge(header)
    #expect(try await transport.fetchChallenge(ownerID: session.user.id) == header)
    WireFixture.shared.change(host) { state in
        #expect(state.header?["time_zone"] as? String == "Australia/Sydney")
        #expect(state.challengeSelects == ["*"])
        // The same row read back from a server without the column.
        state.unmigrated = true
    }
    let unmigrated = try #require(try await transport.fetchChallenge(ownerID: session.user.id))
    #expect(unmigrated.timeZone == "Europe/Jersey")
    #expect(unmigrated.id == header.id && unmigrated.startTime == header.startTime)
    WireFixture.shared.change(host) { #expect(!$0.invalidWire) }
}

/// A friend's Mac installs the timezone build before the owner applies the
/// migration: the insert is refused with a clear message and nothing local changes.
@Test @MainActor func unmigratedServerRefusesSettingsWithAClearErrorAndKeepsLocalHistory() async throws {
    let host = "\(UUID().uuidString.lowercased()).invalid"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { WireFixture.shared.remove(host); try? FileManager.default.removeItem(at: directory) }
    WireFixture.shared.change(host) { $0.unmigrated = true }
    let client = wireClient(host: host)
    let session = try await client.auth.signIn(email: "fixture@example.invalid", password: "synthetic-only")
    let now = Date(timeIntervalSince1970: 1_791_460_800)
    var store = try ChallengeStore(ownerID: session.user.id, directory: directory)
    try store.start(on: now, timeZone: TimeZone(identifier: "America/New_York")!)
    try store.record(.pour(900), on: now, at: now)
    let file = directory.appendingPathComponent("challenge-\(session.user.id.uuidString.lowercased()).json")
    let before = try Data(contentsOf: file)
    let transport = SupabaseChallengeTransport(client: client)
    do {
        try await transport.insertChallenge(try #require(store.record))
        Issue.record("An unmigrated server accepted the timezone")
    } catch let error as ChallengeSyncError {
        #expect(error == .serverNeedsTimeZoneUpdate)
    }
    let model = TrackerModel(directory: directory, clock: { now })
    model.configureSync(transport)
    model.activate(ownerID: session.user.id)
    await model.sync(force: true)
    #expect(model.syncError == ChallengeSyncError.serverNeedsTimeZoneUpdate.errorDescription)
    #expect(model.syncError?.contains("docs/production-sync.md") == true)
    #expect(model.summary?.waterMillilitres == 900)
    #expect(model.store?.pendingCount == 2)
    #expect(try Data(contentsOf: file) == before)
    WireFixture.shared.change(host) { state in
        #expect(state.header == nil && state.events.isEmpty)
        #expect(!state.invalidWire)
    }
}

/// One good and one unreadable row on the same page: the good row syncs and is
/// acknowledged, the bad one is skipped and reported, and its local copy stays pending.
@Test @MainActor func unreadableServerRowIsSkippedAndNeverAcknowledged() async throws {
    let host = "\(UUID().uuidString.lowercased()).invalid"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { WireFixture.shared.remove(host); try? FileManager.default.removeItem(at: directory) }
    let client = wireClient(host: host)
    let session = try await client.auth.signIn(email: "fixture@example.invalid", password: "synthetic-only")
    let now = Date(timeIntervalSince1970: 1_791_460_800)
    var store = try ChallengeStore(ownerID: session.user.id, directory: directory)
    try store.start(on: now, timeZone: TimeZone(identifier: "Europe/Jersey")!)
    try store.record(.pour(900), on: now, at: now)
    try store.record(.pour(450), on: now, at: now.addingTimeInterval(60))
    let pours = store.pending
    #expect(pours.count == 2)
    let good = pours[0], bad = pours[1]
    WireFixture.shared.change(host) { $0.unreadableIDs = [bad.id.uuidString.lowercased()] }

    let transport = SupabaseChallengeTransport(client: client)
    let model = TrackerModel(directory: directory, clock: { now })
    model.configureSync(transport)
    model.activate(ownerID: session.user.id)
    await model.sync(force: true)

    #expect(model.syncError == nil)
    #expect(model.skippedRows == 1)
    // The skipped row's local copy is still waiting, and the status says why.
    #expect(model.syncStatus == "Saved locally · 1 pending · 1 entry from the server could not be read and was skipped")
    #expect(model.skippedNotice == "1 entry from the server could not be read and was skipped")
    #expect(skippedRowsNotice(0) == nil)
    #expect(skippedRowsNotice(3) == "3 entries from the server could not be read and were skipped")
    #expect(model.store?.pending.map(\.id) == [bad.id])
    #expect(try ChallengeStore(ownerID: session.user.id, directory: directory).pending.map(\.id) == [bad.id])

    let remote = try await transport.fetchEvents(ownerID: session.user.id, challengeID: try #require(store.record).id)
    #expect(remote.events.map(\.id) == [good.id])
    #expect(remote.skipped == 1)
    WireFixture.shared.change(host) { state in
        #expect(state.events.count == 2)
        #expect(state.pageSizes == [2, 2])
        #expect(!state.invalidWire)
    }
}
