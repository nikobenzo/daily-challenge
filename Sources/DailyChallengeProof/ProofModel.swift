import AppKit
import Foundation
import Observation
import ProbeCore
import Supabase

private struct ProofConfiguration: Decodable {
    let supabaseURL: URL
    let publishableKey: String
}

/// Which signed-out screen is showing. Code steps carry the address the code was sent to.
enum AuthStep: Equatable {
    case signIn, createAccount, forgotPassword
    case confirmSignUp(email: String)
    case resetPassword(email: String)
}

@MainActor @Observable
final class ProofModel {
    static let resendInterval: TimeInterval = 60
    /// New passwords only: existing accounts with shorter passwords still sign in.
    nonisolated static let minimumPasswordLength = 10
    /// Every length the Supabase "Email OTP length" setting allows, so a dashboard
    /// change can never again leave people holding a code the app refuses.
    nonisolated static let codeLengths = 6...10
    nonisolated static let passwordRule = "Use at least \(minimumPasswordLength) characters, with at least one letter and one number."

    /// Nil when a new password meets the rule; otherwise the plain-English rule.
    /// Letters and digits are ASCII, as Supabase's "Letters and digits" requirement counts them.
    nonisolated static func passwordProblem(_ password: String) -> String? {
        let acceptable = password.count >= minimumPasswordLength
            && password.contains { $0.isASCII && $0.isLetter } && password.contains { $0.isASCII && $0.isNumber }
        return acceptable ? nil : passwordRule
    }

    /// Whether a typed code is all digits and a length Supabase can send.
    nonisolated static func isCompleteCode(_ code: String) -> Bool {
        codeLengths.contains(code.count) && code.allSatisfy { $0.isASCII && $0.isNumber }
    }

    var email = ""
    var password = ""
    var passwordConfirmation = ""
    var newPassword = ""
    var code = ""
    var message = ""
    var authStep = AuthStep.signIn
    var pauseSync = false
    private(set) var signedInEmail: String?
    private(set) var ownerID: UUID?
    private(set) var journal: ProbeJournal?
    private(set) var isBusy = false
    private(set) var status = "Restoring session…"
    private(set) var errorMessage: String?
    private(set) var configurationReady = false
    /// Guidance for the current sign-up or reset step, such as where a code was sent.
    private(set) var notice: String?
    private(set) var resendAvailableAt: Date?

    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var client: SupabaseClient?
    @ObservationIgnored private var started = false
    /// Set while a recovery code's session waits for its new password, so that session
    /// is never shown as signed in unless the password is saved.
    @ObservationIgnored private var holdingRecoverySession = false
    @ObservationIgnored private var lastSync: Date?
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private weak var tracker: TrackerModel?

    func attachTracker(_ tracker: TrackerModel) {
        self.tracker = tracker
        if let client { tracker.configureSync(SupabaseChallengeTransport(client: client), automatic: true) }
        tracker.activate(ownerID: ownerID)
    }

