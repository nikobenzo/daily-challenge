import Foundation
import Supabase
import Testing
@testable import ChallengeSyncKit

/// Holds the session in memory so `update(user:)` can find it. Never touches Keychain.
private final class InMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
}

/// Every request the synthetic Auth server received, keyed by the per-test host so
/// parallel tests never share state.
private final class AuthRequestLog: @unchecked Sendable {
    static let shared = AuthRequestLog()
    private let lock = NSLock()
    private var requests: [String: [(path: String, body: [String: Any])]] = [:]

    func record(host: String, path: String, body: [String: Any]) {
        lock.withLock { requests[host, default: []].append((path, body)) }
    }

    func entries(host: String) -> [(path: String, body: [String: Any])] {
        lock.withLock { requests[host] ?? [] }
    }
}

private let newAccountID = "22222222-2222-4222-8222-222222222222"
private let validCode = "123456"
/// Supabase's "Email OTP length" allows 6 to 10 digits; the app must take any of them.
private let validCodes = [validCode, "12345678", "1234567890"]
private let staleCode = "999999"

private func userJSON(email: String, confirmed: Bool, identities: Bool = true) -> [String: Any] {
    var user: [String: Any] = [
        "id": newAccountID,
        "aud": "authenticated",
        "role": "authenticated",
        "email": email,
        "app_metadata": ["provider": "email"],
        "user_metadata": [:],
        "created_at": "2026-10-08T00:00:00Z",
        "updated_at": "2026-10-08T00:00:00Z",
        "is_anonymous": false,
        "identities": identities ? [[
            "id": newAccountID,
            "identity_id": "33333333-3333-4333-8333-333333333333",
            "user_id": newAccountID,
            "identity_data": ["email": email, "sub": newAccountID],
            "provider": "email",
            "created_at": "2026-10-08T00:00:00Z",
            "last_sign_in_at": "2026-10-08T00:00:00Z",
            "updated_at": "2026-10-08T00:00:00Z"
        ]] : []
    ]
    if confirmed { user["email_confirmed_at"] = "2026-10-08T00:00:00Z" }
    return user
}

private func sessionJSON(email: String) -> [String: Any] {
    [
        "access_token": "synthetic-test-token",
        "refresh_token": "synthetic-refresh-token",
        "token_type": "bearer",
        "expires_in": 3600,
        "expires_at": Date().timeIntervalSince1970 + 3600,
        "user": userJSON(email: email, confirmed: true)
    ]
}

private func apiError(_ status: Int, _ code: String, _ message: String) -> (Int, [String: Any]) {
    (status, ["code": code, "message": message])
}

/// A stateless synthetic GoTrue: answers by request content, so each case also checks
/// the wire format the SDK sent. No network, real credentials, or email sends.
private final class SignUpAuthProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while true {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count < 0 { throw URLError(.cannotDecodeRawData) }
                    if count == 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            let body = (data.isEmpty ? nil : try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let path = request.url!.path
            AuthRequestLog.shared.record(host: request.url!.host!, path: path, body: body)
            let (status, payload) = Self.respond(method: request.httpMethod ?? "", path: path, body: body, request: request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json", "X-Supabase-Api-Version": "2024-01-01"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: payload))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private static func respond(method: String, path: String, body: [String: Any], request: URLRequest) -> (Int, [String: Any]) {
        let email = body["email"] as? String
        switch (method, path) {
        case ("POST", "/auth/v1/signup"):
            guard body["password"] as? String == "fresh secret 7" else {
                return apiError(422, "weak_password", "Password should be at least 6 characters.")
            }
            switch email {
            case "new@example.com": return (200, userJSON(email: "new@example.com", confirmed: false))
            case "taken@example.com": return (200, userJSON(email: "taken@example.com", confirmed: false, identities: false))
            case "instant@example.com": return (200, sessionJSON(email: "instant@example.com"))
            case "exists@example.com": return apiError(422, "user_already_exists", "User already registered")
            default: return apiError(400, "validation_failed", "Unable to validate email address")
            }
        case ("POST", "/auth/v1/token"):
            if email == "pending@example.com" { return apiError(400, "email_not_confirmed", "Email not confirmed") }
            return apiError(400, "invalid_credentials", "Invalid login credentials")
        case ("POST", "/auth/v1/verify"):
            guard let type = body["type"] as? String, ["signup", "recovery"].contains(type),
                  let email, let token = body["token"] as? String, validCodes.contains(token) else {
                return apiError(403, "otp_expired", "Token has expired or is invalid")
            }
            return (200, sessionJSON(email: email))
        case ("POST", "/auth/v1/logout"):
            return (204, [:])
        case ("POST", "/auth/v1/resend"):
            guard body["type"] as? String == "signup", email != nil else {
                return apiError(400, "validation_failed", "Missing type")
            }
            return (200, [:])
        case ("POST", "/auth/v1/recover"):
            if email == "busy@example.com" {
                return apiError(429, "over_email_send_rate_limit", "For security purposes, you can only request this after 42 seconds.")
            }
            return (200, [:])
        case ("PUT", "/auth/v1/user"):
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-test-token" else {
                return apiError(401, "no_authorization", "This endpoint requires a valid Bearer token")
            }
            switch body["password"] as? String {
            case "brand new secret 9": return (200, userJSON(email: "new@example.com", confirmed: true))
            case "slow secret 123":
                // Stands in for the person closing the app or the screen mid-save.
                RecoveryInterruption.shared.interrupt(host: request.url!.host!)
                return apiError(500, "unexpected_failure", "Interrupted")
            case "same secret 42": return apiError(422, "same_password", "New password should be different from the old password.")
            default: return apiError(422, "weak_password", "Password is known to be weak and easy to guess.")
            }
        default:
            return apiError(404, "not_found", "Unexpected synthetic request \(method) \(path)")
        }
    }
}

