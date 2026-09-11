//
//  ExerciseNoteSheet.swift
//  Set Buddy
//

import SwiftUI

/// Add or edit free-form notes for an exercise (Cancel / Save).
struct ExerciseNoteEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @State private var draft: String
    let onSave: (String) -> Void

    init(title: String, initialNote: String, onSave: @escaping (String) -> Void) {
        self.title = title
        _draft = State(initialValue: initialNote)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $draft)
                .font(.body)
                .padding(8)
                .accessibilityIdentifier("exerciseNoteEditor")
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave(draft)
                            dismiss()
                        }
                        .accessibilityIdentifier("exerciseNoteSaveButton")
                    }
                }
        }
    }
}
