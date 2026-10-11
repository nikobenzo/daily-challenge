package app.dailychallenge.core

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import kotlin.math.floor

/**
 * Instants are seconds since 1 January 2001 UTC, as Swift's `Date` encodes them. Every
 * `day` and `recordedAt` on the wire uses this reference, so the rules keep the same
 * doubles the Mac and iPhone compare, instead of converting back and forth.
 */
object ChallengeTime {
    const val REFERENCE_UNIX_SECONDS = 978_307_200L

    fun fromUnix(seconds: Double): Double = seconds - REFERENCE_UNIX_SECONDS
    fun toUnix(reference: Double): Double = reference + REFERENCE_UNIX_SECONDS

    fun fromInstant(instant: Instant): Double =
        (instant.epochSecond - REFERENCE_UNIX_SECONDS).toDouble() + instant.nano / 1e9

    fun toInstant(reference: Double): Instant {
        val whole = floor(reference)
        val nanos = ((reference - whole) * 1e9).toLong().coerceIn(0, 999_999_999)
        return Instant.ofEpochSecond(whole.toLong() + REFERENCE_UNIX_SECONDS, nanos)
    }

    /** "2026-10-08T12:00:00Z" in reference seconds. */
    fun parse(iso: String): Double = fromInstant(Instant.parse(iso))

    fun now(): Double = fromUnix(System.currentTimeMillis() / 1000.0)
}

/**
 * The Gregorian calendar in one challenge's zone: every day boundary, streak, reminder and
 * displayed date uses it (Swift `Challenge.calendar(for:)`). A day starts at the zone's
 * first instant of that date, which is midnight unless a transition skips it.
 */
class ChallengeCalendar(val zone: ZoneId) {
    // Not LocalDate.ofInstant: that is Java 9, missing on Android 10.
    fun localDate(instant: Double): LocalDate = ChallengeTime.toInstant(instant).atZone(zone).toLocalDate()

    fun startOf(date: LocalDate): Double =
        (date.atStartOfDay(zone).toEpochSecond() - ChallengeTime.REFERENCE_UNIX_SECONDS).toDouble()

    fun startOfDay(instant: Double): Double = startOf(localDate(instant))

    fun addDays(instant: Double, days: Long): Double = startOf(localDate(instant).plusDays(days))

    /** The day containing `instant` as [start, end). */
    fun interval(instant: Double): Pair<Double, Double> {
        val date = localDate(instant)
        return startOf(date) to startOf(date.plusDays(1))
    }

    fun isSameDay(a: Double, b: Double): Boolean = localDate(a) == localDate(b)

    fun daysBetween(fromDay: Double, toDay: Double): Long =
        java.time.temporal.ChronoUnit.DAYS.between(localDate(fromDay), localDate(toDay))

    /** Seconds east of GMT at `instant`. */
    fun offsetSeconds(instant: Double): Int = zone.rules.getOffset(ChallengeTime.toInstant(instant)).totalSeconds

    companion object {
        val utc: ZoneId = ZoneOffset.UTC
    }
}