private final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_791_500_000)
}

/// Cancels the task running a password reset when the synthetic server is asked to save it.
private final class RecoveryInterruption: @unchecked Sendable {
    static let shared = RecoveryInterruption()
    private let lock = NSLock()
    private var tasks: [String: Task<Void, Never>] = [:]
    func register(host: String, _ task: Task<Void, Never>) { lock.withLock { tasks[host] = task } }
    func interrupt(host: String) { lock.withLock { tasks[host] }?.cancel() }
}

private struct Harness {
    let model: AuthModel
    let client: SupabaseClient
    let host: String
    let clock: TestClock
    let directory: URL

    var requests: [(path: String, body: [String: Any])] { AuthRequestLog.shared.entries(host: host) }
    func requests(to path: String) -> [[String: Any]] { requests.filter { $0.path == path }.map(\.body) }
}

@MainActor
private func makeHarness() -> Harness {
    let host = "\(UUID().uuidString.lowercased()).auth-test.invalid"
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SignUpAuthProtocol.self]
    let client = SupabaseClient(
        supabaseURL: URL(string: "https://\(host)")!,
        supabaseKey: "sb_publishable_synthetic_test_only",
        options: .init(
            auth: .init(storage: InMemoryAuthStorage(), autoRefreshToken: false),
            global: .init(session: URLSession(configuration: configuration))
        )
    )
    let clock = TestClock()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return Harness(
        model: AuthModel(client: client, now: { clock.now }),
        client: client, host: host, clock: clock, directory: directory
    )
}

@MainActor
private func expectSecretsCleared(_ model: AuthModel) {
    #expect(model.password.isEmpty)
    #expect(model.passwordConfirmation.isEmpty)
    #expect(model.newPassword.isEmpty)
    #expect(!model.isBusy)
}

@Test @MainActor func signUpWithoutSessionAsksForCodeInsteadOfFailing() async {
    let h = makeHarness()
    defer { try? FileManager.default.removeItem(at: h.directory) }
    h.model.show(.createAccount)
    h.model.email = " new@example.com "
    h.model.password = "fresh secret 7"
    h.model.passwordConfirmation = "fresh secret 7"
    await h.model.signUp(email: h.model.email, password: h.model.password)

    #expect(h.model.authStep == .confirmSignUp(email: "new@example.com"))
    #expect(h.model.ownerID == nil)
    #expect(h.model.errorMessage == nil)
    #expect(h.model.notice?.contains("new@example.com") == true)
    expectSecretsCleared(h.model)
    let sent = h.requests(to: "/auth/v1/signup")
    #expect(sent.count == 1)
    #expect(sent.first?["email"] as? String == "new@example.com")
    #expect(h.model.resendWait(at: h.clock.now) == 60)
}