    init() {
        now = Date.init
        directory = URL.applicationSupportDirectory
            .appendingPathComponent("DailyChallengeProof", isDirectory: true)
            .appendingPathComponent("ujyvvyrugenknhjodfhc", isDirectory: true)
        do {
            guard let url = Bundle.main.url(forResource: "Configuration", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let configuration = try JSONDecoder().decode(
                ProofConfiguration.self, from: Data(contentsOf: url)
            )
            guard configuration.supabaseURL.scheme == "https",
                  configuration.publishableKey.hasPrefix("sb_publishable_") else {
                throw CocoaError(.fileReadCorruptFile)
            }
            client = SupabaseClient(
                supabaseURL: configuration.supabaseURL,
                supabaseKey: configuration.publishableKey,
                options: .init(auth: .init(
                    storage: KeychainLocalStorage(service: "app.daily-challenge.proof.auth"),
                    storageKey: "daily-challenge-proof-ujyvvyrugenknhjodfhc",
                    emitLocalSessionAsInitialSession: true
                ))
            )
            configurationReady = true
        } catch {
            status = "Configuration unavailable"
            errorMessage = "Build the .app using scripts/build-proof.sh. Configuration could not be loaded."
        }
    }

    /// Offline UI fixtures: no SDK client, Keychain, network, or production paths.
    init(
        fixtureOwnerID: UUID?, directory: URL, authStep: AuthStep = .signIn,
        notice: String? = nil, errorMessage: String? = nil, resendAvailableAt: Date? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.now = now
        self.directory = directory
        self.authStep = authStep
        self.notice = notice
        self.errorMessage = errorMessage
        self.resendAvailableAt = resendAvailableAt
        self.ownerID = fixtureOwnerID
        self.signedInEmail = fixtureOwnerID == nil ? nil : "fixture@example.invalid"
        self.configurationReady = true
        self.status = "Offline appearance fixture"
    }

    /// Allows tests to exercise the real SDK login path without a real account or Keychain.
    init(client: SupabaseClient, directory: URL, now: @escaping () -> Date = Date.init) {
        self.now = now
        self.client = client
        self.directory = directory
        self.configurationReady = true
        self.status = "Sign in to test private sync"
    }

    var entries: [ProbeEntry] { journal?.entries.reversed() ?? [] }
    var pendingCount: Int { journal?.pending.count ?? 0 }
    var lastSyncLabel: String {
        lastSync.map { "Last checked \($0.formatted(date: .omitted, time: .shortened))" }
            ?? "Not checked yet"
    }
    func isPending(_ id: UUID) -> Bool { journal?.isPending(id) ?? false }

    func start() {
        guard !started, let client else { return }
        started = true
        Task {
            for await (_, session) in client.auth.authStateChanges {
                if holdingRecoverySession { continue }
                activate(session)
            }
        }
        Task {
            // Polling also recovers updates missed while asleep. Not a production sync engine.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await sync()
            }
        }
    }

    private func activate(_ session: Session?) {
        defer { tracker?.activate(ownerID: ownerID) }
        guard let session else {
            ownerID = nil
            signedInEmail = nil
            journal = nil
            lastSync = nil
            status = "Sign in to test private sync"
            return
        }
        signedInEmail = session.user.email
        guard ownerID != session.user.id else { return }
        ownerID = session.user.id
        lastSync = nil
        do {
            journal = try ProbeJournal(ownerID: session.user.id, directory: directory)
            errorMessage = nil
            status = "Local queue ready"
        } catch {
            journal = nil
            errorMessage = error.localizedDescription
            status = "Local data could not be opened; it has not been reset"
        }
    }

    func signIn() async {
        guard !isBusy, let client else { return }
        let address = normalizedEmail(email)
        guard address.contains("@"), !password.isEmpty else {
            errorMessage = "Enter your app account email and password."
            return
        }
        beginAttempt("Signing in…")
        defer { endAttempt() }
        do {
            let session = try await client.auth.signIn(email: address, password: password)
            activate(session)
            if journal != nil {
                status = "Signed in. Use Sync now to check the server."
            }
        } catch let error as AuthError where error.errorCode == .emailNotConfirmed {
            // The account exists but its sign-up code was never entered.
            show(.confirmSignUp(email: address))
            notice = "Confirm your email to finish creating your account. Enter the code we sent to \(address), or send a new one."
            status = "Email not confirmed yet"
        } catch {
            errorMessage = describe(error)
            status = "Sign-in failed"
        }
    }

    /// Switches signed-out screens. Never carries a typed password or code across screens.
    func show(_ step: AuthStep) {
        authStep = step
        code = ""
        clearSecrets()
        notice = nil
        errorMessage = nil
        resendAvailableAt = nil
    }

