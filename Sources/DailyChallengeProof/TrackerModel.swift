import ChallengeCore
import Foundation
import Observation
import Network

enum SyncState: Equatable {
    case localOnly
    case unavailable(pending: Int, error: String)
    case checking(pending: Int)
    case savedLocally(pending: Int)
    case awaitingCheck
    case synced(at: Date, clockWarning: Bool)

    var footerText: String {
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
    var plainText: String {
        switch self {
        case .localOnly: return "Saved on this Mac only, not connected to the server"
        case .unavailable: return "Can't reach the server, your entries are safe"
        case let .checking(pending): return pending > 0 ? "Syncing, \(Self.changes(pending)) waiting" : "Syncing"
        case let .savedLocally(pending): return "Saved on this Mac, \(Self.changes(pending)) waiting"
        case .awaitingCheck: return "Saved on this Mac, checking the server shortly"
        case let .synced(date, _): return "Up to date, checked \(date.formatted(date: .omitted, time: .shortened))"
        }
    }

    var clockWarningText: String? {
        guard case .synced(_, true) = self else { return nil }
        return "This Mac's clock looks ahead of the server; check Date & Time if this keeps happening"
    }

    private static func changes(_ count: Int) -> String { count == 1 ? "1 change" : "\(count) changes" }
}

/// One serialized writer for the active app account. Real challenge data never
/// enters the probe queue. Clock injection lets the UI's date/edit paths be tested.
@MainActor @Observable
final class TrackerModel {
    private(set) var ownerID: UUID?
    private(set) var store: ChallengeStore? {
        didSet {
            // Starting or adopting a challenge can change the zone that bounds days.
            selectedDay = followsToday ? today : dates.calendar.startOfDay(for: selectedDay)
            refreshReminders()
            observeCompletion()
        }
    }
    var reminders: WaterReminderController?
    private(set) var celebration: CelebrationEvent?
    @ObservationIgnored private var localCompletionDay: Date?
    @ObservationIgnored private var localExtrasDay: Date?

    private func observeCompletion() {
        guard let challenge, let record = store?.record else { return }
        let ledger = CelebrationLedger(file: directory.appendingPathComponent("celebrations-\(challenge.ownerID.uuidString).json"))
        if let kind = ledger.observe(challenge, challengeID: record.id, now: clock(), localCompletionDay: localCompletionDay,
                                     localExtrasDay: localExtrasDay) {
            celebration = CelebrationEvent(kind: kind, started: clock())
        }
    }

    func refreshReminders() {
        let date = clock()
        let nextDay = dates.calendar.date(byAdding: .day, value: 1, to: date)!
        func water(on day: Date) -> Int? {
            let summary = challenge?.summary(on: day, asOf: date)
            return summary?.status == .outsideChallenge ? nil : summary?.waterMillilitres
        }
        reminders?.refresh(waterMillilitres: water(on: date), nextDayWaterMillilitres: water(on: nextDay),
                           timeZone: dates.timeZone)
    }
    private(set) var now: Date
    private(set) var selectedDay: Date
    private(set) var isEditingHistory = false
    private(set) var errorMessage: String?
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var followsToday = true
    @ObservationIgnored private var transport: (any ChallengeTransport)?
    @ObservationIgnored private var automaticRequests = false
    @ObservationIgnored private var monitor: NWPathMonitor?
    private(set) var syncActive = false
    private(set) var isSyncing = false
    private(set) var setupChecked = false
    private(set) var syncError: String?
    private(set) var lastSync: Date?
    /// Server rows the last successful sync could not read.
    private(set) var skippedRows = 0
    private(set) var retryAfter: Date?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var generation = UUID()

    var canStartChallenge: Bool { !syncActive || (setupChecked && !isSyncing && syncError == nil) }
    /// The one sync state. The footer and the Account tab are two wordings of it.
    var syncState: SyncState {
        guard syncActive else { return .localOnly }
        let pending = store?.pendingCount ?? 0
        if let syncError { return .unavailable(pending: pending, error: syncError) }
        if isSyncing { return .checking(pending: pending) }
        if pending > 0 { return .savedLocally(pending: pending) }
        guard let lastSync else { return .awaitingCheck }
        return .synced(at: lastSync, clockWarning: store?.hasClockWarning ?? false)
    }
    /// Unreadable server rows are a note beside whatever the state is, never a failure.
    var skippedNotice: String? { syncError == nil ? skippedRowsNotice(skippedRows) : nil }
    var syncStatus: String { [syncState.footerText, skippedNotice].compactMap { $0 }.joined(separator: " · ") }