@Test @MainActor func signUpCodeConfirmsAndSignsIn() async {
    let h = makeHarness()
    defer { try? FileManager.default.removeItem(at: h.directory) }
    await h.model.signUp(email: "new@example.com", password: "fresh secret 7")
    h.model.code = validCode
    await h.model.confirmSignUp(code: " 123 456 ")

    #expect(h.model.ownerID == UUID(uuidString: newAccountID))
    #expect(h.model.signedInEmail == "new@example.com")
    #expect(h.model.ownerID != nil)
    #expect(h.model.authStep == .signIn)
    #expect(h.model.code.isEmpty)
    #expect(h.model.errorMessage == nil)
    let verify = h.requests(to: "/auth/v1/verify")
    #expect(verify.count == 1)
    #expect(verify.first?["type"] as? String == "signup")
    #expect(verify.first?["token"] as? String == validCode)
    #expect(verify.first?["email"] as? String == "new@example.com")
}

@Test @MainActor func wrongOrExpiredCodeKeepsTheCodeStepWithPlainEnglish() async {
    let h = makeHarness()
    defer { try? FileManager.default.removeItem(at: h.directory) }
    await h.model.signUp(email: "new@example.com", password: "fresh secret 7")
    h.model.code = staleCode
    await h.model.confirmSignUp(code: staleCode)

    #expect(h.model.ownerID == nil)
    #expect(h.model.authStep == .confirmSignUp(email: "new@example.com"))
    #expect(h.model.errorMessage == "That code is wrong or has expired. Check the latest email, or request a new code.")
    #expect(h.model.code.isEmpty)
    #expect(!h.model.isBusy)

    // A malformed code is rejected locally without a request.
    await h.model.confirmSignUp(code: "12ab")
    #expect(h.model.errorMessage == "Enter the code from the email.")
    #expect(h.requests(to: "/auth/v1/verify").count == 1)
}

@Test @MainActor func signUpForAnExistingAccountPointsToSignIn() async {
    for address in ["taken@example.com", "exists@example.com"] {
        let h = makeHarness()
        defer { try? FileManager.default.removeItem(at: h.directory) }
        h.model.show(.createAccount)
        h.model.password = "fresh secret 7"
        h.model.passwordConfirmation = "fresh secret 7"
        await h.model.signUp(email: address, password: "fresh secret 7")
        #expect(h.model.authStep == .signIn)
        #expect(h.model.email == address)
        #expect(h.model.ownerID == nil)
        #expect(h.model.errorMessage == "An account with this email already exists, try signing in.")
        expectSecretsCleared(h.model)
    }
}

@Test @MainActor func signUpReturningASessionSignsInDirectly() async {
    let h = makeHarness()
    defer { try? FileManager.default.removeItem(at: h.directory) }
    await h.model.signUp(email: "instant@example.com", password: "fresh secret 7")
    #expect(h.model.ownerID == UUID(uuidString: newAccountID))
    #expect(h.model.authStep == .signIn)
    #expect(h.model.errorMessage == nil)
}

@Test @MainActor func shortSignUpPasswordIsRejectedLocallyAndCleared() async {
    let h = makeHarness()
    defer { try? FileManager.default.removeItem(at: h.directory) }
    h.model.password = "abc"
    h.model.passwordConfirmation = "abc"
    await h.model.signUp(email: "new@example.com", password: "abc")
    #expect(h.model.errorMessage == "Use at least 10 characters, with at least one letter and one number.")
    #expect(h.requests.isEmpty)
    expectSecretsCleared(h.model)
}

@Test @MainActor func serverRejectedSignUpClearsPasswordsAndExplains() async {
    let h = makeHarness()
    defer { try? FileManager.default.removeItem(at: h.directory) }
    h.model.password = "guessable 12"
    h.model.passwordConfirmation = "guessable 12"
    await h.model.signUp(email: "new@example.com", password: "guessable 12")
    #expect(h.model.authStep == .signIn)
    #expect(h.model.ownerID == nil)
    #expect(h.model.errorMessage?.hasPrefix("Choose a stronger password.") == true)
    #expect(h.model.status == "Account not created")
    expectSecretsCleared(h.model)
}

