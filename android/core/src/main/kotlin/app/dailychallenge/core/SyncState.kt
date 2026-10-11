package app.dailychallenge.core

import java.util.UUID

/** The few words that name the device in status text (Swift `DeviceWording`). */
data class DeviceWording(
    /** "phone": as in "Saved on this phone". */
    val device: String,
    /** "Android": as in "Delivery depends on Android and Do Not Disturb". */
    val system: String,
    /** Where a person turns this app's notifications back on. */
    val notificationSettings: String,
    /** Where a person checks the device clock. */
    val dateTimeSettings: String,
    /** What can hold a notification back: "Focus" on Apple devices. */
    val quietMode: String,
) {
    companion object {
        val android = DeviceWording(
            device = "phone", system = "Android",
            notificationSettings = "Settings > Apps > Daily Challenge > Notifications",
            dateTimeSettings = "Settings > System > Date & time",
            quietMode = "Do Not Disturb",
        )
    }
}

/** The one sync state (Swift `SyncState`); the chip and the Account screen are two wordings of it. */
sealed interface SyncState {
    data object LocalOnly : SyncState
    data class Unavailable(val pending: Int, val error: String) : SyncState
    data class Checking(val pending: Int) : SyncState
    data class SavedLocally(val pending: Int) : SyncState
    data object AwaitingCheck : SyncState
    data class Synced(val at: Double, val clockWarning: Boolean) : SyncState

    /** Plain words for the Account screen; never adds information the chip lacks. */
    fun plainText(wording: DeviceWording, time: (Double) -> String): String {
        val device = wording.device
        return when (this) {
            LocalOnly -> "Saved on this $device only, not connected to the server"
            is Unavailable -> "Can't reach the server, your entries are safe"
            is Checking -> if (pending > 0) "Syncing, ${changes(pending)} waiting" else "Syncing"
            is SavedLocally -> "Saved on this $device, ${changes(pending)} waiting"
            AwaitingCheck -> "Saved on this $device, checking the server shortly"
            is Synced -> "Up to date, checked ${time(at)}"
        }
    }

    fun clockWarningText(wording: DeviceWording): String? {
        if (this !is Synced || !clockWarning) return null
        return "This ${wording.device}'s clock looks ahead of the server; check ${wording.dateTimeSettings} if this keeps happening"
    }

    companion object {
        private fun changes(count: Int) = if (count == 1) "1 change" else "$count changes"
    }
}

/** An account's fetched history. Rows the app could not read are counted and left out. */
data class RemoteEvents(val events: List<ChallengeEvent>, val skipped: Int = 0)

/** Reported beside the sync state, not as a failure: everything else still synced. */
fun skippedRowsNotice(count: Int): String? = when {
    count <= 0 -> null
    count == 1 -> "1 entry from the server could not be read and was skipped"
    else -> "$count entries from the server could not be read and were skipped"
}

/** The seam shared by the Supabase adapter and offline fixtures (Swift `ChallengeTransport`). */
interface ChallengeTransport {
    suspend fun fetchChallenge(ownerID: UUID): ChallengeRecord?
    suspend fun insertChallenge(record: ChallengeRecord)
    suspend fun upload(events: List<ChallengeEvent>, ownerID: UUID)
    suspend fun fetchEvents(ownerID: UUID, challengeID: UUID): RemoteEvents
}
