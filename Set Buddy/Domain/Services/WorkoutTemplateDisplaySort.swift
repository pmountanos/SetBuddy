//
//  WorkoutTemplateDisplaySort.swift
//  Set Buddy
//

import Foundation

/// Orders workout templates for Program overview: Push 1, Pull 1, Legs 1, Push 2, Pull 2, Legs 2, then others by name.
enum WorkoutTemplateDisplaySort {
    private static let canonical: [String] = [
        "Push 1", "Pull 1", "Legs 1",
        "Push 2", "Pull 2", "Legs 2",
    ]

    private static func normalized(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    /// Lower rank sorts earlier. Known cycle names first; everything else after, alphabetically.
    static func rank(_ name: String) -> (Int, String) {
        let norm = normalized(name)
        for (i, ref) in canonical.enumerated() {
            if norm == normalized(ref) {
                return (i, name)
            }
        }
        for (i, ref) in canonical.enumerated() {
            if norm.hasPrefix(normalized(ref)) || name.localizedCaseInsensitiveContains(ref) {
                return (i, name)
            }
        }
        return (1_000, name)
    }

    static func compare(_ a: String, _ b: String) -> Bool {
        let ra = rank(a)
        let rb = rank(b)
        if ra.0 != rb.0 { return ra.0 < rb.0 }
        return ra.1.localizedCaseInsensitiveCompare(rb.1) == .orderedAscending
    }
}
