package net.mountanos.setbuddy.domain

/** Orders workout templates for Program overview: Push 1, Pull 1, Legs 1, Push 2, Pull 2, Legs 2, then others by name. */
object WorkoutTemplateDisplaySort {
    private val canonical = listOf(
        "Push 1", "Pull 1", "Legs 1",
        "Push 2", "Pull 2", "Legs 2",
    )

    private fun normalized(name: String): String =
        name.trim().replace(" ", "").lowercase()

    /** Lower rank sorts earlier. Known cycle names first; everything else after, alphabetically. */
    fun rank(name: String): Pair<Int, String> {
        val norm = normalized(name)
        canonical.forEachIndexed { i, ref ->
            if (norm == normalized(ref)) return i to name
        }
        canonical.forEachIndexed { i, ref ->
            if (norm.startsWith(normalized(ref)) || name.contains(ref, ignoreCase = true)) return i to name
        }
        return 1_000 to name
    }

    val comparator: Comparator<String> = Comparator { a, b ->
        val (ra, na) = rank(a)
        val (rb, nb) = rank(b)
        if (ra != rb) ra.compareTo(rb) else na.compareTo(nb, ignoreCase = true)
    }
}
