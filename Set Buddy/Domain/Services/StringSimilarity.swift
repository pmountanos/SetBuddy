//
//  StringSimilarity.swift
//  Set Buddy
//

import Foundation

enum StringSimilarity {
    /// Levenshtein-distance-based similarity in `[0, 1]` (1 = identical, 0 = nothing in common). Two empty strings
    /// are treated as identical.
    nonisolated static func ratio(_ a: String, _ b: String) -> Double {
        let aChars = Array(a)
        let bChars = Array(b)
        let maxLen = max(aChars.count, bChars.count)
        guard maxLen > 0 else { return 1 }
        return 1.0 - Double(levenshteinDistance(aChars, bChars)) / Double(maxLen)
    }

    private static func levenshteinDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previousRow = Array(0 ... b.count)
        var currentRow = [Int](repeating: 0, count: b.count + 1)
        for i in 1 ... a.count {
            currentRow[0] = i
            for j in 1 ... b.count {
                if a[i - 1] == b[j - 1] {
                    currentRow[j] = previousRow[j - 1]
                } else {
                    currentRow[j] = 1 + min(previousRow[j - 1], previousRow[j], currentRow[j - 1])
                }
            }
            swap(&previousRow, &currentRow)
        }
        return previousRow[b.count]
    }
}
