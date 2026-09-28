package net.mountanos.setbuddy.domain

import kotlinx.datetime.DatePeriod
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.plus
import kotlinx.datetime.toLocalDateTime

/**
 * A calendar day in the user's locale, independent of time-of-day.
 * Used as the canonical key for program schedule entries.
 */
data class CalendarDate(
    val year: Int,
    /** 1...12 */
    val month: Int,
    /** 1...31 */
    val day: Int,
) : Comparable<CalendarDate> {

    fun toLocalDate(): LocalDate = LocalDate(year, month, day)

    /** Adds [days] to this calendar date. */
    fun addingDays(days: Int): CalendarDate {
        val next = toLocalDate().plus(DatePeriod(days = days))
        return from(next)
    }

    override fun compareTo(other: CalendarDate): Int {
        if (year != other.year) return year.compareTo(other.year)
        if (month != other.month) return month.compareTo(other.month)
        return day.compareTo(other.day)
    }

    companion object {
        fun from(localDate: LocalDate): CalendarDate =
            CalendarDate(localDate.year, localDate.monthNumber, localDate.dayOfMonth)

        /** The current calendar date in [timeZone] (defaults to the device's current time zone). */
        fun today(timeZone: TimeZone = TimeZone.currentSystemDefault()): CalendarDate {
            val instant = kotlinx.datetime.Clock.System.now()
            val local = instant.toLocalDateTime(timeZone)
            return CalendarDate(local.year, local.monthNumber, local.dayOfMonth)
        }
    }
}
