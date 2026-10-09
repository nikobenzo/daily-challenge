import AppKit
import ChallengeSyncKit
import Foundation
import Observation
import ProbeCore
import Supabase

/// The Mac's account object: the shared `AuthModel` (ChallengeSyncKit) under the Mac's
/// legacy Keychain names, plus the Mac-only test-message diagnostics journal. Views keep
/// talking to one object; auth members forward to `account`.
@MainActor @Observable
final class ProofModel {
    /// Legacy identity (HANDOFF.md): renaming either would sign every installed Mac out.
    static let storage = SessionStorage(keychainService: "app.daily-challenge.proof.auth",
                                        storageKey: "daily-challenge-proof-ujyvvyrugenknhjodfhc")

    let account: AuthModel
    var message = ""
    var pauseSync = false
    private(set) var journal: ProbeJournal?
    /// The diagnostics' own status line, shown under Advanced; auth keeps `status`.
    private(set) var diagnosticStatus = "Sign in to test private sync"
    private(set) var diagnosticError: String?

    @ObservationIgnored private var started = false
    @ObservationIgnored private var lastSync: Date?
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var journalOwner: UUID?

    init() {
        account = AuthModel(storage: Self.storage,
                            missingConfiguration: "Build the .app using scripts/build-proof.sh. Configuration could not be loaded.")
        directory = URL.applicationSupportDirectory
            .appendingPathComponent("DailyChallengeProof", isDirectory: true)
            .appendingPathComponent("ujyvvyrugenknhjodfhc", isDirectory: true)
        observeSessions()
    }

    /// Offline UI fixtures: no SDK client, Keychain, network, or production paths.
    init(
        fixtureOwnerID: UUID?, directory: URL, authStep: AuthStep = .signIn,
        notice: String? = nil, errorMessage: String? = nil, resendAvailableAt: Date? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        account = AuthModel(fixtureOwnerID: fixtureOwnerID, authStep: authStep, notice: notice,
                            errorMessage: errorMessage, resendAvailableAt: resendAvailableAt, now: now)
        self.directory = directory
        diagnosticStatus = "Offline appearance fixture"
    }

    /// Allows tests to exercise the real SDK login path without a real account or Keychain.
    init(client: SupabaseClient, directory: URL, now: @escaping () -> Date = Date.init) {
        account = AuthModel(client: client, now: now)
        self.directory = directory
        observeSessions()
    }

    private func observeSessions() {
        account.onSessionChange { [weak self] owner in self?.openJournal(for: owner) }
    }

    // MARK: Auth, forwarded to the shared model

    var email: String { get { account.email } set { account.email = newValue } }
    var password: String { get { account.password } set { account.password = newValue } }
    var passwordConfirmation: String {
        get { account.passwordConfirmation } set { account.passwordConfirmation = newValue }
    }
    var newPassword: String { get { account.newPassword } set { account.newPassword = newValue } }
    var code: String { get { account.code } set { account.code = newValue } }
    var authStep: AuthStep { get { account.authStep } set { account.authStep = newValue } }
    var signedInEmail: String? { account.signedInEmail }
    var ownerID: UUID? { account.ownerID }
    var isBusy: Bool { account.isBusy }
    var status: String { account.status }
    var errorMessage: String? { account.errorMessage }
    var configurationReady: Bool { account.configurationReady }
    var notice: String? { account.notice }
    var resendAvailableAt: Date? { account.resendAvailableAt }
    var canResend: Bool { account.canResend }

    nonisolated static var minimumPasswordLength: Int { AuthModel.minimumPasswordLength }
    nonisolated static var codeLengths: ClosedRange<Int> { AuthModel.codeLengths }
    nonisolated static var passwordRule: String { AuthModel.passwordRule }
    nonisolated static func passwordProblem(_ password: String) -> String? { AuthModel.passwordProblem(password) }
    nonisolated static func isCompleteCode(_ code: String) -> Bool { AuthModel.isCompleteCode(code) }

    func attachTracker(_ tracker: TrackerModel) { account.attachTracker(tracker) }
    func show(_ step: AuthStep) { account.show(step) }
    func signIn() async { await account.signIn() }
    func signUp(email: String, password: String) async { await account.signUp(email: email, password: password) }
    func confirmSignUp(code: String) async { await account.confirmSignUp(code: code) }
    func requestPasswordReset(email: String) async { await account.requestPasswordReset(email: email) }
    func completePasswordReset(code: String, newPassword: String) async {
        await account.completePasswordReset(code: code, newPassword: newPassword)
    }
    func resendCode() async { await account.resendCode() }
    func resendWait(at date: Date) -> Int { account.resendWait(at: date) }
    @discardableResult func changePassword(new: String) async -> Bool { await account.changePassword(new: new) }

    func signOut() async {
        await account.signOut()
        if account.ownerID == nil { message = "" }
    }

    func start() {
        account.start()
        guard !started, account.client != nil else { return }
        started = true
        Task {
            // Polling also recovers updates missed while asleep. Not a production sync engine.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await sync()
            }
        }
    }

    // MARK: Test-message diagnostics (Mac only)

    var entries: [ProbeEntry] { journal?.entries.reversed() ?? [] }
    var pendingCount: Int { journal?.pending.count ?? 0 }
    var lastSyncLabel: String {
        lastSync.map { "Last checked \($0.formatted(date: .omitted, time: .shortened))" }
            ?? "Not checked yet"
    }
    func isPending(_ id: UUID) -> Bool { journal?.isPending(id) ?? false }

    private func openJournal(for owner: UUID?) {
        guard let owner else {
            journalOwner = nil
            journal = nil
            lastSync = nil
            diagnosticStatus = "Sign in to test private sync"
            return
        }
        guard journalOwner != owner else { return }
        journalOwner = owner
        lastSync = nil
        do {
            journal = try ProbeJournal(ownerID: owner, directory: directory)
            diagnosticError = nil
            diagnosticStatus = "Local queue ready"
        } catch {
            journal = nil
            diagnosticError = error.localizedDescription
            diagnosticStatus = "Local data could not be opened; it has not been reset"
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
            diagnosticError = nil
            diagnosticStatus = "Saved locally; \(pendingCount) pending"
            if !pauseSync { Task { await sync() } }
        } catch {
            diagnosticError = error.localizedDescription
            diagnosticStatus = "Entry could not be saved"
        }
    }

    func sync() async {
        guard !isBusy, !pauseSync, let client = account.client, let ownerID, let journal else { return }
        account.setBusy(true)
        diagnosticError = nil
        diagnosticStatus = "Checking server…"
        defer { account.setBusy(false) }
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
            diagnosticStatus = [pendingCount == 0 ? "Up to date" : "\(pendingCount) entries still pending",
                                skippedRowsNotice(skipped)]
                .compactMap { $0 }.joined(separator: " · ")
        } catch {
            diagnosticError = error.localizedDescription
            diagnosticStatus = "Sync unavailable; local entries are retained"
        }
    }
}
