//
//  UITestLaunch.swift
//  Set Buddy
//

import Foundation

/// When `true`, UI tests passed `-uiTesting` on launch (skip system prompts that block automation).
enum UITestLaunch {
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }
}
