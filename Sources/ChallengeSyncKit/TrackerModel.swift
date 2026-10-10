import ChallengeCore
import Foundation
import Observation
import Network

public enum SyncState: Equatable, Sendable {
    case localOnly
    case unavailable(pending: Int, error: String)
    case checking(pending: Int)
    case savedLocally(pending: Int)
    case awaitingCheck
    case synced(at: Date, clockWarning: Bool)

    public var footerText: String {
        switch self {
        case .localOnly: return "Local only · Not synced"
        case let .unavailable(pending, error): return "Sync unavailable · \(pending) pending · \(error)"
        case let .checking(pending): return "Checking sync · \(pending) pending"
        case let .savedLocally(pending): return "Saved locally · \(pending) pending"
        case .awaitingCheck: return "Waiting for server check"
        case let .synced(date, clockWarning):
            let checked = "Synced · \(date.formatted(date: .omitted, time: .shortened))"
            return clockWarning ? checked + " · Clock/delivery delay > 5 min" : checked
        }
    }

    /// Plain words for the Account tab; never adds information the footer lacks.
    public func plainText(on wording: DeviceWording) -> String {
        let device = wording.device
        switch self {
        case .localOnly: return "Saved on this \(device) only, not connected to the server"
        case .unavailable: return "Can't reach the server, your entries are safe"
        case let .checking(pending): return pending > 0 ? "Syncing, \(Self.changes(pending)) waiting" : "Syncing"
        case let .savedLocally(pending): return "Saved on this \(device), \(Self.changes(pending)) waiting"
        case .awaitingCheck: return "Saved on this \(device), checking the server shortly"
        case let .synced(date, _): return "Up to date, checked \(date.formatted(date: .omitted, time: .shortened))"
        }
    }

    public func clockWarningText(on wording: DeviceWording) -> String? {
        guard case .synced(_, true) = self else { return nil }
        return "This \(wording.device)'s clock looks ahead of the server; check \(wording.dateTimeSettings) if this keeps happening"
    }

    private static func changes(_ count: Int) -> String { count == 1 ? "1 change" : "\(count) changes" }
}

