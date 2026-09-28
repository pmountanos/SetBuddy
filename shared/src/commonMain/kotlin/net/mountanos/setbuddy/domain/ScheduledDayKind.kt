package net.mountanos.setbuddy.domain

import kotlin.uuid.Uuid

/** What the program assigns to a single calendar date. */
sealed class ScheduledDayKind {
    data object Rest : ScheduledDayKind()

    /** The workout template/instance scheduled for that calendar day. */
    data class Workout(val workoutId: Uuid) : ScheduledDayKind()
}
