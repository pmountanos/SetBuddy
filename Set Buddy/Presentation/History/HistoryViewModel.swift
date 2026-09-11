//
//  HistoryViewModel.swift
//  Set Buddy
//

import Foundation
import SwiftData

@MainActor
@Observable
final class HistoryViewModel {
    private let modelContext: ModelContext

    var rows: [HistoryCompletedRow] = []
    var errorMessage: String?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func refresh() {
        errorMessage = nil
        do {
            try ProgramRepository.addExerciseTemplatesIfMissing(modelContext: modelContext)
            rows = try HistoryRepository(modelContext: modelContext).completedRows()
        } catch {
            errorMessage = error.localizedDescription
            rows = []
        }
    }
}
