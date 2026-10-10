import ChallengeCore
import ChallengeSyncKit
import Darwin
import Foundation

/// Contains no credentials or user-facing account information.
struct PhoneSharedAccount: Codable, Equatable {
    let ownerID: UUID
    let generation: UUID
    let challengeID: UUID?
}

enum PhoneSharedStoreError: LocalizedError {
    case unavailable, staleAccount, relocationConflict, protectedData
    var errorDescription: String? {
        switch self {
        case .unavailable: "Shared storage is unavailable. Open Daily Challenge after unlocking your iPhone. The App Group capability must be enabled for this build."
        case .staleAccount: "The active account changed. Open Daily Challenge to continue."
        case .relocationConflict: "Storage recovery is needed: the old and shared histories differ. Both copies have been kept. Do not start a new challenge; retain both copies for recovery."
        case .protectedData: "Shared history is protected until your iPhone has been unlocked. Open Daily Challenge after unlocking."
        }
    }
}

/// The phone and future extension share this stable lock inode. flock handles
/// other processes; the static mutex serializes independent accessors in this one.
/// Neither the lock nor the mutex spans an async/network operation.
final class PhoneSharedStore: TrackerStoreAccess, @unchecked Sendable {
    static let groupID = "group.app.daily-challenge.ios"
    private let root: URL?
    private let legacy: URL?
    private let available: () -> Bool
    private let afterCopy: () throws -> Void
    private var binding: PhoneSharedAccount?
    var onCommitted: (() -> Void)?

    init(root: URL?, legacy: URL? = nil, available: @escaping () -> Bool = { true },
         afterCopy: @escaping () throws -> Void = {}) {
        self.root = root
        self.legacy = legacy
        self.available = available
        self.afterCopy = afterCopy
    }

    @MainActor static func production() -> PhoneSharedStore {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
        return PhoneSharedStore(root: container?.appendingPathComponent("ChallengeHistory", isDirectory: true),
                                legacy: TrackerModel.defaultDirectory)
    }

    /// Clear visibility *before* attempting to open another account. A failed
    /// relocation/open never leaves a prior account visible to an extension.
    func activate(ownerID: UUID?) throws -> ChallengeStore? {
        defer { onCommitted?() }
        return try locked { root in
            binding = nil
            try writeAccount(nil, root: root)
            try relocate(root: root)
            guard let ownerID else { return nil }
            let store = try ChallengeStore(ownerID: ownerID, directory: root)
            let account = PhoneSharedAccount(ownerID: ownerID, generation: UUID(), challengeID: store.record?.id)
            try protectFiles(root)
            try writeAccount(account, root: root)
            binding = account
            return store
        }
    }

    func transaction<Result>(ownerID: UUID, _ operation: (inout ChallengeStore) throws -> Result) throws -> (ChallengeStore, Result) {
        try locked { root in
            guard let binding, binding.ownerID == ownerID,
                  try readAccount(root) == binding else { throw PhoneSharedStoreError.staleAccount }
            var store = try ChallengeStore(ownerID: ownerID, directory: root)
            guard store.record?.id == binding.challengeID else { throw PhoneSharedStoreError.staleAccount }
            let result = try operation(&store)
            let updated = PhoneSharedAccount(ownerID: ownerID, generation: binding.generation, challengeID: store.record?.id)
            try protectFiles(root)
            try writeAccount(updated, root: root)
            self.binding = updated
            onCommitted?()
            return (store, result)
        }
    }

    func observeCompletion(ownerID: UUID, now: Date, localCompletionDay: Date?, localExtrasDay: Date?) throws -> CompletionCelebration? {
        try locked { root in
            guard let binding, binding.ownerID == ownerID, try readAccount(root) == binding else {
                throw PhoneSharedStoreError.staleAccount
            }
            let store = try ChallengeStore(ownerID: ownerID, directory: root)
            guard store.record?.id == binding.challengeID else { throw PhoneSharedStoreError.staleAccount }
            guard let challenge = store.challenge, let record = store.record else { return nil }
            let ledger = CelebrationLedger(file: root.appendingPathComponent("celebrations-\(ownerID.uuidString).json"))
            let result = ledger.observe(challenge, challengeID: record.id, now: now,
                                        localCompletionDay: localCompletionDay, localExtrasDay: localExtrasDay)
            try protectFiles(root)
            return result
        }
    }

    /// Future consumers receive only the published account; never enumerate files
    /// to select an owner. Stale actions must supply this exact opaque binding.
    func readActive() throws -> (PhoneSharedAccount, ChallengeStore)? {
        try locked { root in
            guard let account = try readAccount(root) else { return nil }
            let store = try ChallengeStore(ownerID: account.ownerID, directory: root)
            guard store.record?.id == account.challengeID else { throw PhoneSharedStoreError.staleAccount }
            return (account, store)
        }
    }

    func transaction<Result>(account: PhoneSharedAccount, _ operation: (inout ChallengeStore) throws -> Result) throws -> (ChallengeStore, Result) {
        try locked { root in
            guard try readAccount(root) == account else { throw PhoneSharedStoreError.staleAccount }
            var store = try ChallengeStore(ownerID: account.ownerID, directory: root)
            guard store.record?.id == account.challengeID else { throw PhoneSharedStoreError.staleAccount }
            let result = try operation(&store)
            try protectFiles(root)
            try writeAccount(PhoneSharedAccount(ownerID: account.ownerID, generation: account.generation,
                                               challengeID: store.record?.id), root: root)
            return (store, result)
        }
    }

