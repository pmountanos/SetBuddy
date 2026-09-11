//
//  SettingsViewModel.swift
//  Set Buddy
//

import Foundation

/// Container for the Settings screen's three independent concerns (notifications, import, export) plus the one
/// setting that doesn't fit any of them (upcoming schedule list length).
@MainActor
@Observable
final class SettingsViewModel {
    var notifications = NotificationSettingsViewModel()
    var importer = ImportViewModel()
    var exporter = ExportViewModel()

    /// Row count for the Program tab’s upcoming schedule list (7 / 14 / 21).
    var upcomingScheduleListDayCount: Int

    init() {
        upcomingScheduleListDayCount = ProgramSchedulePreviewDaysSetting.load()
    }

    func setUpcomingScheduleListDayCount(_ days: Int) {
        guard ProgramSchedulePreviewDaysSetting.choices.contains(days) else { return }
        upcomingScheduleListDayCount = days
        ProgramSchedulePreviewDaysSetting.save(days)
    }
}
