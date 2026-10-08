import Foundation
import Supabase
import Testing
@testable import DailyChallengeProof

private struct EphemeralAuthStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws {}
}

/// Intercepts the actual SDK request. No network, live credentials, or email sends.
private final class PasswordAuthProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while true {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count < 0 { throw URLError(.cannotDecodeRawData) }
                    if count == 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            let credentials = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let isPasswordRequest = request.httpMethod == "POST"
                && request.url?.path == "/auth/v1/token"
                && URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?.contains(URLQueryItem(name: "grant_type", value: "password")) == true
            let matches = isPasswordRequest
                && credentials?["email"] as? String == "person@example.com"
                && credentials?["password"] as? String == "  test password  "

            let status: Int
            let payload: [String: Any]
            if matches {
                status = 200
                payload = [
                    "access_token": "synthetic-test-token",
                    "refresh_token": "synthetic-refresh-token",
                    "token_type": "bearer",
                    "expires_in": 3600,
                    "expires_at": Date().timeIntervalSince1970 + 3600,
                    "user": [
                        "id": "11111111-1111-4111-8111-111111111111",
                        "aud": "authenticated",
                        "role": "authenticated",
                        "email": "person@example.com",
                        "app_metadata": ["provider": "email"],
                        "user_metadata": [:],
                        "created_at": "2026-10-08T00:00:00Z",
                        "updated_at": "2026-10-08T00:00:00Z",
                        "email_confirmed_at": "2026-10-08T00:00:00Z",
                        "is_anonymous": false
                    ]
                ]
            } else {
                status = 400
                payload = ["code": "invalid_credentials", "msg": "Invalid login credentials"]
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: payload))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

@MainActor
private func makeModel(directory: URL) -> ProofModel {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PasswordAuthProtocol.self]
    let client = SupabaseClient(
        supabaseURL: URL(string: "https://auth-test.invalid")!,
        supabaseKey: "sb_publishable_synthetic_test_only",
        options: .init(
            auth: .init(storage: EphemeralAuthStorage(), autoRefreshToken: false),
            global: .init(session: URLSession(configuration: configuration))
        )
    )
    return ProofModel(client: client, directory: directory)
}

@Test @MainActor func passwordLoginUsesPasswordEndpointAndClearsForm() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = makeModel(directory: directory)
    model.email = " person@example.com "
    model.password = "  test password  "
    await model.signIn()
    #expect(model.ownerID == UUID(uuidString: "11111111-1111-4111-8111-111111111111"))
    #expect(model.signedInEmail == "person@example.com")
    #expect(model.journal != nil)
    #expect(model.password.isEmpty)
    #expect(!model.isBusy)
    #expect(model.errorMessage == nil)
}

@Test @MainActor func failedLoginClearsPasswordAndDoesNotActivateAccount() async {
    let model = makeModel(directory: FileManager.default.temporaryDirectory)
    model.email = "person@example.com"
    model.password = "incorrect synthetic password"
    await model.signIn()
    #expect(model.ownerID == nil)
    #expect(model.journal == nil)
    #expect(model.password.isEmpty)
    #expect(!model.isBusy)
    #expect(model.status == "Sign-in failed")
    #expect(model.errorMessage != nil)
}

@Test @MainActor func emptyPasswordIsRejectedBeforeLogin() async {
    let model = makeModel(directory: FileManager.default.temporaryDirectory)
    model.email = "person@example.com"
    await model.signIn()
    #expect(model.ownerID == nil)
    #expect(!model.isBusy)
    #expect(model.errorMessage == "Enter your app account email and password.")
}

@Test @MainActor func successfulAuthDoesNotHideCorruptLocalQueue() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("11111111-1111-4111-8111-111111111111.json")
    try Data("corrupt".utf8).write(to: file)
    let model = makeModel(directory: directory)
    model.email = "person@example.com"
    model.password = "  test password  "
    await model.signIn()
    #expect(model.ownerID != nil)
    #expect(model.journal == nil)
    #expect(model.password.isEmpty)
    #expect(model.status == "Local data could not be opened; it has not been reset")
    #expect(model.errorMessage != nil)
    #expect(try String(contentsOf: file, encoding: .utf8) == "corrupt")
}