    /// Fixtures configure a transport without launching timers/network monitoring.
    func configureSync(_ transport: any ChallengeTransport, automatic: Bool = false) {
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

    func requestSync() {
        guard syncActive, automaticRequests else { return }
        Task { await sync() }
    }

    func sync(force: Bool = false) async {
        guard !isSyncing, let transport, let ownerID, store != nil,
              force || retryAfter.map({ clock() >= $0 }) != false else { return }
        let token = generation
        isSyncing = true
        defer { if generation == token { isSyncing = false } }
        do {
            var skipped = 0
            var remote = try await transport.fetchChallenge(ownerID: ownerID)
            guard generation == token else { return }
            if remote == nil, let record = store?.record {
                try await transport.insertChallenge(record)
                guard generation == token else { return }
                remote = try await transport.fetchChallenge(ownerID: ownerID)
                guard generation == token else { return }
                guard remote != nil else { throw ChallengeSyncError.invalidRecord }
            }
            if let remote {
                guard remote.ownerID == ownerID else { throw ChallengeSyncError.wrongOwner }
                if let local = store?.record, local != remote { throw ChallengeSyncError.conflictingChallenge }
                let pending = store?.pending ?? []
                try await transport.upload(pending, ownerID: ownerID)
                guard generation == token else { return }
                let fetched = try await transport.fetchEvents(ownerID: ownerID, challengeID: remote.id)
                guard generation == token, var current = store else { return }
                // Only events that decoded are merged, so only they acknowledge pending uploads.
                try current.merge(record: remote, events: fetched.events)
                store = current
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

    init(
        directory: URL = URL.applicationSupportDirectory
            .appendingPathComponent("DailyChallenge/ujyvvyrugenknhjodfhc", isDirectory: true),
        clock: @escaping () -> Date = Date.init
    ) {
        self.directory = directory
        self.clock = clock
        let now = clock()
        self.now = now
        self.selectedDay = ChallengeDates(timeZone: .current).calendar.startOfDay(for: now)
    }

    var challenge: Challenge? { store?.challenge }
    /// The challenge's own zone. Before setup there is no challenge day yet; the
    /// Mac's zone only places the navigation date until one is chosen or adopted.
    var dates: ChallengeDates { ChallengeDates(timeZone: challenge?.timeZone ?? .current) }
    var summary: Challenge.DailySummary? { challenge?.summary(on: selectedDay, asOf: now) }
    var streaks: Challenge.StreakSummary? { challenge?.streaks(asOf: now) }
    var history: [Challenge.Activity] { challenge?.history(on: selectedDay).reversed() ?? [] }
    var today: Date { dates.calendar.startOfDay(for: now) }
    var dayNumber: Int {
        guard let challenge else { return 0 }
        return max(0, (dates.calendar.dateComponents([.day], from: challenge.startDate, to: today).day ?? 0) + 1)
    }
    var canEdit: Bool {
        guard let summary, summary.status != .future, summary.status != .outsideChallenge else { return false }
        return followsToday || isEditingHistory
    }
    var canUndo: Bool { canEdit && !(summary?.activePours.isEmpty ?? true) }

    func activate(ownerID: UUID?) {
        guard self.ownerID != ownerID else { refresh(); return }
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
        if ownerID != nil { reload(); requestSync() }
    }

    func reload() {
        guard let ownerID else { return }
        do {
            store = try ChallengeStore(ownerID: ownerID, directory: directory)
            errorMessage = nil
        } catch {
            store = nil
            errorMessage = "Local history could not be opened. It has not been reset. \(error.localizedDescription)"
        }
    }

    func refresh() {
        now = clock()
        if followsToday { selectedDay = today }
        refreshReminders()
    }

    func showToday() {
        followsToday = true
        isEditingHistory = false
        refresh()
    }

    func selectHistoryDay(_ date: Date) {
        refresh()
        let day = dates.calendar.startOfDay(for: date)
        guard let challenge, day >= challenge.startDate, day <= today else { return }
        followsToday = false
        selectedDay = day
        isEditingHistory = false
        errorMessage = nil
    }

    func enableCorrections() { isEditingHistory = true }
    func dismissError() { errorMessage = nil }

    func startChallenge(on date: Date, timeZone: TimeZone) {
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
        guard var candidate = store else { return }
        do {
            try candidate.start(on: date, timeZone: timeZone)
            store = candidate
            errorMessage = nil
            showToday()
            setupChecked = false
            requestSync()
        } catch { errorMessage = error.localizedDescription }
    }

    func exportData() throws -> Data {
        guard let store else { throw ChallengeStoreError.notStarted }
        return try store.exportData()
    }

    func previewImport(_ data: Data) throws -> ChallengeBackup.Plan {
        guard let store else { throw ChallengeStoreError.notStarted }
        return try store.previewImport(data)
    }

    func importData(_ data: Data) throws -> URL {
        guard var candidate = store else { throw ChallengeStoreError.notStarted }
        let backup = try candidate.importData(data)
        store = candidate
        refresh()
        requestSync()
        return backup
    }

    func addWater(_ amount: Int = 450) { record(.pour(amount)) }

    func addCustomWater(_ text: String) {
        guard let amount = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), amount > 0 else {
            errorMessage = "Enter a positive whole amount in ml, such as 250."
            return
        }
        addWater(amount)
    }

    func undoWater() { record(.undoLatestPour) }

    func toggle(_ habit: Challenge.Habit) {
        refresh()
        record(.setHabit(habit, completed: !(summary?.completedHabits.contains(habit) ?? false)))
    }

    func setDiet(_ state: Challenge.DietState) { record(.setDiet(state)) }

    private func record(_ action: Challenge.Action) {
        refresh()
        guard canEdit, var candidate = store else {
            errorMessage = "Select Edit this day before making a historical correction."
            return
        }
        do {
            let wasComplete = summary?.isComplete == true
            try candidate.record(action, on: selectedDay, at: now)
            localCompletionDay = !wasComplete && selectedDay == today ? today : nil
            defer { localCompletionDay = nil }
            store = candidate
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
    var activeExtras: [Challenge.Extra] { challenge?.allExtras.filter { !$0.isArchived } ?? [] }
    var canAddExtra: Bool { challenge != nil && activeExtras.count < Challenge.maximumActiveExtras }

    func toggleExtra(_ id: UUID) {
        refresh()
        let done = summary?.completedExtras.contains(id) ?? false
        // Only a tick made here, today, may celebrate; opening or syncing never does.
        localExtrasDay = !done && selectedDay == today ? today : nil
        defer { localExtrasDay = nil }
        record(.setExtra(id: id, completed: !done))
    }

    /// Each returns nil once saved, otherwise the reason nothing was saved.
    func addExtra(_ title: String) -> String? { defineExtra(id: UUID(), title: title) }

    func renameExtra(_ id: UUID, to title: String) -> String? {
        guard Challenge.extraTitle(title) != activeExtras.first(where: { $0.id == id })?.title else { return nil }
        return defineExtra(id: id, title: title)
    }

    func archiveExtra(_ id: UUID) -> String? { recordExtraSetting(.archiveExtra(id: id)) }

    private func defineExtra(id: UUID, title: String) -> String? {
        guard let title = Challenge.extraTitle(title) else { return ChallengeError.invalidExtraTitle.localizedDescription }
        return recordExtraSetting(.defineExtra(id: id, title: title))
    }

    private func recordExtraSetting(_ action: Challenge.Action) -> String? {
        refresh()
        guard var candidate = store, candidate.challenge != nil else {
            return ChallengeStoreError.notStarted.localizedDescription
        }
        do {
            try candidate.record(action, on: now, at: now)
            store = candidate
            requestSync()
            return nil
        } catch let error as ChallengeError {
            return error.localizedDescription
        } catch {
            return "Could not save. Your previous history is intact. \(error.localizedDescription)"
        }
    }
}
