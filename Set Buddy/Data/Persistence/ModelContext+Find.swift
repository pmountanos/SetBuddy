//
//  ModelContext+Find.swift
//  Set Buddy
//

import Foundation
import SwiftData

extension ModelContext {
    /// Fetches the first model matching `predicate` (nil if none), instead of `fetch(FetchDescriptor<T>())` + `.first(where:)`.
    func first<T: PersistentModel>(_ type: T.Type, matching predicate: Predicate<T>) throws -> T? {
        var descriptor = FetchDescriptor<T>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }
}
