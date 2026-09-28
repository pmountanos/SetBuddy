package net.mountanos.setbuddy.android.settings

import android.content.Context

/** Ported from `Platform/ProgramSchedulePreviewDaysSetting.swift`. */
object ProgramSchedulePreviewDaysSetting {
    val choices = listOf(7, 14, 21)
    private const val DEFAULT_DAYS = 14
    private const val PREFS_NAME = "program_schedule_preview_days"
    private const val KEY_DAYS = "days"

    fun load(context: Context): Int {
        val value = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getInt(KEY_DAYS, 0)
        return if (value in choices) value else DEFAULT_DAYS
    }

    fun save(context: Context, days: Int) {
        if (days !in choices) return
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit().putInt(KEY_DAYS, days).apply()
    }
}