    /// With Confirm email on, Supabase returns no session until the emailed code is entered.
    func signUp(email: String, password: String) async {
        guard !isBusy, let client else { return }
        let address = normalizedEmail(email)
        self.email = address
        guard address.contains("@") else {
            clearSecrets()
            errorMessage = "Enter your email address."
            return
        }
        if let problem = Self.passwordProblem(password) {
            clearSecrets()
            errorMessage = problem
            return
        }
        beginAttempt("Creating account…")
        defer { endAttempt() }
        do {
            let response = try await client.auth.signUp(email: address, password: password)
            if let session = response.session {
                activate(session)
                status = "Account created. You're signed in."
                return
            }
            // An already-confirmed address gets an obfuscated user with no identities
            // and no email, so the server does not reveal which addresses exist.
            if response.user.identities?.isEmpty == true {
                show(.signIn)
                errorMessage = Self.accountExists
                status = "Account already exists"
                return
            }
            show(.confirmSignUp(email: address))
            resendAvailableAt = now().addingTimeInterval(Self.resendInterval)
            notice = "We emailed a code to \(address). Enter it to finish creating your account."
            status = "Check your email for a code"
        } catch {
            errorMessage = describe(error)
            status = "Account not created"
            if let code = (error as? AuthError)?.errorCode, [.userAlreadyExists, .emailExists].contains(code) {
                show(.signIn)
                errorMessage = Self.accountExists
            }
        }
    }

    func confirmSignUp(code: String) async {
        guard !isBusy, let client, case .confirmSignUp(let address) = authStep else { return }
        guard let token = validCode(code) else { return }
        beginAttempt("Checking code…")
        defer { endAttempt() }
        do {
            let response = try await client.auth.verifyOTP(email: address, token: token, type: .signup)
            show(.signIn)
            if let session = response.session {
                activate(session)
                status = "Email confirmed. You're signed in."
            } else {
                email = address
                notice = "Your email is confirmed. Sign in with your password."
                status = "Email confirmed"
            }
        } catch {
            errorMessage = describe(error)
            status = "Code not accepted"
        }
    }

    /// Supabase answers the same way whether or not the address has an account.
    func requestPasswordReset(email: String) async {
        guard !isBusy, let client else { return }
        let address = normalizedEmail(email)
        self.email = address
        guard address.contains("@") else {
            errorMessage = "Enter the email address you signed up with."
            return
        }
        beginAttempt("Sending code…")
        defer { endAttempt() }
        do {
            try await client.auth.resetPasswordForEmail(address)
            show(.resetPassword(email: address))
            resendAvailableAt = now().addingTimeInterval(Self.resendInterval)
            notice = "If \(address) has an account, we emailed it a code. Enter it with your new password."
            status = "Check your email for a code"
        } catch {
            errorMessage = describe(error)
            status = "Code not sent"
            if (error as? AuthError)?.errorCode == .overEmailSendRateLimit {
                resendAvailableAt = now().addingTimeInterval(Self.resendInterval)
            }
        }
    }

    /// The code and the new password are one step. Verifying a recovery code creates a
    /// session; it is kept only once the new password is saved, and is otherwise signed
    /// out on this Mac so an abandoned or failed reset never leaves anyone signed in.
    func completePasswordReset(code: String, newPassword: String) async {
        guard !isBusy, let client, case .resetPassword(let address) = authStep else { return }
        guard let token = validCode(code) else {
            clearSecrets()
            return
        }
        if let problem = Self.passwordProblem(newPassword) {
            clearSecrets()
            errorMessage = problem
            return
        }
        beginAttempt("Checking code…")
        defer { endAttempt() }
        holdingRecoverySession = true
        defer { holdingRecoverySession = false }
        let session: Session
        do {
            guard let verified = try await client.auth.verifyOTP(email: address, token: token, type: .recovery).session else {
                errorMessage = "That code could not sign you in. Request a new one."
                status = "Code not accepted"
                return
            }
            session = verified
        } catch {
            errorMessage = describe(error)
            status = "Code not accepted"
            return
        }
        let outcome: String
        do {
            try Task.checkCancellation()
            try await client.auth.update(user: UserAttributes(password: newPassword))
            outcome = "Password updated. You're signed in."
        } catch let error as AuthError where error.errorCode == .samePassword {
            outcome = "That was already your password. You're signed in."
        } catch {
            // Removes the session on this Mac even if the server can't be reached.
            try? await client.auth.signOut(scope: .local)
            show(.forgotPassword)
            email = address
            errorMessage = Task.isCancelled || error is CancellationError
                ? "The password reset was interrupted and your new password was not saved. Start again to get a new code."
                : "Your new password was not saved: \(describe(error)) Start again to get a new code."
            status = "Password not changed"
            return
        }
        show(.signIn)
        activate(session)
        if journal != nil { status = outcome }
    }

