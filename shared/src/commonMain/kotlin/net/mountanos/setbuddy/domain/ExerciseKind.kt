package net.mountanos.setbuddy.domain

/** What an exercise logs: weight/reps (default) or minutes/max heart rate. */
enum class ExerciseKind(val rawValue: String) {
    Strength("strength"),
    Cardio("cardio");

    companion object {
        /** Unknown/legacy values read as [Strength], matching the column default. */
        fun fromRaw(raw: String?): ExerciseKind = entries.firstOrNull { it.rawValue == raw } ?: Strength
    }
}
