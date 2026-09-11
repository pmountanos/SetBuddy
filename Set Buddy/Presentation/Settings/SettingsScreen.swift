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
                    Toggle("Daily plan reminder", isOn: $viewModel.dailyNotificationsEnabled)

                    if viewModel.dailyNotificationsEnabled {
                        DatePicker(
                            "Reminder time",
                            selection: $viewModel.notificationReminderTime,
                            displayedComponents: [.hourAndMinute]
                        )
                    }

                    if viewModel.notificationShowAllowButton {
                        Button("Allow notifications") {
                            Task {
                                await viewModel.requestNotificationAuthorizationAndReschedule(modelContext: modelContext)
                            }
                        }
                    }

                    if viewModel.notificationShowOpenSettingsButton {
                        Button("Open system settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }

                    if !viewModel.notificationAuthorizationExplanation.isEmpty {
                        Text(viewModel.notificationAuthorizationExplanation)
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
                    .disabled(viewModel.isImporting)

                    if viewModel.isImporting {
                        HStack {
                            ProgressView()
                            Text("Importing…")
                        }
                    }

                    if let message = viewModel.importMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let err = viewModel.importError {
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
                        viewModel.exportProgram(modelContext: modelContext)
                    } label: {
                        Label("Export program", systemImage: "square.and.arrow.up")
                    }
                    .disabled(viewModel.isImporting || viewModel.isExporting)
                    .accessibilityIdentifier("settingsExportProgramButton")

                    Button {
                        viewModel.exportHistory(modelContext: modelContext)
                    } label: {
                        Label("Export workout history", systemImage: "square.and.arrow.up")
                    }
                    .disabled(viewModel.isImporting || viewModel.isExporting)
                    .accessibilityIdentifier("settingsExportHistoryButton")

                    if let err = viewModel.exportError {
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
                await viewModel.refreshNotificationAuthorizationStatus()
            }
            .onChange(of: viewModel.dailyNotificationsEnabled) { _, _ in
                Task { await viewModel.rescheduleNotifications(modelContext: modelContext) }
            }
            .onChange(of: viewModel.notificationReminderTime) { _, _ in
                Task { await viewModel.rescheduleNotifications(modelContext: modelContext) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task {
                    await viewModel.refreshNotificationAuthorizationStatus()
                    await viewModel.rescheduleNotifications(modelContext: modelContext)
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
                    viewModel.stageImportFromPickedFile(url: url)
                case .failure(let error):
                    Task { @MainActor in
                        viewModel.importError = error.localizedDescription
                    }
                }
            }
            .sheet(item: $viewModel.exportPresentation) { item in
                ShareExportSheet(items: [item.url]) {
                    viewModel.finishExportSharing()
                }
            }
            .sheet(isPresented: $viewModel.importStagingPresented) {
                NavigationStack {
                    Form {
                        if !viewModel.stagedCycleDayLabels.isEmpty {
                            Picker("Next workout in cycle", selection: $viewModel.stagedSelectedCycleDayIndex) {
                                ForEach(Array(viewModel.stagedCycleDayLabels.enumerated()), id: \.offset) { pair in
                                    Text(pair.element).tag(pair.offset)
                                }
                            }
                        }
                        DatePicker(
                            "First day on calendar",
                            selection: $viewModel.importScheduleStartDate,
                            displayedComponents: [.date]
                        )
                    }
                    .navigationTitle("Import program")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                viewModel.cancelStagedImport()
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Import") {
                                Task {
                                    await viewModel.confirmStagedImport(modelContext: modelContext)
                                }
                            }
                            .disabled(viewModel.isImporting || viewModel.stagedCycleDayLabels.isEmpty)
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
