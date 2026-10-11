package app.dailychallenge.core

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime

/** Device preferences, deliberately not part of the challenge record or sync. */
data class WaterReminderSettings(
    val enabled: Boolean = false,
    val intervalMinutes: Int = 90,
    val startMinute: Int = 9 * 60,
    val endMinute: Int = 21 * 60,
) {
    val isValid: Boolean
        get() = intervalMinutes in 15..240 && startMinute in 0..1439 && endMinute in startMinute..1439

    /** The same JSON the Apple apps keep in their defaults. */
    fun encoded(): String = Wire.text(JsonObject(linkedMapOf(
        "enabled" to JsonPrimitive(enabled), "intervalMinutes" to JsonPrimitive(intervalMinutes),
        "startMinute" to JsonPrimitive(startMinute), "endMinute" to JsonPrimitive(endMinute),
    )))

    companion object {
        fun decode(text: String?): WaterReminderSettings? = try {
            val values = Wire.json.parseToJsonElement(text ?: return null).jsonObject
            WaterReminderSettings(
                Wire.boolOf(values["enabled"], "enabled"), Wire.longOf(values["intervalMinutes"], "interval").toInt(),
                Wire.longOf(values["startMinute"], "start").toInt(), Wire.longOf(values["endMinute"], "end").toInt(),
            )
        } catch (_: Exception) {
            null
        }
    }
}

/**
 * Calendar slots anchored to the window start, inclusive of the end, as wall times in the
 * challenge's zone (Swift `WaterReminderPlanner`). Missing DST wall times are skipped;
 * repeated wall times occur once (first occurrence).
 */
class WaterReminderPlanner(zone: ZoneId, private val clock: () -> Double = ChallengeTime::now) {
    val calendar = ChallengeCalendar(zone)

    fun upcoming(settings: WaterReminderSettings, through: Double, waterMillilitres: (Double) -> Long?): List<Double> {
        if (!settings.enabled || !settings.isValid) return emptyList()
        val now = clock()
        var date = calendar.localDate(now)
        val dates = ArrayList<Double>()
        while (calendar.startOf(date) <= through) {
            val water = waterMillilitres(calendar.startOf(date))
            if (water != null && water < 4_000) {
                for (minute in settings.startMinute..settings.endMinute step settings.intervalMinutes) {
                    val wall = LocalDateTime.of(date, LocalTime.of(minute / 60, minute % 60))
                    if (calendar.zone.rules.getValidOffsets(wall).isEmpty()) continue
                    val instant = ChallengeTime.fromInstant(ZonedDateTime.ofLocal(wall, calendar.zone, null).toInstant())
                    if (instant > now && instant <= through) dates.add(instant)
                }
            }
            date = date.plusDays(1)
        }
        return dates
    }
}

enum class NotificationPermission { NOT_DETERMINED, DENIED, ALLOWED, UNKNOWN }

/** The platform's notification side: Android alarms and notifications, or a fixture. */
interface ReminderScheduler {
    fun permission(): NotificationPermission
    /** Replaces every pending water reminder this app scheduled with `dates`. */
    fun replace(dates: List<Double>, zone: ZoneId)
    /** Removes every pending water reminder this app scheduled. */
    fun cancel()
}

/** Device-local settings storage (SharedPreferences on Android). */
interface KeyValueStore {
    fun getString(key: String): String?
    fun putString(key: String, value: String?)
}

class MemoryKeyValueStore : KeyValueStore {
    private val values = HashMap<String, String>()
    override fun getString(key: String) = values[key]
    override fun putString(key: String, value: String?) { if (value == null) values.remove(key) else values[key] = value }
}

/**
 * Water reminders on this device (Swift `WaterReminderController` with the iPhone's queued
 * policy): every remaining slot of today and tomorrow is handed to the system, because a
 * stopped app cannot schedule the next one in time. Re-planned whenever the app learns a
 * new total. Android alarms are set synchronously, so there is no reconcile queue.
 */
class WaterReminderController(
    private val defaults: KeyValueStore,
    private val scheduler: ReminderScheduler,
    val wording: DeviceWording,
    private val clock: () -> Double = ChallengeTime::now,
) {
    var settings: WaterReminderSettings = WaterReminderSettings.decode(defaults.getString(KEY))?.takeIf { it.isValid }
        ?: WaterReminderSettings()
        private set
    var permission = NotificationPermission.UNKNOWN
        private set
    var errorMessage: String? = null
        private set
    var scheduledDates: List<Double> = emptyList()
        private set
    var zone: ZoneId = ZoneId.systemDefault()
        private set
    private var waterByDay: Map<Double, Long> = emptyMap()
    var onChange: () -> Unit = {}

    private val calendar get() = ChallengeCalendar(zone)
    private val water: Long? get() = waterByDay[calendar.startOfDay(clock())]

    val status: String
        get() = when (permission) {
            NotificationPermission.NOT_DETERMINED -> "Permission not determined. Turn reminders off and on to allow notifications."
            NotificationPermission.DENIED -> "Notifications are off for this app. Open ${wording.notificationSettings}."
            NotificationPermission.UNKNOWN -> "Checking notification permission."
            NotificationPermission.ALLOWED -> when {
                !settings.enabled -> "Permission allowed · Reminders off on this ${wording.device}."
                water == null -> "Permission allowed · Waiting for a local challenge."
                water!! >= 4_000 -> "Permission allowed · Today's water goal met."
                else -> "Permission allowed · Reminders enabled on this ${wording.device}. Delivery depends on ${wording.system} and ${wording.quietMode}."
            }
        }

    fun update(next: WaterReminderSettings) {
        if (!next.isValid) return
        settings = next
        defaults.putString(KEY, next.encoded())
        reconcile()
    }

    fun refresh(waterMillilitres: Long?, nextDayWaterMillilitres: Long?, zone: ZoneId) {
        this.zone = zone
        val day = calendar.startOfDay(clock())
        val next = calendar.addDays(day, 1)
        waterByDay = buildMap {
            waterMillilitres?.let { put(day, it) }
            nextDayWaterMillilitres?.let { put(next, it) }
        }
        reconcile()
    }

    /** Re-reads the permission, for instance after the person changed it in Settings. */
    fun reconcile() {
        permission = scheduler.permission()
        val now = clock()
        val planned = WaterReminderPlanner(zone) { now }
            .upcoming(settings, now + 48 * 3_600) { waterByDay[it] }.take(QUEUED_LIMIT)
        val desired = if (permission == NotificationPermission.ALLOWED) planned else emptyList()
        try {
            if (desired.isEmpty()) scheduler.cancel() else if (desired != scheduledDates) scheduler.replace(desired, zone)
            scheduledDates = desired
            errorMessage = null
        } catch (error: Exception) {
            scheduledDates = emptyList()
            errorMessage = "Could not schedule water reminder: ${error.message}"
        }
        onChange()
    }

    companion object {
        const val KEY = "water-reminders.device.v1"
        /** Alarms are numbered below this bound. */
        const val QUEUED_LIMIT = 48
    }
}
