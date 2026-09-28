package net.mountanos.setbuddy.domain

import kotlin.math.max
import kotlin.math.min

object StringSimilarity {
    /**
     * Levenshtein-distance-based similarity in `[0, 1]` (1 = identical, 0 = nothing in common). Two empty strings
     * are treated as identical.
     */
    fun ratio(a: String, b: String): Double {
        val maxLen = max(a.length, b.length)
        if (maxLen == 0) return 1.0
        return 1.0 - levenshteinDistance(a, b).toDouble() / maxLen.toDouble()
    }

    private fun levenshteinDistance(a: String, b: String): Int {
        if (a.isEmpty()) return b.length
        if (b.isEmpty()) return a.length
        var previousRow = IntArray(b.length + 1) { it }
        var currentRow = IntArray(b.length + 1)
        for (i in 1..a.length) {
            currentRow[0] = i
            for (j in 1..b.length) {
                currentRow[j] = if (a[i - 1] == b[j - 1]) {
                    previousRow[j - 1]
                } else {
                    1 + min(min(previousRow[j - 1], previousRow[j]), currentRow[j - 1])
                }
            }
            val tmp = previousRow
            previousRow = currentRow
            currentRow = tmp
        }
        return previousRow[b.length]
    }
}
