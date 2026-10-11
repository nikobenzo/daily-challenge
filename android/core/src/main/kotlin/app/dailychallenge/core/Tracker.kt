package app.dailychallenge.core

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.io.File
import java.io.IOException
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlin.math.min
import kotlin.math.pow

/**
 * One serialized coordinator for the signed-in account (Swift `TrackerModel`): the local
 * store, the sync coordinator and its state, the selected day and corrections. Every call
 * runs on one thread (the main thread in the app); `changes` ticks after each change so
 * the UI can redraw. Real challenge data never leaves this account's store and queue.
 */
class Tracker(
    private val directory: File,
    private val scope: CoroutineScope,
    private val clock: () -> Double = ChallengeTime::now,
    private val deviceZone: () -> ZoneId = ZoneId::systemDefault,
) {
    private val _changes = MutableStateFlow(0L)
    val changes: StateFlow<Long> = _changes
    private fun changed() { _changes.value = _changes.value + 1 }

    var ownerID: UUID? = null
        private set
    var store: ChallengeStore? = null
        private set
    var reminders: WaterReminderController? = null
    var celebration: CelebrationEvent? = null
        private set
    private var localCompletionDay: Double? = null
    private var localExtrasDay: Double? = null

    var now: Double = clock()
        private set
    var selectedDay: Double = ChallengeCalendar(deviceZone()).startOfDay(now)
        private set
    var isEditingHistory = false
        private set
    var errorMessage: String? = null
        private set
    private var followsToday = true
    private var transport: ChallengeTransport? = null
    private var automaticRequests = false
    var syncActive = false
        private set
    var isSyncing = false
        private set
    var setupChecked = false
        private set
    var syncError: String? = null
        private set
    var lastSync: Double? = null
        private set
    /** Server rows the last successful sync could not read. */
    var skippedRows = 0
        private set
    var retryAfter: Double? = null
        private set
    private var failures = 0
    private var generation = UUID.randomUUID()
    private var hasActivated = false

    private fun setStore(value: ChallengeStore?) {
        store = value
        // Starting or adopting a challenge can change the zone that bounds days.
        selectedDay = if (followsToday) today else dates.calendar.startOfDay(selectedDay)
        refreshReminders()
        observeCompletion()
        changed()
    }

    private fun observeCompletion() {
        val challenge = challenge ?: return
        val record = store?.record ?: return
        val ledger = CelebrationLedger(File(directory, CelebrationLedger.fileName(challenge.ownerID)))
        ledger.observe(challenge, record.id, clock(), localCompletionDay, localExtrasDay)?.let {
            celebration = CelebrationEvent(it, clock())
        }
    }

    fun refreshReminders() {
        val date = clock()
        val nextDay = dates.calendar.addDays(date, 1)
        fun water(day: Double): Long? = challenge?.summary(day, date)?.takeIf { it.status != DayStatus.OUTSIDE_CHALLENGE }?.waterMillilitres
        reminders?.refresh(water(date), water(nextDay), dates.zone)
    }

    val canStartChallenge: Boolean get() = !syncActive || (setupChecked && !isSyncing && syncError == null)

    /** The one sync state. The chip and the Account screen are two wordings of it. */
    val syncState: SyncState
        get() {
            if (!syncActive) return SyncState.LocalOnly
            val pending = store?.pendingCount ?: 0
            syncError?.let { return SyncState.Unavailable(pending, it) }
            if (isSyncing) return SyncState.Checking(pending)
            if (pending > 0) return SyncState.SavedLocally(pending)
            val last = lastSync ?: return SyncState.AwaitingCheck
            return SyncState.Synced(last, store?.hasClockWarning ?: false)
        }

    /** Unreadable server rows are a note beside whatever the state is, never a failure. */
    val skippedNotice: String? get() = if (syncError == null) skippedRowsNotice(skippedRows) else null

    /** Fixtures configure a transport without the automatic requests. */
    fun configureSync(transport: ChallengeTransport, automatic: Boolean = false) {
        this.transport = transport
        automaticRequests = automatic
        syncActive = true
        setupChecked = false
        changed()
    }

    /** While the app is on screen: sync now and every 30 seconds, as the Apple apps do. */
    suspend fun syncWhileVisible() {
        while (true) {
            sync()
            delay(30_000)
        }
    }

    fun requestSync() {
        if (!syncActive || !automaticRequests) return
        scope.launch { sync() }
    }

    suspend fun sync(force: Boolean = false) {
        val transport = transport ?: return
        val owner = ownerID ?: return
        if (isSyncing || store == null) return
        if (!force && retryAfter?.let { clock() < it } == true) return
        val token = generation
        isSyncing = true
        changed()
        try {
            var remote = transport.fetchChallenge(owner)
            if (generation != token) return
            val localRecord = store?.record
            if (remote == null && localRecord != null) {
                transport.insertChallenge(localRecord)
                if (generation != token) return
                remote = transport.fetchChallenge(owner)
                if (generation != token) return
                if (remote == null) throw ChallengeSyncException(ChallengeSyncError.INVALID_RECORD)
            }
            var skipped = 0
            if (remote != null) {
                if (remote.ownerID != owner) throw ChallengeSyncException(ChallengeSyncError.WRONG_OWNER)
                val current = store ?: throw ChallengeStoreException(ChallengeStoreError.NOT_STARTED)
                current.record?.let { if (it != remote) throw ChallengeSyncException(ChallengeSyncError.CONFLICTING_CHALLENGE) }
                transport.upload(current.pending, owner)
                if (generation != token) return
                val fetched = transport.fetchEvents(owner, remote.id)
                if (generation != token) return
                // Only events that decoded are merged, so only they acknowledge pending uploads.
                transact { it.merge(remote, fetched.events) }
                skipped = fetched.skipped
            }
            setupChecked = true
            syncError = null
            lastSync = clock()
            skippedRows = skipped
            failures = 0
            retryAfter = null
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            if (generation != token) return
            setupChecked = false
            syncError = describe(error)
            failures = min(failures + 1, 8)
            retryAfter = clock() + min(900.0, 2.0.pow(failures) * 5)
        } finally {
            if (generation == token) isSyncing = false
            changed()
        }
    }

    val challenge: Challenge? get() = store?.challenge
    /** The challenge's own zone; before setup the device's zone only places the navigation date. */
    val dates: ChallengeDates get() = ChallengeDates(challenge?.zone ?: deviceZone())
    val summary: DailySummary? get() = challenge?.summary(selectedDay, now)
    val streaks: StreakSummary? get() = challenge?.streaks(now)
    val history: List<Activity> get() = challenge?.history(selectedDay)?.reversed() ?: emptyList()
    val today: Double get() = dates.calendar.startOfDay(now)
    val dayNumber: Int
        get() {
            val challenge = challenge ?: return 0
            return maxOf(0, dates.calendar.daysBetween(challenge.startDate, today).toInt() + 1)
        }
    val canEdit: Boolean
        get() {
            val summary = summary ?: return false
            if (summary.status == DayStatus.FUTURE || summary.status == DayStatus.OUTSIDE_CHALLENGE) return false
            return followsToday || isEditingHistory
        }
    val canUndo: Boolean get() = canEdit && summary?.activePours?.isNotEmpty() == true

    fun activate(ownerID: UUID?) {
        if (hasActivated && this.ownerID == ownerID) { refresh(); return }
        hasActivated = true
        generation = UUID.randomUUID()
        isSyncing = false
        setupChecked = false
        syncError = null
        lastSync = null
        skippedRows = 0
        retryAfter = null
        failures = 0
        this.ownerID = ownerID
        celebration = null
        setStore(null)
        errorMessage = null
        showToday()
        if (ownerID != null) {
            reload()
            requestSync()
        }
        changed()
    }

    fun reload() {
        val owner = ownerID ?: return
        try {
            setStore(ChallengeStore(owner, directory))
            errorMessage = null
        } catch (error: Exception) {
            setStore(null)
            errorMessage = "Local history could not be opened. It has not been reset. ${describe(error)}"
        }
        changed()
    }

    /**
     * After the account is deleted on the server: leave it, then remove this device's copies
     * of its history, pending queue and celebration ledger. Other accounts' files stay.
     */
    fun removeLocalData(ownerID: UUID) {
        if (this.ownerID == ownerID) activate(null)
        ChallengeStore.removeAccountFiles(ownerID, directory)
    }

    fun refresh() {
        now = clock()
        if (followsToday) selectedDay = today
        refreshReminders()
        changed()
    }

    fun showToday() {
        followsToday = true
        isEditingHistory = false
        refresh()
    }

    fun selectHistoryDay(date: Double) {
        refresh()
        val day = dates.calendar.startOfDay(date)
        val challenge = challenge ?: return
        if (day < challenge.startDate || day > today) return
        followsToday = false
        selectedDay = day
        isEditingHistory = false
        errorMessage = null
        changed()
    }

    fun enableCorrections() { isEditingHistory = true; changed() }
    fun dismissError() { errorMessage = null; changed() }
    fun clearCelebration() { celebration = null; changed() }

    fun startChallenge(date: LocalDate, zone: ZoneId) {
        refresh()
        if (!canStartChallenge) {
            errorMessage = "Check the server before setup. Existing local history can still be used offline."
            changed()
            return
        }
        val calendar = ChallengeCalendar(zone)
        if (date > calendar.localDate(now)) {
            errorMessage = "Choose today or an earlier start date."
            changed()
            return
        }
        if (store == null) return
        try {
            transact { it.start(calendar.startOf(date), zone) }
            errorMessage = null
            showToday()
            setupChecked = false
            requestSync()
        } catch (error: Exception) {
            errorMessage = describe(error)
        }
        changed()
    }

    fun addWater(amount: Long = 450) = record { Action.Pour(amount) }

    fun addCustomWater(text: String) {
        val amount = text.trim().toLongOrNull()
        if (amount == null || amount <= 0) {
            errorMessage = "Enter a positive whole amount in ml, such as 250."
            changed()
            return
        }
        addWater(amount)
    }

    fun undoWater() = record { Action.UndoLatestPour }

    fun toggle(habit: Habit) {
        refresh()
        record { summary -> Action.SetHabit(habit, !(summary?.completedHabits?.contains(habit) ?: false)) }
    }

    fun setDiet(state: DietState) = record { Action.SetDiet(state) }

    private fun <T> transact(operation: (ChallengeStore) -> T): T {
        if (ownerID == null) throw ChallengeStoreException(ChallengeStoreError.NOT_STARTED)
        val candidate = store ?: throw ChallengeStoreException(ChallengeStoreError.NOT_STARTED)
        val result = operation(candidate)
        setStore(candidate)
        return result
    }

    /** Every action derives from the just-loaded summary, never a rendered snapshot. */
    private fun record(derive: (DailySummary?) -> Action) {
        refresh()
        if (!canEdit || store == null) {
            errorMessage = "Select Edit this day before making a historical correction."
            changed()
            return
        }
        try {
            transact { candidate ->
                val fresh = candidate.challenge?.summary(selectedDay, now)
                if (fresh == null || fresh.status == DayStatus.FUTURE || fresh.status == DayStatus.OUTSIDE_CHALLENGE) {
                    throw ChallengeStoreException(ChallengeStoreError.NOT_STARTED)
                }
                val action = derive(fresh)
                if (action is Action.SetExtra) localExtrasDay = if (action.completed && selectedDay == today) today else null
                localCompletionDay = if (!fresh.isComplete && selectedDay == today) today else null
                candidate.record(action, selectedDay, now)
            }
            errorMessage = null
            requestSync()
        } catch (error: Exception) {
            errorMessage = "Could not save. Your previous history is intact. ${describe(error)}"
        } finally {
            localCompletionDay = null
            localExtrasDay = null
        }
        changed()
    }

    // MARK: Extras

    /** Still to do today, in creation order: what Manage extras lists and the cap counts. */
    val activeExtras: List<Extra> get() = challenge?.openExtras(now) ?: emptyList()
    val canAddExtra: Boolean get() = challenge != null && activeExtras.size < Challenge.MAXIMUM_ACTIVE_EXTRAS

    fun toggleExtra(id: UUID) {
        refresh()
        record { Action.SetExtra(id, !(it?.completedExtras?.contains(id) ?: false)) }
    }

    /** Each returns null once saved, otherwise the reason nothing was saved. */
    fun addExtra(title: String): String? = defineExtra(UUID.randomUUID(), title)
    fun renameExtra(id: UUID, title: String): String? = defineExtra(id, title)
    fun archiveExtra(id: UUID): String? = recordExtraSetting(Action.ArchiveExtra(id))

    private fun defineExtra(id: UUID, title: String): String? {
        val clean = Challenge.extraTitle(title) ?: return ChallengeError.INVALID_EXTRA_TITLE.message
        return recordExtraSetting(Action.DefineExtra(id, clean))
    }

    /** Adding, renaming and archiving belong to the challenge, so they are recorded on today. */
    private fun recordExtraSetting(action: Action): String? {
        refresh()
        if (store?.challenge == null) return ChallengeStoreError.NOT_STARTED.message
        return try {
            transact { candidate ->
                if (action is Action.DefineExtra &&
                    candidate.challenge?.allExtras?.firstOrNull { it.id == action.id && !it.isArchived }?.title == action.title
                ) return@transact
                candidate.record(action, now, now)
            }
            requestSync()
            null
        } catch (error: ChallengeException) {
            error.message
        } catch (error: Exception) {
            "Could not save. Your previous history is intact. ${describe(error)}"
        } finally {
            changed()
        }
    }

    companion object {
        /** Words a person can act on; anything else keeps its own message. */
        fun describe(error: Throwable): String = when (error) {
            is IOException -> if (error is NetworkException || error.message.isNullOrBlank() || isNetwork(error))
                "Can't reach the server. Check your internet connection and try again." else error.message!!
            else -> error.message ?: error.toString()
        }

        private fun isNetwork(error: IOException): Boolean =
            error is java.net.UnknownHostException || error is java.net.ConnectException ||
                error is java.net.SocketTimeoutException || error is javax.net.ssl.SSLException
    }
}

/** A request that never reached the server, or whose answer never arrived. */
class NetworkException(cause: Throwable) : IOException("Can't reach the server. Check your internet connection and try again.", cause)