/// One serialized coordinator for the active app account. Opt-in store access
/// supplies cross-process transactions; default callers keep their single writer.
/// Real challenge data never
/// enters the probe queue. Clock injection lets the UI's date/edit paths be tested.
/// Shared by the Mac and iPhone apps; each drives refreshes and sync requests from
/// its own lifecycle (popup visibility and wake on the Mac, scene phase on iOS).
@MainActor @Observable
public final class TrackerModel {
    /// The legacy on-disk layout (HANDOFF.md): unchanged so existing Mac data keeps opening.
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("DailyChallenge/ujyvvyrugenknhjodfhc", isDirectory: true)
    }

    public private(set) var ownerID: UUID?
    public private(set) var store: ChallengeStore? {
        didSet {
            // Starting or adopting a challenge can change the zone that bounds days.
            selectedDay = followsToday ? today : dates.calendar.startOfDay(for: selectedDay)
            refreshReminders()
            observeCompletion()
        }
    }
    public var reminders: WaterReminderController?
    public private(set) var celebration: CelebrationEvent?
    @ObservationIgnored private var localCompletionDay: Date?
    @ObservationIgnored private var localExtrasDay: Date?

    private func observeCompletion() {
        guard let challenge, let record = store?.record else { return }
        let kind: CompletionCelebration?
        if let access {
            kind = try? access.observeCompletion(ownerID: challenge.ownerID, now: clock(),
                                                 localCompletionDay: localCompletionDay, localExtrasDay: localExtrasDay)
        } else {
            let ledger = CelebrationLedger(file: directory.appendingPathComponent("celebrations-\(challenge.ownerID.uuidString).json"))
            kind = ledger.observe(challenge, challengeID: record.id, now: clock(), localCompletionDay: localCompletionDay,
                                  localExtrasDay: localExtrasDay)
        }
        if let kind { celebration = CelebrationEvent(kind: kind, started: clock()) }
    }

    public func refreshReminders() {
        let date = clock()
        let nextDay = dates.calendar.date(byAdding: .day, value: 1, to: date)!
        func water(on day: Date) -> Int? {
            let summary = challenge?.summary(on: day, asOf: date)
            return summary?.status == .outsideChallenge ? nil : summary?.waterMillilitres
        }
        reminders?.refresh(waterMillilitres: water(on: date), nextDayWaterMillilitres: water(on: nextDay),
                           timeZone: dates.timeZone)
    }
    public private(set) var now: Date
    public private(set) var selectedDay: Date
    public private(set) var isEditingHistory = false
    public private(set) var errorMessage: String?
    @ObservationIgnored private let access: (any TrackerStoreAccess)?
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var followsToday = true
    @ObservationIgnored private var transport: (any ChallengeTransport)?
    @ObservationIgnored private var automaticRequests = false
    @ObservationIgnored private var monitor: NWPathMonitor?
    public private(set) var syncActive = false
    public private(set) var isSyncing = false
    public private(set) var setupChecked = false
    public private(set) var syncError: String?
    public private(set) var lastSync: Date?
    /// Server rows the last successful sync could not read.
    public private(set) var skippedRows = 0
    public private(set) var retryAfter: Date?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var hasActivated = false

    public var canStartChallenge: Bool { !syncActive || (setupChecked && !isSyncing && syncError == nil) }
    /// The one sync state. The footer and the Account tab are two wordings of it.
    public var syncState: SyncState {
        guard syncActive else { return .localOnly }
        let pending = store?.pendingCount ?? 0
        if let syncError { return .unavailable(pending: pending, error: syncError) }
        if isSyncing { return .checking(pending: pending) }
        if pending > 0 { return .savedLocally(pending: pending) }
        guard let lastSync else { return .awaitingCheck }
        return .synced(at: lastSync, clockWarning: store?.hasClockWarning ?? false)
    }
    /// Unreadable server rows are a note beside whatever the state is, never a failure.
    public var skippedNotice: String? { syncError == nil ? skippedRowsNotice(skippedRows) : nil }
    public var syncStatus: String { [syncState.footerText, skippedNotice].compactMap { $0 }.joined(separator: " · ") }

    /// Fixtures configure a transport without launching timers/network monitoring.
    public func configureSync(_ transport: any ChallengeTransport, automatic: Bool = false) {
        self.transport = transport
        automaticRequests = automatic
        syncActive = true
        setupChecked = false
        guard automatic, monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in self?.requestSync() }
        }
        monitor.start(queue: DispatchQueue(label: "DailyChallenge.reconnect"))
        self.monitor = monitor
        Task { [weak self] in
            while !Task.isCancelled {
                await self?.sync()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard self != nil else { return }
            }
        }
    }

    public func requestSync() {
        guard syncActive, automaticRequests else { return }
        Task { await sync() }
    }

    public func sync(force: Bool = false) async {
        guard !isSyncing, let transport, let ownerID, store != nil,
              force || retryAfter.map({ clock() >= $0 }) != false else { return }
        let token = generation
        isSyncing = true
        defer { if generation == token { isSyncing = false } }
        do {
            // Refresh pending/settings before the first network await. The lock is
            // released by transact; each later phase reloads again.
            if access != nil { try transact { _ in } }
            var skipped = 0
            var remote = try await transport.fetchChallenge(ownerID: ownerID)
            guard generation == token else { return }
            let localRecord = try transact { $0.record }
            if remote == nil, let record = localRecord {
                try await transport.insertChallenge(record)
                guard generation == token else { return }
                remote = try await transport.fetchChallenge(ownerID: ownerID)
                guard generation == token else { return }
                guard remote != nil else { throw ChallengeSyncError.invalidRecord }
            }
            if let remote {
                guard remote.ownerID == ownerID else { throw ChallengeSyncError.wrongOwner }
                let pending = try transact { current in
                    if let local = current.record, local != remote { throw ChallengeSyncError.conflictingChallenge }
                    return current.pending
                }
                try await transport.upload(pending, ownerID: ownerID)
                guard generation == token else { return }
                let fetched = try await transport.fetchEvents(ownerID: ownerID, challengeID: remote.id)
                guard generation == token else { return }
                // Only events that decoded are merged, so only they acknowledge pending uploads.
                try transact { try $0.merge(record: remote, events: fetched.events) }
                skipped = fetched.skipped
            }
            setupChecked = true
            syncError = nil
            lastSync = clock()
            skippedRows = skipped
            failures = 0
            retryAfter = nil
        } catch {
            guard generation == token else { return }
            setupChecked = false
            syncError = error.localizedDescription
            failures = min(failures + 1, 8)
            retryAfter = clock().addingTimeInterval(min(900, pow(2, Double(failures)) * 5))
        }
    }

    public init(directory: URL = TrackerModel.defaultDirectory, clock: @escaping () -> Date = Date.init,
                access: (any TrackerStoreAccess)? = nil) {
        self.access = access
        self.directory = directory
        self.clock = clock
        let now = clock()
        self.now = now
        self.selectedDay = ChallengeDates(timeZone: .current).calendar.startOfDay(for: now)
    }

    public var challenge: Challenge? { store?.challenge }
    /// The challenge's own zone. Before setup there is no challenge day yet; the
    /// device's zone only places the navigation date until one is chosen or adopted.
    public var dates: ChallengeDates { ChallengeDates(timeZone: challenge?.timeZone ?? .current) }
    public var summary: Challenge.DailySummary? { challenge?.summary(on: selectedDay, asOf: now) }
    public var streaks: Challenge.StreakSummary? { challenge?.streaks(asOf: now) }
    public var history: [Challenge.Activity] { challenge?.history(on: selectedDay).reversed() ?? [] }
    public var today: Date { dates.calendar.startOfDay(for: now) }
    public var dayNumber: Int {
        guard let challenge else { return 0 }
        return max(0, (dates.calendar.dateComponents([.day], from: challenge.startDate, to: today).day ?? 0) + 1)
    }
    public var canEdit: Bool {
        guard let summary, summary.status != .future, summary.status != .outsideChallenge else { return false }
        return followsToday || isEditingHistory
    }
    public var canUndo: Bool { canEdit && !(summary?.activePours.isEmpty ?? true) }

    public func activate(ownerID: UUID?) {
        guard !hasActivated || self.ownerID != ownerID else { refresh(); return }
        hasActivated = true
        generation = UUID()
        isSyncing = false
        setupChecked = false
        syncError = nil
        lastSync = nil
        skippedRows = 0
        retryAfter = nil
        failures = 0
        self.ownerID = ownerID
        celebration = nil
        store = nil
        errorMessage = nil
        showToday()
        if let access {
            do { store = try access.activate(ownerID: ownerID) }
            catch {
                hasActivated = false
                errorMessage = "Local history could not be opened. It has not been reset. \(error.localizedDescription)"
            }
            if store != nil { requestSync() }
        } else if ownerID != nil { reload(); requestSync() }
    }

    public func reload() {
        if access != nil && !hasActivated { activate(ownerID: ownerID); return }
        guard let ownerID else { return }
        do {
            store = try access?.transaction(ownerID: ownerID, { _ in }).0 ?? ChallengeStore(ownerID: ownerID, directory: directory)
            errorMessage = nil
        } catch {
            store = nil
            errorMessage = "Local history could not be opened. It has not been reset. \(error.localizedDescription)"
        }
    }

    public func refresh() {
        now = clock()
        if followsToday { selectedDay = today }
        refreshReminders()
    }

    public func showToday() {
        followsToday = true
        isEditingHistory = false
        refresh()
    }

    public func selectHistoryDay(_ date: Date) {
        refresh()
        let day = dates.calendar.startOfDay(for: date)
        guard let challenge, day >= challenge.startDate, day <= today else { return }
        followsToday = false
        selectedDay = day
        isEditingHistory = false
        errorMessage = nil
    }

    public func enableCorrections() { isEditingHistory = true }
    public func dismissError() { errorMessage = nil }

    public func startChallenge(on date: Date, timeZone: TimeZone) {
        refresh()
        guard canStartChallenge else {
            errorMessage = "Check the server before setup. Existing local history can still be used offline."
            return
        }
        let calendar = ChallengeDates(timeZone: timeZone).calendar
        guard calendar.startOfDay(for: date) <= calendar.startOfDay(for: now) else {
            errorMessage = "Choose today or an earlier start date."
            return
        }
        guard store != nil else { return }
        do {
            try transact { try $0.start(on: date, timeZone: timeZone) }
            errorMessage = nil
            showToday()
            setupChecked = false
            requestSync()
        } catch { errorMessage = error.localizedDescription }
    }

    public func exportData() throws -> Data {
        return try transact { try $0.exportData() }
    }

    public func previewImport(_ data: Data) throws -> ChallengeBackup.Plan {
        return try transact { try $0.previewImport(data) }
    }

    public func importData(_ data: Data) throws -> URL {
        let backup = try transact { try $0.importData(data) }
        refresh()
        requestSync()
        return backup
    }

    public func addWater(_ amount: Int = 450) { record(.pour(amount)) }

    public func addCustomWater(_ text: String) {
        guard let amount = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), amount > 0 else {
            errorMessage = "Enter a positive whole amount in ml, such as 250."
            return
        }
        addWater(amount)
    }

    public func undoWater() { record(.undoLatestPour) }

    public func toggle(_ habit: Challenge.Habit) {
        refresh()
        record { summary in .setHabit(habit, completed: !(summary?.completedHabits.contains(habit) ?? false)) }
    }

    public func setDiet(_ state: Challenge.DietState) { record(.setDiet(state)) }

    /// All opted-in actions are derived from the just-loaded summary, never a
    /// rendered snapshot. This also preserves concrete latest-pour undo semantics.
    private func record(_ action: Challenge.Action) { record { _ in action } }

    @discardableResult
    private func transact<Result>(_ operation: (inout ChallengeStore) throws -> Result) throws -> Result {
        guard let ownerID, var candidate = store else { throw ChallengeStoreError.notStarted }
        let result: Result
        if let access {
            let committed = try access.transaction(ownerID: ownerID, operation)
            candidate = committed.0
            result = committed.1
        } else {
            result = try operation(&candidate)
        }
        store = candidate
        return result
    }

    private func record(_ derive: (Challenge.DailySummary?) -> Challenge.Action) {
        refresh()
        guard canEdit, store != nil else {
            errorMessage = "Select Edit this day before making a historical correction."
            return
        }
        defer { localCompletionDay = nil; localExtrasDay = nil }
        do {
            _ = try transact { candidate in
                let fresh = candidate.challenge?.summary(on: selectedDay, asOf: now)
                guard let fresh, fresh.status != .future, fresh.status != .outsideChallenge else {
                    throw ChallengeStoreError.notStarted
                }
                let action = derive(fresh)
                if case let .setExtra(_, completed) = action {
                    localExtrasDay = completed && selectedDay == today ? today : nil
                }
                try candidate.record(action, on: selectedDay, at: now)
                localCompletionDay = !fresh.isComplete && selectedDay == today ? today : nil
                return fresh.isComplete
            }
            errorMessage = nil
            requestSync()
        } catch { errorMessage = "Could not save. Your previous history is intact. \(error.localizedDescription)" }
    }
}