@Test @MainActor func resendRespectsTheSixtySecondLimit() async {
    let h = makeHarness()
    defer { try? FileManager.default.removeItem(at: h.directory) }
    await h.model.signUp(email: "new@example.com", password: "fresh secret 7")
    #expect(!h.model.canResend)
    await h.model.resendCode()
    #expect(h.requests(to: "/auth/v1/resend").isEmpty)

    h.clock.now += 59.5
    #expect(h.model.resendWait(at: h.clock.now) == 1)
    h.clock.now += 0.5
    #expect(h.model.canResend)
    await h.model.resendCode()
    let resent = h.requests(to: "/auth/v1/resend")
    #expect(resent.count == 1)
    #expect(resent.first?["type"] as? String == "signup")
    #expect(resent.first?["email"] as? String == "new@example.com")
    #expect(h.model.resendWait(at: h.clock.now) == 60)
    #expect(h.model.errorMessage == nil)
}

@Test @MainActor func passwordRecoveryVerifiesCodeThenSavesNewPassword() async {
    let h = makeHarness()
    defer { try? FileManager.default.removeItem(at: h.directory) }
    h.model.show(.forgotPassword)
    await h.model.requestPasswordReset(email: " new@example.com ")
    #expect(h.model.authStep == .resetPassword(email: "new@example.com"))
    #expect(h.requests(to: "/auth/v1/recover").first?["email"] as? String == "new@example.com")
    #expect(h.model.resendWait(at: h.clock.now) == 60)

    h.model.code = validCode
    h.model.newPassword = "brand new secret 9"
    h.model.passwordConfirmation = "brand new secret 9"
    await h.model.completePasswordReset(code: validCode, newPassword: "brand new secret 9")

    #expect(h.model.ownerID == UUID(uuidString: newAccountID))
    #expect(h.model.authStep == .signIn)
    #expect(h.model.errorMessage == nil)
    #expect(h.model.status == "Password updated. You're signed in.")
    #expect(h.requests(to: "/auth/v1/verify").first?["type"] as? String == "recovery")
    #expect(h.requests(to: "/auth/v1/user").first?["password"] as? String == "brand new secret 9")
    expectSecretsCleared(h.model)
    #expect(h.model.code.isEmpty)
}

@Test @MainActor func expiredRecoveryCodeNeverSendsThePassword() async {
    let h = makeHarness()
    defer { try? FileManager.default.removeItem(at: h.directory) }
    await h.model.requestPasswordReset(email: "new@example.com")
    h.model.newPassword = "brand new secret 9"
    h.model.passwordConfirmation = "brand new secret 9"
    await h.model.completePasswordReset(code: staleCode, newPassword: "brand new secret 9")

    #expect(h.model.ownerID == nil)
    #expect(h.model.authStep == .resetPassword(email: "new@example.com"))
    #expect(h.model.errorMessage == "That code is wrong or has expired. Check the latest email, or request a new code.")
    #expect(h.requests(to: "/auth/v1/user").isEmpty)
    expectSecretsCleared(h.model)
}

@Test @MainActor func resetRequestRateLimitIsExplainedAndStartsTheWait() async {
    let h = makeHarness()
    defer { try? FileManager.default.removeItem(at: h.directory) }
    await h.model.requestPasswordReset(email: "busy@example.com")
    #expect(h.model.authStep == .signIn)
    #expect(h.model.errorMessage == "Too many emails were requested. Wait a minute, then try again.")
    #expect(h.model.resendWait(at: h.clock.now) == 60)
}

@Test @MainActor func recoveryResendUsesTheRecoverEndpoint() async {
    let h = makeHarness()
    defer { try? FileManager.default.removeItem(at: h.directory) }
    await h.model.requestPasswordReset(email: "new@example.com")
    h.clock.now += 61
    await h.model.resendCode()
    #expect(h.requests(to: "/auth/v1/recover").count == 2)
    #expect(h.requests(to: "/auth/v1/resend").isEmpty)
}

