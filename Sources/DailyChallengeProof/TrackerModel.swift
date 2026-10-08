import ChallengeCore
import Foundation
import Observation
import Network

/// One serialized writer for the active app account. Real challenge data never
/// enters the probe queue. Clock injection lets the UI's date/edit paths be tested.
@MainActor @Observable
final class TrackerModel {
    private(set) var ownerID: UUID?
    private(set) var store: ChallengeStore? {
        didSet {
            refreshReminders()
            observeCompletion()
        }
    }
    var reminders: WaterReminderController?
    private(set) var celebration: CelebrationEvent?
    @ObservationIgnored private var localCompletionDay: Date?

    private func observeCompletion() {
        guard let challenge, let record = store?.record else { return }
        let ledger = CelebrationLedger(file: directory.appendingPathComponent("celebrations-\(challenge.ownerID.uuidString).json"))
        if let kind = ledger.observe(challenge, challengeID: record.id, now: clock(), localCompletionDay: localCompletionDay) {
            celebration = CelebrationEvent(kind: kind, started: clock())
        }
    }

    func refreshReminders() {
        let date = clock()
        let nextDay = WaterReminderPlanner.calendar.date(byAdding: .day, value: 1, to: date)!
        func water(on day: Date) -> Int? {
            let summary = challenge?.summary(on: day, asOf: date)
            return summary?.status == .outsideChallenge ? nil : summary?.waterMillilitres
        }
        reminders?.refresh(waterMillilitres: water(on: date), nextDayWaterMillilitres: water(on: nextDay))
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
    private(set) var retryAfter: Date?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var generation = UUID()

    var canStartChallenge: Bool { !syncActive || (setupChecked && !isSyncing && syncError == nil) }
    var syncStatus: String {
        guard syncActive else { return "Local only · Not synced" }
        let pending = store?.pendingCount ?? 0
        if let syncError { return "Sync unavailable · \(pending) pending · \(syncError)" }
        if isSyncing { return "Checking sync · \(pending) pending" }
        if pending > 0 { return "Saved locally · \(pending) pending" }
        guard let lastSync else { return "Waiting for server check" }
        let checked = "Synced · \(lastSync.formatted(date: .omitted, time: .shortened))"
        return (store?.hasClockWarning ?? false) ? checked + " · Clock/delivery delay > 5 min" : checked
    }

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
                let events = try await transport.fetchEvents(ownerID: ownerID, challengeID: remote.id)
                guard generation == token, var current = store else { return }
                try current.merge(record: remote, events: events)
                store = current
            }
            setupChecked = true
            syncError = nil
            lastSync = clock()
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
        self.selectedDay = JerseyDates.calendar.startOfDay(for: now)
    }

    var challenge: Challenge? { store?.challenge }
    var summary: Challenge.DailySummary? { challenge?.summary(on: selectedDay, asOf: now) }
    var streaks: Challenge.StreakSummary? { challenge?.streaks(asOf: now) }
    var history: [Challenge.Activity] { challenge?.history(on: selectedDay).reversed() ?? [] }
    var today: Date { JerseyDates.calendar.startOfDay(for: now) }
    var dayNumber: Int {
        guard let challenge else { return 0 }
        return max(0, (JerseyDates.calendar.dateComponents([.day], from: challenge.startDate, to: today).day ?? 0) + 1)
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
        let day = JerseyDates.calendar.startOfDay(for: date)
        guard let challenge, day >= challenge.startDate, day <= today else { return }
        followsToday = false
        selectedDay = day
        isEditingHistory = false
        errorMessage = nil
    }

    func enableCorrections() { isEditingHistory = true }
    func dismissError() { errorMessage = nil }

    func startChallenge(on date: Date) {
        refresh()
        guard canStartChallenge else {
            errorMessage = "Check the server before setup. Existing local history can still be used offline."
            return
        }
        guard JerseyDates.calendar.startOfDay(for: date) <= today else {
            errorMessage = "Choose today or an earlier start date."
            return
        }
        guard var candidate = store else { return }
        do {
            try candidate.start(on: date)
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
