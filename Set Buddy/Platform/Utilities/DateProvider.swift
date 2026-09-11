//
//  DateProvider.swift
//  Set Buddy
//

import Foundation

protocol DateProviding: Sendable {
    nonisolated var now: Date { get }
}

struct SystemDateProvider: DateProviding {
    nonisolated init() {}

    nonisolated var now: Date { Date() }
}