@Test @MainActor func changePasswordNeedsASessionAndReportsTheResult() async {
    let h = makeHarness()
    defer { try? FileManager.default.removeItem(at: h.directory) }
    h.model.newPassword = "brand new secret 9"
    #expect(await h.model.changePassword(new: "brand new secret 9") == false)
    #expect(h.model.errorMessage == "Sign in before changing your password.")
    #expect(h.requests(to: "/auth/v1/user").isEmpty)
    expectSecretsCleared(h.model)

    await h.model.signUp(email: "new@example.com", password: "fresh secret 7")
    await h.model.confirmSignUp(code: validCode)
    #expect(h.model.ownerID != nil)

    h.model.newPassword = "same secret 42"
    #expect(await h.model.changePassword(new: "same secret 42") == false)
    #expect(h.model.errorMessage == "That is already your password. Choose a different one.")
    expectSecretsCleared(h.model)

    h.model.newPassword = "brand new secret 9"
    h.model.passwordConfirmation = "brand new secret 9"
    #expect(await h.model.changePassword(new: "brand new secret 9"))
    #expect(h.model.errorMessage == nil)
    #expect(h.model.status == "Password changed. Use it next time you sign in.")
    #expect(h.requests(to: "/auth/v1/user").last?["password"] as? String == "brand new secret 9")
    expectSecretsCleared(h.model)
    #expect(h.model.ownerID == UUID(uuidString: newAccountID))
}

@Test @MainActor func signInBeforeConfirmingOffersTheCodeStep() async {
    let h = makeHarness()
    defer { try? FileManager.default.removeItem(at: h.directory) }
    h.model.email = "pending@example.com"
    h.model.password = "fresh secret 7"
    await h.model.signIn()
    #expect(h.model.ownerID == nil)
    #expect(h.model.authStep == .confirmSignUp(email: "pending@example.com"))
    #expect(h.model.errorMessage == nil)
    #expect(h.model.canResend)
    expectSecretsCleared(h.model)

    await h.model.resendCode()
    #expect(h.requests(to: "/auth/v1/resend").count == 1)
}

@Test @MainActor func wrongSignInPasswordIsExplainedPlainly() async {
    let h = makeHarness()
    defer { try? FileManager.default.removeItem(at: h.directory) }
    h.model.email = "new@example.com"
    h.model.password = "wrong"
    await h.model.signIn()
    #expect(h.model.errorMessage == "That email and password don't match an account. Try again, or use Forgot password.")
    #expect(h.model.authStep == .signIn)
    expectSecretsCleared(h.model)
}

@Test @MainActor func switchingScreensDropsTypedSecrets() {
    let h = makeHarness()
    h.model.password = "typed"
    h.model.passwordConfirmation = "typed"
    h.model.newPassword = "typed"
    h.model.code = "123"
    h.model.email = "keep@example.com"
    h.model.show(.forgotPassword)
    expectSecretsCleared(h.model)
    #expect(h.model.code.isEmpty)
    #expect(h.model.email == "keep@example.com")
    #expect(h.model.authStep == .forgotPassword)
}

@Test @MainActor func everyCodeLengthSupabaseCanSendIsAccepted() async {
    for code in validCodes {
        let h = makeHarness()
        defer { try? FileManager.default.removeItem(at: h.directory) }
        await h.model.signUp(email: "new@example.com", password: "fresh secret 7")
        #expect(AuthModel.isCompleteCode(code))
        await h.model.confirmSignUp(code: code)
        #expect(h.model.ownerID == UUID(uuidString: newAccountID), "\(code.count)-digit code")
        #expect(h.requests(to: "/auth/v1/verify").first?["token"] as? String == code)
    }
}

@Test @MainActor func codesOutsideSixToTenDigitsAreRejectedLocally() async {
    for code in ["12345", "12345678901", "1234567a", "１２３４５６"] {
        #expect(!AuthModel.isCompleteCode(code), "\(code)")
        let h = makeHarness()
        defer { try? FileManager.default.removeItem(at: h.directory) }
        await h.model.signUp(email: "new@example.com", password: "fresh secret 7")
        await h.model.confirmSignUp(code: code)
        #expect(h.model.errorMessage == "Enter the code from the email.")
        #expect(h.requests(to: "/auth/v1/verify").isEmpty)
    }
}

@Test @MainActor func codeCopyNamesNoFixedLength() async {
    let h = makeHarness()
    defer { try? FileManager.default.removeItem(at: h.directory) }
    await h.model.signUp(email: "new@example.com", password: "fresh secret 7")
    #expect(h.model.notice == "We emailed a code to new@example.com. Enter it to finish creating your account.")
}

