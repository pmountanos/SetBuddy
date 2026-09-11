//
//  NotificationSettingsViewModel.swift
//  Set Buddy
//

import Foundation
import SwiftData
import UserNotifications

/// Daily reminder toggle/time and system authorization status — the Notifications section of Settings.
@MainActor
@Observable
final class NotificationSettingsViewModel {
    /// User-facing status for the Notifications section (system authorization).
    var notificationAuthorizationExplanation: String = ""
    var notificationShowAllowButton = false
    var notificationShowOpenSettingsButton = false

    /// Master switch for scheduling daily plan reminders (stored in `NotificationSettings`).
    var dailyNotificationsEnabled: Bool {
        didSet { persist() }
    }

    /// Time-of-day for the daily reminder; calendar date is ignored.
    var notificationReminderTime: Date {
        didSet { persist() }
    }

    init() {
        let ns = NotificationSettings.load()
        dailyNotificationsEnabled = ns.dailyRemindersEnabled
        notificationReminderTime = Calendar.current.date(
            bySettingHour: ns.hour,
            minute: ns.minute,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    private func persist() {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: notificationReminderTime)
        let minute = cal.component(.minute, from: notificationReminderTime)
        NotificationSettings(
            dailyRemindersEnabled: dailyNotificationsEnabled,
            hour: hour,
            minute: minute
        ).save()
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let status = settings.authorizationStatus
        notificationShowAllowButton = status == .notDetermined
        notificationShowOpenSettingsButton = status == .denied
        switch status {
        case .authorized, .provisional, .ephemeral:
            notificationAuthorizationExplanation = "System permission is on. Reminders use your chosen time when the toggle above is on."
        case .denied:
            notificationAuthorizationExplanation = "Notifications are turned off for Set Buddy. Use “Open system settings” to enable alerts."
        case .notDetermined:
            notificationAuthorizationExplanation = "Allow notifications so Set Buddy can remind you on workout and rest days."
        @unknown default:
            notificationAuthorizationExplanation = ""
        }
    }

    func requestAuthorizationAndReschedule(modelContext: ModelContext) async {
        _ = await NotificationPermission.requestAuthorization()
        await refreshAuthorizationStatus()
        DailyNotificationScheduler.requestReschedule(modelContext: modelContext)
    }
}