    /// Sends a fresh code for the current code step, at most once per resend interval.
    func resendCode() async {
        guard !isBusy, let client, canResend else { return }
        beginAttempt("Sending a new code…")
        defer { endAttempt() }
        do {
            switch authStep {
            case .confirmSignUp(let address):
                try await client.auth.resend(email: address, type: .signup)
                notice = "We sent a new code to \(address)."
            case .resetPassword(let address):
                try await client.auth.resetPasswordForEmail(address)
                notice = "If \(address) has an account, we sent it a new code."
            case .signIn, .createAccount, .forgotPassword:
                return
            }
            resendAvailableAt = now().addingTimeInterval(Self.resendInterval)
            status = "Check your email for a code"
        } catch {
            errorMessage = describe(error)
            status = "Code not sent"
            if (error as? AuthError)?.errorCode == .overEmailSendRateLimit {
                resendAvailableAt = now().addingTimeInterval(Self.resendInterval)
            }
        }
    }

    var canResend: Bool { resendWait(at: now()) == 0 }

    /// Whole seconds until another code may be requested; 0 when it can be sent now.
    func resendWait(at date: Date) -> Int {
        guard let resendAvailableAt else { return 0 }
        return max(0, Int(resendAvailableAt.timeIntervalSince(date).rounded(.up)))
    }

    /// Changes the password of the signed-in account. Returns whether it was saved.
    @discardableResult
    func changePassword(new: String) async -> Bool {
        guard !isBusy, let client else { return false }
        guard ownerID != nil else {
            clearSecrets()
            errorMessage = "Sign in before changing your password."
            return false
        }
        if let problem = Self.passwordProblem(new) {
            clearSecrets()
            errorMessage = problem
            return false
        }
        beginAttempt("Changing password…")
        defer { endAttempt() }
        do {
            try await client.auth.update(user: UserAttributes(password: new))
            status = "Password changed. Use it next time you sign in."
            return true
        } catch {
            errorMessage = describe(error)
            status = "Password not changed"
            return false
        }
    }

    private func beginAttempt(_ label: String) {
        isBusy = true
        errorMessage = nil
        status = label
    }

    private func endAttempt() {
        // Passwords are sent only to Supabase Auth, never saved in configuration,
        // the local queue, or Keychain. Only session tokens are persisted.
        clearSecrets()
        code = ""
        isBusy = false
    }

    private func clearSecrets() {
        password = ""
        passwordConfirmation = ""
        newPassword = ""
    }

    private func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validCode(_ value: String) -> String? {
        let digits = value.filter { !$0.isWhitespace }
        guard Self.isCompleteCode(digits) else {
            code = ""
            errorMessage = "Enter the code from the email."
            return nil
        }
        return digits
    }

    private static let accountExists = "An account with this email already exists, try signing in."