// MARK: Extras

/// Personal daily to-dos beside the five requirements; they never make a day complete.
/// Ticks follow the selected day like habit marks. Adding, renaming and archiving
/// belong to the challenge rather than a day, so they are recorded on today without
/// the History correction lock.
extension TrackerModel {
    /// Not archived, in creation order: what Manage extras lists and the cap counts.
    public var activeExtras: [Challenge.Extra] { challenge?.allExtras.filter { !$0.isArchived } ?? [] }
    public var canAddExtra: Bool { challenge != nil && activeExtras.count < Challenge.maximumActiveExtras }

    public func toggleExtra(_ id: UUID) {
        refresh()
        // Completion provenance is derived from the fresh summary inside record.
        record { .setExtra(id: id, completed: !($0?.completedExtras.contains(id) ?? false)) }
    }

    /// Each returns nil once saved, otherwise the reason nothing was saved.
    public func addExtra(_ title: String) -> String? { defineExtra(id: UUID(), title: title) }

    public func renameExtra(_ id: UUID, to title: String) -> String? {
        return defineExtra(id: id, title: title)
    }

    public func archiveExtra(_ id: UUID) -> String? { recordExtraSetting(.archiveExtra(id: id)) }

    private func defineExtra(id: UUID, title: String) -> String? {
        guard let title = Challenge.extraTitle(title) else { return ChallengeError.invalidExtraTitle.localizedDescription }
        return recordExtraSetting(.defineExtra(id: id, title: title))
    }

    private func recordExtraSetting(_ action: Challenge.Action) -> String? {
        refresh()
        guard store?.challenge != nil else {
            return ChallengeStoreError.notStarted.localizedDescription
        }
        do {
            try transact { candidate in
                if case let .defineExtra(id, title) = action,
                   candidate.challenge?.allExtras.first(where: { $0.id == id && !$0.isArchived })?.title == title { return }
                try candidate.record(action, on: now, at: now)
            }
            requestSync()
            return nil
        } catch let error as ChallengeError {
            return error.localizedDescription
        } catch {
            return "Could not save. Your previous history is intact. \(error.localizedDescription)"
        }
    }
}
