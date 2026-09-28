package net.mountanos.setbuddy.android.notifications

import android.content.Context

/** SharedPreferences-backed prefs, mirroring the iOS `NotificationSettings`/`UserDefaults` counterpart. */
data class NotificationPrefs(val dailyRemindersEnabled: Boolean, val hour: Int, val minute: Int)

object NotificationSettings {
    private const val PREFS_NAME = "notification_settings"
    private const val KEY_ENABLED = "daily_reminders_enabled"
    private const val KEY_HOUR = "hour"
    private const val KEY_MINUTE = "minute"

    fun load(context: Context): NotificationPrefs {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return NotificationPrefs(
            dailyRemindersEnabled = prefs.getBoolean(KEY_ENABLED, false),
            hour = prefs.getInt(KEY_HOUR, 8),
            minute = prefs.getInt(KEY_MINUTE, 0),
        )
    }

    fun save(context: Context, prefs: NotificationPrefs) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_ENABLED, prefs.dailyRemindersEnabled)
            .putInt(KEY_HOUR, prefs.hour)
            .putInt(KEY_MINUTE, prefs.minute)
            .apply()
    }
}
