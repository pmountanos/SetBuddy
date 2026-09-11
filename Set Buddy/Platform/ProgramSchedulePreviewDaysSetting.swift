//
//  ProgramSchedulePreviewDaysSetting.swift
//  Set Buddy
//

import Foundation

extension Notification.Name {
    /// Posted when the user changes how many upcoming days appear on the Program tab schedule list.
    static let programSchedulePreviewDaysDidChange = Notification.Name("programSchedulePreviewDaysDidChange")
}

enum ProgramSchedulePreviewDaysSetting {
    static let userDefaultsKey = "programOverview.schedulePreviewDays"
    static let choices: [Int] = [7, 14, 21]

    static func load(from defaults: UserDefaults = .standard) -> Int {
        let s = defaults.integer(forKey: userDefaultsKey)
        return choices.contains(s) ? s : 14
    }

    static func save(_ days: Int, to defaults: UserDefaults = .standard) {
        guard choices.contains(days) else { return }
        defaults.set(days, forKey: userDefaultsKey)
        NotificationCenter.default.post(name: .programSchedulePreviewDaysDidChange, object: nil)
    }
}
