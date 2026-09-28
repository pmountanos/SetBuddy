package net.mountanos.setbuddy.android.notifications

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import net.mountanos.setbuddy.domain.CalendarDate
import net.mountanos.setbuddy.domain.TodayScheduleResolver
import net.mountanos.setbuddy.domain.TodayScheduleStatus
import net.mountanos.setbuddy.shared.data.ProgramRepository
import java.util.Calendar as JCalendar

/**
 * Schedules one local notification per calendar day for the next [horizonDays], using the same date-based
 * schedule as the Today screen. Ported from `Platform/Notifications/DailyNotificationScheduler.swift`.
 */
class DailyNotificationScheduler(
    private val context: Context,
    private val programRepository: ProgramRepository,
) {
    private val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    private val identifierPrefix = "net.mountanos.setbuddy.schedule."

    /** Cancels+rebuilds all pending alarms. Call after any mutation that affects the schedule or notification prefs. */
    fun requestReschedule(horizonDays: Int = 14) {
        cancelAll(horizonDays)

        val prefs = NotificationSettings.load(context)
        if (!prefs.dailyRemindersEnabled) return

        val program = programRepository.activeProgram()
        val schedule = program?.let { programRepository.calendarSchedule(it) }
        val titles = program?.let { programRepository.workoutTitles(it) } ?: emptyMap()
        val today = CalendarDate.today()

        for (offset in 0 until horizonDays) {
            val date = today.addingDays(offset)
            val status = if (schedule == null) {
                TodayScheduleStatus.NoProgram
            } else {
                TodayScheduleResolver.status(date, schedule, titles)
            }
            val (title, body) = contentFor(status)
            scheduleOne(date, prefs.hour, prefs.minute, title, body)
        }
    }

    private fun scheduleOne(date: CalendarDate, hour: Int, minute: Int, title: String, body: String) {
        val trigger = JCalendar.getInstance().apply {
            set(date.year, date.month - 1, date.day, hour, minute, 0)
            set(JCalendar.MILLISECOND, 0)
        }
        val requestCode = alarmRequestCode(date)
        val intent = Intent(context, DailyReminderReceiver::class.java).apply {
            putExtra(DailyReminderReceiver.EXTRA_TITLE, title)
            putExtra(DailyReminderReceiver.EXTRA_BODY, body)
            putExtra(DailyReminderReceiver.EXTRA_NOTIFICATION_ID, requestCode)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        if (trigger.timeInMillis <= System.currentTimeMillis()) return
        try {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger.timeInMillis, pendingIntent)
        } catch (_: SecurityException) {
            // Exact-alarm permission not granted; skip silently (mirrors iOS's guard on notification authorization).
        }
    }

    private fun cancelAll(horizonDays: Int) {
        val today = CalendarDate.today()
        for (offset in 0 until horizonDays) {
            val date = today.addingDays(offset)
            val requestCode = alarmRequestCode(date)
            val intent = Intent(context, DailyReminderReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                context, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            alarmManager.cancel(pendingIntent)
        }
    }

    private fun alarmRequestCode(date: CalendarDate): Int =
        (identifierPrefix + "${date.year}-${date.month}-${date.day}").hashCode()

    private fun contentFor(status: TodayScheduleStatus): Pair<String, String> = when (status) {
        is TodayScheduleStatus.NoProgram -> "Set Buddy" to "Set up your training program in the app."
        is TodayScheduleStatus.DayNotScheduled -> "Set Buddy" to "Open the app to see your plan."
        is TodayScheduleStatus.RestDay -> "Rest day" to "Today is a scheduled rest day."
        is TodayScheduleStatus.WorkoutDay -> "Workout day" to "Today: ${status.title}."
        is TodayScheduleStatus.WorkoutInProgress -> "Workout day" to "Today: ${status.title}."
        is TodayScheduleStatus.WorkoutAlreadyFinished -> "Set Buddy" to "You're all set for today's planned session."
    }
}
