package app.dailychallenge.core

import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.abs

/** Display and navigation dates in one challenge's own zone (Swift `ChallengeDates`). Weeks start on Monday. */
class ChallengeDates(val zone: ZoneId, private val locale: Locale = Locale.getDefault()) {
    val calendar = ChallengeCalendar(zone)

    fun label(instant: Double, pattern: String = "EEE, d MMM"): String =
        DateTimeFormatter.ofPattern(pattern, locale).withZone(zone).format(ChallengeTime.toInstant(instant))

    companion object {
        /** "New York", "Jersey", "GMT": the readable last part of the identifier. */
        fun city(zone: ZoneId): String = zone.id.substringAfterLast('/').replace('_', ' ')

        /** "GMT+1", "GMT−4", "GMT+5:30", or "GMT" at the given instant. */
        fun offset(zone: ZoneId, at: Double): String {
            val seconds = zone.rules.getOffset(ChallengeTime.toInstant(at)).totalSeconds
            if (seconds == 0) return "GMT"
            val minutes = abs(seconds) / 60
            val sign = if (seconds < 0) "−" else "+"
            return "GMT$sign${minutes / 60}" + if (minutes % 60 == 0) "" else ":%02d".format(minutes % 60)
        }
    }
}

/**
 * Canonical zones searchable by city, region or zone name and grouped by region, for setup
 * (Swift `TimeZoneChoices`). The platform supplies the identifiers it knows.
 */
class TimeZoneChoices(identifiers: Collection<String>, private val locale: Locale = Locale.getDefault()) {
    data class Group(val region: String, val zones: List<ZoneId>)

    val all: List<ZoneId> = identifiers.mapNotNull(Challenge::canonicalZone).distinctBy { it.id }
        .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { ChallengeDates.city(it) })

    /** Localized names are looked up once, not on every keystroke. */
    private val searchable: List<Pair<ZoneId, List<String>>> = all.map { zone ->
        zone to listOf(
            zone.id.replace('_', ' '),
            zone.getDisplayName(TextStyle.FULL, locale),
            java.util.TimeZone.getTimeZone(zone).getDisplayName(false, java.util.TimeZone.LONG, locale),
        )
    }

    fun groups(query: String): List<Group> {
        val words = query.split(Regex("\\s+")).filter { it.isNotEmpty() }
        val matches = searchable.filter { (_, texts) ->
            words.all { word -> texts.any { it.contains(word, ignoreCase = true) } }
        }.map { it.first }
        return matches.groupBy(::region).toSortedMap().map { (region, zones) -> Group(region, zones) }
    }

    companion object {
        /** "New York · GMT−4" */
        fun title(zone: ZoneId, at: Double): String = "${ChallengeDates.city(zone)} · ${ChallengeDates.offset(zone, at)}"

        private fun region(zone: ZoneId): String = zone.id.split('/').let { if (it.size > 1) it[0] else "Other" }
    }
}