@Test func newPasswordsNeedTenCharactersWithALetterAndANumber() {
    let rule = "Use at least 10 characters, with at least one letter and one number."
    #expect(AuthModel.passwordProblem("") == rule)
    #expect(AuthModel.passwordProblem("abc123") == rule)
    #expect(AuthModel.passwordProblem("abcdefghij") == rule)
    #expect(AuthModel.passwordProblem("1234567890") == rule)
    #expect(AuthModel.passwordProblem("abcdefghi1") == nil)
    // Supabase's server-side "Letters and digits" rule counts only ASCII characters.
    #expect(AuthModel.passwordProblem("ééééééééé1") == rule)
    #expect(AuthModel.passwordProblem("abcdefghi١") == rule)
    #expect(AuthModel.passwordProblem("fresh secret 7") == nil)
}

@Test @MainActor func weakNewPasswordsAreRejectedBeforeAnyRequest() async {
    let h = makeHarness()
    defer { try? FileManager.default.removeItem(at: h.directory) }
    await h.model.signUp(email: "new@example.com", password: "freshsecret")
    #expect(h.model.errorMessage == "Use at least 10 characters, with at least one letter and one number.")
    await h.model.requestPasswordReset(email: "new@example.com")
    await h.model.completePasswordReset(code: validCode, newPassword: "1234567890")
    #expect(h.model.errorMessage == "Use at least 10 characters, with at least one letter and one number.")
    #expect(h.requests(to: "/auth/v1/signup").isEmpty)
    #expect(h.requests(to: "/auth/v1/verify").isEmpty)
    expectSecretsCleared(h.model)
}

@Test @MainActor func existingShortPasswordsStillSignIn() async {
    let h = makeHarness()
    defer { try? FileManager.default.removeItem(at: h.directory) }
    h.model.email = "new@example.com"
    h.model.password = "old6ch"
    await h.model.signIn()
    // The rule applies to new passwords only: the old password reaches the server.
    #expect(h.requests(to: "/auth/v1/token").first?["password"] as? String == "old6ch")
}

@Test @MainActor func recoveryWithAnEightDigitCodeSavesThePassword() async {
    let h = makeHarness()
    defer { try? FileManager.default.removeItem(at: h.directory) }
    await h.model.requestPasswordReset(email: "new@example.com")
    await h.model.completePasswordReset(code: "12345678", newPassword: "brand new secret 9")
    #expect(h.model.ownerID == UUID(uuidString: newAccountID))
    #expect(h.model.status == "Password updated. You're signed in.")
    #expect(h.requests(to: "/auth/v1/logout").isEmpty)
}

@Test @MainActor func failedRecoveryPasswordSignsOutAndAsksToStartAgain() async {
    let h = makeHarness()
    defer { try? FileManager.default.removeItem(at: h.directory) }
    h.model.start()
    await h.model.requestPasswordReset(email: "new@example.com")
    // The synthetic server accepts the code but rejects this password as weak.
    await h.model.completePasswordReset(code: validCode, newPassword: "guessable 12")
    for _ in 0..<20 { await Task.yield() }

    #expect(h.model.ownerID == nil)
    #expect(h.model.signedInEmail == nil)
    #expect(h.client.auth.currentSession == nil)
    #expect(h.requests(to: "/auth/v1/logout").count == 1)
    #expect(h.model.authStep == .forgotPassword)
    #expect(h.model.email == "new@example.com")
    #expect(h.model.errorMessage?.hasPrefix("Your new password was not saved: Choose a stronger password.") == true)
    #expect(h.model.errorMessage?.hasSuffix("Start again to get a new code.") == true)
    expectSecretsCleared(h.model)
}

@Test @MainActor func abandonedRecoverySignsOutOnThisMac() async {
    let h = makeHarness()
    defer { try? FileManager.default.removeItem(at: h.directory) }
    h.model.start()
    await h.model.requestPasswordReset(email: "new@example.com")
    let model = h.model
    let reset = Task { await model.completePasswordReset(code: validCode, newPassword: "slow secret 123") }
    RecoveryInterruption.shared.register(host: h.host, reset)
    await reset.value
    for _ in 0..<20 { await Task.yield() }

    #expect(h.requests(to: "/auth/v1/verify").count == 1)
    #expect(h.model.ownerID == nil)
    #expect(h.client.auth.currentSession == nil)
    #expect(h.model.authStep == .forgotPassword)
    #expect(h.model.errorMessage == "The password reset was interrupted and your new password was not saved. Start again to get a new code.")
}
