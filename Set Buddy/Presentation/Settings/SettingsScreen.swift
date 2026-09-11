//
//  SettingsScreen.swift
//  Set Buddy
//

import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private var xlsxContentType: UTType {
    if let t = UTType(filenameExtension: "xlsx") {
        return t
    }
    return .data
}

struct SettingsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var viewModel = SettingsViewModel()
    @State private var showImporter = false

    var body: some View {
        @Bindable var viewModel = viewModel
        @Bindable var notifications = viewModel.notifications
        @Bindable var importer = viewModel.importer
        @Bindable var exporter = viewModel.exporter
        return NavigationStack {
            Form {
                Section {
                    Text(
                        "Set Buddy uses one active training program. Build it on the Program tab (Start over there resets to a fresh starter), or import a spreadsheet here. Replacing the program clears in‑progress workouts; completed sessions remain in History."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("How it works")
                }

                Section {
                    Toggle("Daily plan reminder", isOn: $notifications.dailyNotificationsEnabled)

                    if notifications.dailyNotificationsEnabled {
                        DatePicker(
                            "Reminder time",
                            selection: $notifications.notificationReminderTime,
                            displayedComponents: [.hourAndMinute]
                        )
                    }

                    if notifications.notificationShowAllowButton {
                        Button("Allow notifications") {
                            Task {
                                await notifications.requestAuthorizationAndReschedule(modelContext: modelContext)
                            }
                        }
                    }

                    if notifications.notificationShowOpenSettingsButton {
                        Button("Open system settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }

                    if !notifications.notificationAuthorizationExplanation.isEmpty {
                        Text(notifications.notificationAuthorizationExplanation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text(
                        "One reminder per day at the time you choose. The message matches your program: workout day vs rest day. Turn off the toggle to stop scheduling reminders (already delivered notifications are unchanged)."
                    )
                }

                Section {
                    Picker(
                        "Upcoming schedule list",
                        selection: Binding(
                            get: { viewModel.upcomingScheduleListDayCount },
                            set: { viewModel.setUpcomingScheduleListDayCount($0) }
                        )
                    ) {
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("21 days").tag(21)
                    }
                    .accessibilityIdentifier("settingsProgramScheduleRangePicker")

                    Button {
                        showImporter = true
                    } label: {
                        Label("Import program (.xlsx)", systemImage: "square.and.arrow.down")
                    }
                    .disabled(importer.isImporting)

                    if importer.isImporting {
                        HStack {
                            ProgressView()
                            Text("Importing…")
                        }
                    }

                    if let message = importer.importMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let err = importer.importError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Program")
                } footer: {
                    Text(
                        "“Upcoming schedule list” controls how many days appear on the Program tab. Pick a file, then choose which day in the workbook is next and the calendar day that maps to it. The schedule continues in worksheet tab order. Row 1 can name columns: exercise, Notes, and Per side (order flexible). In each row, mark per side with x, ✓, yes, 1, or TRUE where that column’s header says Per side / Per set. If there are no headers, the app assumes B = note and C = per side. Rest: empty sheet or a name containing “Rest”. Import clears any in‑progress workout. Note: Total work history (completed sessions and volume) is kept when you import a new program."
                    )
                }

                Section {
                    Button {
                        exporter.exportProgram(modelContext: modelContext)
                    } label: {
                        Label("Export program", systemImage: "square.and.arrow.up")
                    }
                    .disabled(importer.isImporting || exporter.isExporting)
                    .accessibilityIdentifier("settingsExportProgramButton")

                    Button {
                        exporter.exportHistory(modelContext: modelContext)
                    } label: {
                        Label("Export workout history", systemImage: "square.and.arrow.up")
                    }
                    .disabled(importer.isImporting || exporter.isExporting)
                    .accessibilityIdentifier("settingsExportHistoryButton")

                    if let err = exporter.exportError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Export")
                } footer: {
                    Text(
                        "Spreadsheet exports use the date and time in the file name (Set_Buddy_Program_… or Set_Buddy_History_…). Program workbooks use one sheet per workout with the same columns as import (Exercise_Name, Notes, Per side). The CSV program export also includes the calendar schedule. History includes every completed set. Prefer .xlsx; if that fails, a .csv file is offered instead."
                    )
                }
            }
            .navigationTitle("Settings")
            .task {
                await notifications.refreshAuthorizationStatus()
            }
            .onChange(of: notifications.dailyNotificationsEnabled) { _, _ in
                DailyNotificationScheduler.requestReschedule(modelContext: modelContext)
            }
            .onChange(of: notifications.notificationReminderTime) { _, _ in
                DailyNotificationScheduler.requestReschedule(modelContext: modelContext)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task {
                    await notifications.refreshAuthorizationStatus()
                    DailyNotificationScheduler.requestReschedule(modelContext: modelContext)
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [xlsxContentType],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importer.stageImportFromPickedFile(url: url, modelContext: modelContext)
                case .failure(let error):
                    Task { @MainActor in
                        importer.importError = error.localizedDescription
                    }
                }
            }
            .sheet(item: $exporter.exportPresentation) { item in
                ShareExportSheet(items: [item.url]) {
                    exporter.finishExportSharing()
                }
            }
            .sheet(isPresented: $importer.importStagingPresented) {
                NavigationStack {
                    Form {
                        if !importer.stagedCycleDayLabels.isEmpty {
                            Picker("Next workout in cycle", selection: $importer.stagedSelectedCycleDayIndex) {
                                ForEach(Array(importer.stagedCycleDayLabels.enumerated()), id: \.offset) { pair in
                                    Text(pair.element).tag(pair.offset)
                                }
                            }
                        }
                        DatePicker(
                            "First day on calendar",
                            selection: $importer.importScheduleStartDate,
                            displayedComponents: [.date]
                        )

                        if importer.stagedAutoCarryoverCount > 0 || !importer.stagedCarryoverSuggestions.isEmpty {
                            Section {
                                if importer.stagedAutoCarryoverCount > 0 {
                                    Text(
                                        "\(importer.stagedAutoCarryoverCount) exercise\(importer.stagedAutoCarryoverCount == 1 ? "" : "s") matched by name — reference weights carry over automatically."
                                    )
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                }
                                ForEach(importer.stagedCarryoverSuggestions) { suggestion in
                                    Toggle(isOn: Binding(
                                        get: { importer.stagedConfirmedSuggestionIds.contains(suggestion.id) },
                                        set: { isOn in
                                            if isOn {
                                                importer.stagedConfirmedSuggestionIds.insert(suggestion.id)
                                            } else {
                                                importer.stagedConfirmedSuggestionIds.remove(suggestion.id)
                                            }
                                        }
                                    )) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(suggestion.newExercise.exerciseName)
                                            Text("Carry over weights from “\(suggestion.oldExerciseName)”?")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            } header: {
                                Text("Carry over previous weights")
                            } footer: {
                                Text("These new exercise names are close to ones in your current program but not identical. Turn off any that aren’t actually the same exercise.")
                            }
                        }
                    }
                    .navigationTitle("Import program")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                importer.cancelStagedImport()
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Import") {
                                Task {
                                    await importer.confirmStagedImport(modelContext: modelContext)
                                }
                            }
                            .disabled(importer.isImporting || importer.stagedCycleDayLabels.isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}

#Preview {
    SettingsScreen()
        .modelContainer(for: PersistedProgram.self, inMemory: true)
}
