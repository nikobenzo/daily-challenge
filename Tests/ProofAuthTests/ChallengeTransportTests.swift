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
                                state.events.append(event)
                            }
                        }
                    } else { state.invalidWire = true }
                    return (201, [:])
                }
                if !query.contains(URLQueryItem(name: "owner_id", value: "eq.11111111-1111-4111-8111-111111111111")) {
                    state.invalidWire = true
                }
                if url.path == "/rest/v1/challenges" { return (200, state.header.map { [$0] } ?? []) }
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
    let remote = try await transport.fetchEvents(ownerID: session.user.id, challengeID: header.id)
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
