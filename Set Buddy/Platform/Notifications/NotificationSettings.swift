//
//  NotificationSettings.swift
//  Set Buddy
//
//  UserDefaults-backed preferences for Phase 8 (daily reminder time and on/off).
//

import Foundation

struct NotificationSettings: Equatable, Sendable {
    var dailyRemindersEnabled: Bool
    var hour: Int
    var minute: Int

    private enum Keys {
        static let enabled = "notificationSettings.dailyRemindersEnabled"
        static let hour = "notificationSettings.reminderHour"
        static let minute = "notificationSettings.reminderMinute"
    }

    static let `default` = NotificationSettings(dailyRemindersEnabled: true, hour: 8, minute: 0)

    static func load(from defaults: UserDefaults = .standard) -> NotificationSettings {
        let d = defaults
        let enabled: Bool
        if d.object(forKey: Keys.enabled) == nil {
            enabled = true
        } else {
            enabled = d.bool(forKey: Keys.enabled)
        }
        let hour = (d.object(forKey: Keys.hour) as? Int) ?? Self.default.hour
        let minute = (d.object(forKey: Keys.minute) as? Int) ?? Self.default.minute
        return NotificationSettings(
            dailyRemindersEnabled: enabled,
            hour: Self.clampHour(hour),
            minute: Self.clampMinute(minute)
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        let d = defaults
        d.set(dailyRemindersEnabled, forKey: Keys.enabled)
        d.set(Self.clampHour(hour), forKey: Keys.hour)
        d.set(Self.clampMinute(minute), forKey: Keys.minute)
    }

    fileprivate static func clampHour(_ h: Int) -> Int { min(23, max(0, h)) }
    fileprivate static func clampMinute(_ m: Int) -> Int { min(59, max(0, m)) }
}
