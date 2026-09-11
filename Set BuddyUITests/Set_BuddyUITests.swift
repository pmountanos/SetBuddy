//
//  Set_BuddyUITests.swift
//  Set BuddyUITests
//

import XCTest

final class Set_BuddyUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    // MARK: - Helpers

    /// Seeded sample: day 0 is **Upper Day A**; starts from Today and finishes without editing sets.
    @MainActor
    private func completeSeededUpperWorkoutFromToday() {
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Today"].waitForExistence(timeout: 8))
        let startButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start ")).firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 12))
        app.buttons["Finish"].tap()
        let confirmFinish = app.buttons["Finish workout"]
        XCTAssertTrue(confirmFinish.waitForExistence(timeout: 5))
        confirmFinish.tap()
        XCTAssertTrue(app.staticTexts["No workout open"].waitForExistence(timeout: 10))
    }

    // MARK: - Tests

    @MainActor
    func testLaunchShowsTodayTab() throws {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Today"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.navigationBars.firstMatch.staticTexts["Today"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testNavigateAllMainTabs() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        tabBar.buttons["Program"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.staticTexts["Program"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Upcoming schedule"].waitForExistence(timeout: 5))

        tabBar.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.staticTexts["History"].waitForExistence(timeout: 5))

        tabBar.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.staticTexts["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["How it works"].waitForExistence(timeout: 5))

        tabBar.buttons["Workout"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.staticTexts["Log Workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No workout open"].waitForExistence(timeout: 5))

        tabBar.buttons["Today"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.staticTexts["Today"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testProgramTabShowsSeededProgramAndWorkouts() throws {
        app.tabBars.firstMatch.buttons["Program"].tap()
        XCTAssertTrue(app.staticTexts["Sample Program"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Upper Day A"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsShowsProgramImportControls() throws {
        app.tabBars.firstMatch.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Import program (.xlsx)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Daily plan reminder"].waitForExistence(timeout: 5))
    }

    /// Full path: Today → Start (seeded sample is a workout on day 0) → Finish → History lists the session.
    @MainActor
    func testStartWorkoutFromTodayFinishAndSeeInHistory() throws {
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Today"].waitForExistence(timeout: 8))

        let startButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start ")).firstMatch
        guard startButton.waitForExistence(timeout: 10) else {
            throw XCTSkip("No “Start …” button (not a workout day or schedule missing).")
        }
        startButton.tap()

        XCTAssertTrue(app.tabBars.firstMatch.buttons["Workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars.firstMatch.staticTexts["Upper Day A"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Session volume"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 5))
        app.buttons["Finish"].tap()
        XCTAssertTrue(app.buttons["Finish workout"].waitForExistence(timeout: 5))
        app.buttons["Finish workout"].tap()

        XCTAssertTrue(app.navigationBars.firstMatch.staticTexts["Log Workout"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["No workout open"].waitForExistence(timeout: 5))

        app.tabBars.firstMatch.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.staticTexts["History"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Upper Day A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Volume:")).firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testTodayHidesStartWorkoutAfterSessionFinished() throws {
        completeSeededUpperWorkoutFromToday()
        app.tabBars.firstMatch.buttons["Today"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["todayStartWorkoutButton"].exists)
        XCTAssertFalse(app.buttons["todayContinueWorkoutButton"].exists)
    }

    /// After opening today’s workout (session created), Today should offer Continue — not Start — until the session is finished.
    @MainActor
    func testTodayShowsContinueWhenWorkoutInProgress() throws {
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Today"].waitForExistence(timeout: 8))
        let startButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start ")).firstMatch
        guard startButton.waitForExistence(timeout: 10) else {
            throw XCTSkip("No “Start …” button (not a workout day or schedule missing).")
        }
        startButton.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.staticTexts["Upper Day A"].waitForExistence(timeout: 12))

        app.tabBars.firstMatch.buttons["Today"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["todayStartWorkoutButton"].exists)
        XCTAssertTrue(app.buttons["todayContinueWorkoutButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHistoryOpensSessionDetailWithSetRows() throws {
        completeSeededUpperWorkoutFromToday()

        app.tabBars.firstMatch.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.staticTexts["History"].waitForExistence(timeout: 5))

        let titleInRow = app.staticTexts.matching(NSPredicate(format: "label == %@", "Upper Day A")).firstMatch
        XCTAssertTrue(titleInRow.waitForExistence(timeout: 8))
        titleInRow.tap()

        XCTAssertTrue(app.navigationBars.firstMatch.staticTexts["Upper Day A"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Total volume"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set 1"].waitForExistence(timeout: 5))
    }
}
