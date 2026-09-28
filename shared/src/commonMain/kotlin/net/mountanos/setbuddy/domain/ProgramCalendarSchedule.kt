package net.mountanos.setbuddy.domain

/**
 * Program schedule stored as explicit calendar dates (not abstract weekdays).
 * Each key is one calendar day; the value is rest or a specific workout.
 */
class ProgramCalendarSchedule(days: Map<CalendarDate, ScheduledDayKind> = emptyMap()) {
    private val days: MutableMap<CalendarDate, ScheduledDayKind> = days.toMutableMap()

    /**
     * How this date is scheduled, if the program defines it.
     * `null` means this calendar day is outside defined schedule data (import range, program bounds, etc.).
     */
    fun scheduledKind(date: CalendarDate): ScheduledDayKind? = days[date]

    fun set(kind: ScheduledDayKind, date: CalendarDate) {
        days[date] = kind
    }

    fun remove(date: CalendarDate) {
        days.remove(date)
    }

    val allEntries: List<Pair<CalendarDate, ScheduledDayKind>>
        get() = days.keys.sorted().mapNotNull { date -> days[date]?.let { date to it } }
}