    /// Plain-English text for the auth errors a person can act on; anything else keeps the server's own words.
    private func describe(_ error: Error) -> String {
        if error is URLError { return "Can't reach the server. Check your internet connection and try again." }
        guard let error = error as? AuthError else { return error.localizedDescription }
        switch error.errorCode {
        case .otpExpired:
            return "That code is wrong or has expired. Check the latest email, or request a new code."
        case .userAlreadyExists, .emailExists:
            return Self.accountExists
        case .invalidCredentials:
            return "That email and password don't match an account. Try again, or use Forgot password."
        case .overEmailSendRateLimit:
            return "Too many emails were requested. Wait a minute, then try again."
        case .overRequestRateLimit:
            return "Too many attempts. Wait a few minutes, then try again."
        case .weakPassword:
            if case .weakPassword(let message, _) = error { return "Choose a stronger password. \(message)" }
            return "Choose a stronger password."
        case .samePassword:
            return "That is already your password. Choose a different one."
        case .signupDisabled:
            return "New accounts are switched off for this app right now. Ask the person who shared it with you."
        case .emailAddressNotAuthorized:
            return "The app can't send email to that address yet. Ask the person who shared it with you to finish its email setup."
        case .emailProviderDisabled:
            return "Email accounts are switched off for this app. Ask the person who shared it with you."
        case .sessionNotFound, .sessionExpired:
            return "Your session has ended. Sign in again, then try once more."
        case .reauthenticationNeeded:
            return "For security, sign out and use Forgot password to set a new password."
        default:
            return error.message
        }
    }

    func addEntry() {
        guard !isBusy, let ownerID, var journal else { return }
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "\(Host.current().localizedName ?? "Mac") · \(Date().formatted(date: .omitted, time: .standard))"
        do {
            try journal.enqueue(ProbeEntry(ownerID: ownerID, message: text.isEmpty ? fallback : text))
            self.journal = journal
            message = ""
            errorMessage = nil
            status = "Saved locally; \(pendingCount) pending"
            if !pauseSync { Task { await sync() } }
        } catch {
            errorMessage = error.localizedDescription
            status = "Entry could not be saved"
        }
    }

    func sync() async {
        guard !isBusy, !pauseSync, let client, let ownerID, let journal else { return }
        isBusy = true
        errorMessage = nil
        status = "Checking server…"
        defer { isBusy = false }
        do {
            // Refresh/validate the session before a write. Never relabel queued data.
            let session = try await client.auth.session
            guard session.user.id == ownerID else { throw JournalError.wrongOwner }
            let pending = journal.pending
            if !pending.isEmpty {
                try await client.from("sync_probe_entries")
                    .upsert(pending, onConflict: "id", ignoreDuplicates: true)
                    .execute()
            }
            // An upload response alone doesn't acknowledge a duplicate ID. Fetch and
            // compare actual immutable rows before clearing any pending entries.
            // Rows are decoded one at a time: an unreadable row is skipped and counted,
            // and only rows that decoded can acknowledge a pending entry.
            var remote: [ProbeEntry] = []
            var skipped = 0
            var offset = 0
            while true {
                let page: [ServerRow<ProbeEntry>] = try await client.from("sync_probe_entries")
                    .select("id,owner_id,message,client_created_at")
                    .eq("owner_id", value: ownerID.uuidString)
                    .order("id", ascending: true)
                    .range(from: offset, to: offset + 499)
                    .execute().value
                let readable = page.compactMap(\.value)
                remote.append(contentsOf: readable)
                skipped += page.count - readable.count
                if page.count < 500 { break }
                offset += page.count
            }
            guard self.ownerID == ownerID, var current = self.journal else { return }
            try current.merge(remote)
            self.journal = current
            lastSync = Date()
            status = [pendingCount == 0 ? "Up to date" : "\(pendingCount) entries still pending", skippedRowsNotice(skipped)]
                .compactMap { $0 }.joined(separator: " · ")
        } catch {
            errorMessage = error.localizedDescription
            status = "Sync unavailable; local entries are retained"
        }
    }

    func signOut() async {
        guard !isBusy, let client else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            // Local scope must not sign the other Mac out.
            try await client.auth.signOut(scope: .local)
            activate(nil)
            show(.signIn)
            message = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
