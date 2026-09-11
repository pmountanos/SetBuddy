//
//  VolumeCalculator.swift
//  Set Buddy
//

import Foundation

enum VolumeCalculator {
    /// Total work for one set. When `repsArePerSide` is true, reps are performed on each side (e.g. DB), so volume doubles.
    nonisolated static func setVolume(weight: Double, reps: Int, repsArePerSide: Bool = false) -> Double {
        let base = max(0, weight) * Double(max(0, reps))
        return repsArePerSide ? base * 2 : base
    }

    nonisolated static func totalVolume<S: Sequence>(sets: S) -> Double where S.Element == (weight: Double, reps: Int, repsArePerSide: Bool) {
        sets.reduce(0) { $0 + setVolume(weight: $1.weight, reps: $1.reps, repsArePerSide: $1.repsArePerSide) }
    }
}
