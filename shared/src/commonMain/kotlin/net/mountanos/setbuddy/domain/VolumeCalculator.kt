package net.mountanos.setbuddy.domain

object VolumeCalculator {
    /** Total work for one set. When [repsArePerSide] is true, reps are performed on each side (e.g. DB), so volume doubles. */
    fun setVolume(weight: Double, reps: Int, repsArePerSide: Boolean = false): Double {
        val base = maxOf(0.0, weight) * maxOf(0, reps)
        return if (repsArePerSide) base * 2 else base
    }

    data class Set(val weight: Double, val reps: Int, val repsArePerSide: Boolean)

    fun totalVolume(sets: Iterable<Set>): Double =
        sets.fold(0.0) { acc, s -> acc + setVolume(s.weight, s.reps, s.repsArePerSide) }
}
