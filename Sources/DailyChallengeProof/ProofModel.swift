import AppKit
import Foundation
import Observation
import ProbeCore
import Supabase

private struct ProofConfiguration: Decodable {
    let supabaseURL: URL
    let publishableKey: String
}

@MainActor @Observable
final class ProofModel {
    var email = ""
    var password = ""
    var message = ""
    var pauseSync = false
    private(set) var signedInEmail: String?
    private(set) var ownerID: UUID?
    private(set) var journal: ProbeJournal?
    private(set) var isBusy = false
    private(set) var status = "Restoring session…"
    private(set) var errorMessage: String?
    private(set) var configurationReady = false

    @ObservationIgnored private var client: SupabaseClient?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var lastSync: Date?
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private weak var tracker: TrackerModel?

    func attachTracker(_ tracker: TrackerModel) {
        self.tracker = tracker
        if let client { tracker.configureSync(SupabaseChallengeTransport(client: client), automatic: true) }
        tracker.activate(ownerID: ownerID)
    }

    init() {
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
    init(fixtureOwnerID: UUID?, directory: URL) {
        self.directory = directory
        self.ownerID = fixtureOwnerID
        self.signedInEmail = fixtureOwnerID == nil ? nil : "fixture@example.invalid"
        self.configurationReady = true
        self.status = "Offline appearance fixture"
    }

    /// Allows tests to exercise the real SDK login path without a real account or Keychain.
    init(client: SupabaseClient, directory: URL) {
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
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.contains("@"), !password.isEmpty else {
            errorMessage = "Enter your app account email and password."
            return
        }
        isBusy = true
        errorMessage = nil
        status = "Signing in…"
        defer {
            // Passwords are sent only to Supabase Auth, never saved in configuration,
            // the local queue, or Keychain. Only session tokens are persisted.
            password = ""
            isBusy = false
        }
        do {
            let session = try await client.auth.signIn(email: address, password: password)
            activate(session)
            if journal != nil {
                status = "Signed in. Use Sync now to check the server."
            }
        } catch {
            errorMessage = error.localizedDescription
            status = "Sign-in failed"
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
            var remote: [ProbeEntry] = []
            var offset = 0
            while true {
                let page: [ProbeEntry] = try await client.from("sync_probe_entries")
                    .select("id,owner_id,message,client_created_at")
                    .eq("owner_id", value: ownerID.uuidString)
                    .order("id", ascending: true)
                    .range(from: offset, to: offset + 499)
                    .execute().value
                remote.append(contentsOf: page)
                if page.count < 500 { break }
                offset += page.count
            }
            guard self.ownerID == ownerID, var current = self.journal else { return }
            try current.merge(remote)
            self.journal = current
            lastSync = Date()
            status = pendingCount == 0 ? "Up to date" : "\(pendingCount) entries still pending"
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
            password = ""
            message = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