    private func locked<Result>(_ body: (URL) throws -> Result) throws -> Result {
        guard available() else { throw PhoneSharedStoreError.protectedData }
        guard let root else { throw PhoneSharedStoreError.unavailable }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
                                                             .posixPermissions: 0o700])
        return try TrackerStoreLock(file: root.appendingPathComponent("shared.lock")).withLock {
            try body(root)
        }
    }

    private func readAccount(_ root: URL) throws -> PhoneSharedAccount? {
        let file = root.appendingPathComponent("active-account.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(PhoneSharedAccount?.self, from: Data(contentsOf: file))
    }

    private func writeAccount(_ account: PhoneSharedAccount?, root: URL) throws {
        try durableWrite(JSONEncoder().encode(account), to: root.appendingPathComponent("active-account.json"))
    }

    private func durableWrite(_ data: Data, to file: URL) throws {
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let fd = open(file.path, O_RDONLY)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw POSIXError(.EIO) }
        let dir = open(file.deletingLastPathComponent().path, O_RDONLY)
        guard dir >= 0 else { throw POSIXError(.EIO) }
        defer { close(dir) }
        guard fsync(dir) == 0 else { throw POSIXError(.EIO) }
    }

    private func protectFiles(_ root: URL) throws {
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
                                                  .posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    /// Stage exact originals, validate/migrate only the stage, then copy validated
    /// bytes without replacing any differing destination. Keep the stage across
    /// interruptions (especially version-1 migration's generated identities).
    /// Originals are never modified. Appearance/reminder UserDefaults stay local.
    private func relocate(root: URL) throws {
        let marker = root.appendingPathComponent("relocation-complete.json")
        if FileManager.default.fileExists(atPath: marker.path) { return }
        let stage = root.appendingPathComponent("relocation-stage", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: stage, withIntermediateDirectories: true,
                               attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let stagedMarker = stage.appendingPathComponent("validated.json")
        if !fm.fileExists(atPath: stagedMarker.path) {
            // An incomplete preparation is safe to repeat: no destination commits
            // happen until the full staged snapshot set has validated.
            for file in try fm.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil) { try fm.removeItem(at: file) }
            let originals = stage.appendingPathComponent("originals", isDirectory: true)
            try fm.createDirectory(at: originals, withIntermediateDirectories: true,
                                   attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            if let legacy, fm.fileExists(atPath: legacy.path) {
                for source in try fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)
                    where relevant(source.lastPathComponent) {
                    let data = try Data(contentsOf: source)
                    try durableWrite(data, to: originals.appendingPathComponent(source.lastPathComponent))
                    try durableWrite(data, to: stage.appendingPathComponent(source.lastPathComponent))
                }
            }
            try validateStores(stage)
            // ChallengeStore can migrate a legacy snapshot during validation.
            // Flush those resulting bytes before marking this stage reusable.
            for file in try fm.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil) where relevant(file.lastPathComponent) {
                try durableWrite(Data(contentsOf: file), to: file)
            }
            try durableWrite(Data("true".utf8), to: stagedMarker)
        }
        // Do not silently use an older stage if an older app changed its private
        // history during recovery. Preserve everything and require recovery.
        if let legacy, fm.fileExists(atPath: legacy.path) {
            let originals = stage.appendingPathComponent("originals", isDirectory: true)
            let oldFiles = try fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil).filter { relevant($0.lastPathComponent) }
            let savedFiles = try fm.contentsOfDirectory(at: originals, includingPropertiesForKeys: nil)
            guard Set(oldFiles.map(\.lastPathComponent)) == Set(savedFiles.map(\.lastPathComponent)) else {
                throw PhoneSharedStoreError.relocationConflict
            }
            for source in oldFiles {
                guard try Data(contentsOf: source) == Data(contentsOf: originals.appendingPathComponent(source.lastPathComponent)) else {
                    throw PhoneSharedStoreError.relocationConflict
                }
            }
        }
        let files = try fm.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil).filter { relevant($0.lastPathComponent) }
        // Preflight every file before committing any of them.
        for source in files {
            let destination = root.appendingPathComponent(source.lastPathComponent)
            if fm.fileExists(atPath: destination.path), try Data(contentsOf: source) != Data(contentsOf: destination) {
                throw PhoneSharedStoreError.relocationConflict
            }
        }
        for source in files {
            let destination = root.appendingPathComponent(source.lastPathComponent)
            if !fm.fileExists(atPath: destination.path) {
                try durableWrite(Data(contentsOf: source), to: destination)
                try afterCopy()
            }
        }
        try validateStores(root)
        try durableWrite(Data("true".utf8), to: marker)
        try fm.removeItem(at: stage)
    }

    private func relevant(_ name: String) -> Bool {
        name.hasPrefix("challenge-") || name.hasPrefix("celebrations-")
    }

    private func validateStores(_ directory: URL) throws {
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let name = file.lastPathComponent
            guard name.hasPrefix("challenge-"), name.hasSuffix(".json") else { continue }
            let identifier = String(name.dropFirst("challenge-".count).dropLast(".json".count))
            guard let owner = UUID(uuidString: identifier) else { throw ChallengeSyncError.invalidRecord }
            _ = try ChallengeStore(ownerID: owner, directory: directory)
        }
    }
}
