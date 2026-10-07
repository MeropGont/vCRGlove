//
//  vCRGloveUITests.swift
//  vCRGloveUITests
//
//  Created by Tactile Glove on 22.08.25.
//

import XCTest

final class vCRGloveUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testMovementTrendStatesEnglish() throws {
        try checkMovementTrendStates(language: "en", fontSize: "standard")
    }

    @MainActor
    func testMovementTrendStatesGerman() throws {
        try checkMovementTrendStates(language: "de", fontSize: "standard")
    }

    @MainActor
    func testMovementTrendGermanLargeText() throws {
        try checkMovementTrendStates(language: "de", fontSize: "large")
    }

    @MainActor
    func testMovementTrendGermanAccessibilityText() throws {
        try checkMovementTrendStates(language: "de", fontSize: "extraLarge", scenarios: ["unavailable", "single"])
    }

    @MainActor
    private func checkMovementTrendStates(language: String, fontSize: String,
                                          scenarios: [String] = ["empty", "unavailable", "single", "mixed", "multiple"]) throws {
        let german = language == "de"
        for scenario in scenarios {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-test-trend-scenario", scenario, "-appLanguage", language,
                                   "-appFontSize", fontSize]
            app.launch()
            let movement = app.tabBars.buttons[german ? "Bewegung" : "Movement"]
            XCTAssertTrue(movement.waitForExistence(timeout: 10))
            movement.tap()
            app.buttons["Trends"].tap()
            XCTAssertTrue(app.buttons["trendMetricPicker"].waitForExistence(timeout: 5))
            if fontSize == "extraLarge" {
                let task = app.buttons["trendTaskPicker"]
                XCTAssertTrue(task.label.contains("Finger-Tapping"))
                XCTAssertTrue(app.buttons["trendMetricPicker"].label.contains("Geschwindigkeit"))
                XCTAssertGreaterThan(task.frame.height, 70)
                for _ in 0..<3 where !app.staticTexts[german ? "Zu wenige Bewegungsdaten" : "Not enough movement data"].isHittable && scenario == "unavailable" {
                    app.collectionViews.firstMatch.swipeUp()
                }
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Movement trends \(scenario) \(language) \(fontSize)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            switch scenario {
            case "empty":
                XCTAssertTrue(app.staticTexts[german ? "Noch keine Aufnahmen" : "No recordings yet"].exists)
            case "unavailable":
                let title = app.staticTexts[german ? "Zu wenige Bewegungsdaten" : "Not enough movement data"]
                XCTAssertTrue(title.exists)
                XCTAssertLessThanOrEqual(title.frame.width, app.frame.width - 20)
                XCTAssertTrue(title.isHittable)
                XCTAssertFalse(app.staticTexts["trendSingleValue"].exists)
            case "single", "mixed":
                let hint = app.staticTexts["trendSingleMeasurement"]
                XCTAssertTrue(hint.waitForExistence(timeout: 5))
                XCTAssertEqual(hint.label, german ? "Für einen Verlauf sind weitere Messungen nötig."
                                                  : "More measurements needed for a trend.")
                XCTAssertTrue(app.staticTexts["trendSingleValue"].exists)
                XCTAssertEqual(app.staticTexts["trendSingleValue"].label, german ? "2,00 Hz" : "2.00 Hz")
                XCTAssertTrue(app.staticTexts["trendRecordingDate"].firstMatch.exists)
                XCTAssertTrue(app.staticTexts[german ? "Stimulationszeitpunkt nicht angegeben"
                                                     : "Stimulation timing not specified"].firstMatch.exists)
                XCTAssertFalse(app.descendants(matching: .any)["movementTrendChart"].exists)
                if fontSize == "extraLarge" {
                    for _ in 0..<4 where !hint.isHittable { app.collectionViews.firstMatch.swipeUp() }
                    XCTAssertTrue(hint.isHittable)
                    let screenshot = XCTAttachment(screenshot: app.screenshot())
                    screenshot.name = "Movement trends reachable hint \(language) \(fontSize)"
                    screenshot.lifetime = .keepAlways
                    add(screenshot)
                }
                if scenario == "mixed" {
                    XCTAssertTrue(app.staticTexts[german ? "Aufnahmen ohne diesen Messwert: 1"
                                                         : "Results unavailable for this metric: 1"].exists)
                }
            default:
                XCTAssertTrue(app.descendants(matching: .any)["movementTrendChart"].exists)
                XCTAssertFalse(app.staticTexts["trendSingleMeasurement"].exists)
            }
            if scenario == "single" {
                if fontSize == "extraLarge" { app.collectionViews.firstMatch.swipeDown() }
                app.buttons["trendMetricPicker"].tap()
                app.buttons[german ? "Pausen" : "Pauses"].tap()
                XCTAssertEqual(app.staticTexts["trendSingleValue"].label, "0")
                app.buttons["trendTaskPicker"].tap()
                XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '3.4' OR label BEGINSWITH '3.5' OR label BEGINSWITH '3.6'")).firstMatch.exists)
                app.buttons[german ? "Hand öffnen/schließen" : "Hand Open/Close"].tap()
                XCTAssertTrue(app.staticTexts[german ? "Noch keine Aufnahmen" : "No recordings yet"].exists)
            }
            app.terminate()
        }
    }

    @MainActor
    func testPronationInstructionsScrollAboveTabs() throws {
        for fontSize in ["standard", "extraLarge"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-test-watch-layout", "-appLanguage", "de", "-appFontSize", fontSize]
            app.launch()
            let movement = app.tabBars.buttons["Bewegung"]
            XCTAssertTrue(movement.waitForExistence(timeout: 10))
            movement.tap()
            let skip = app.buttons["movementSkipMeasurement"]
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            for hand in ["right", "left"] {
                let scroll = app.scrollViews.firstMatch
                XCTAssertTrue(scroll.waitForExistence(timeout: 5))
                for _ in 0..<8 where !skip.isHittable || skip.frame.maxY > app.tabBars.firstMatch.frame.minY {
                    scroll.swipeUp()
                }
                XCTAssertTrue(skip.isHittable)
                XCTAssertLessThanOrEqual(skip.frame.maxY, app.tabBars.firstMatch.frame.minY)
                let start = app.buttons["Aufnahme starten"]
                XCTAssertTrue(start.exists)
                XCTAssertFalse(start.isEnabled)
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "Pronation reachable skip \(hand) \(fontSize)"
                screenshot.lifetime = .keepAlways
                add(screenshot)
                skip.tap()
            }
            XCTAssertTrue(app.staticTexts["Keine Aufnahmen gespeichert"].exists)
            app.terminate()
        }
    }

    @MainActor
    func testCameraRecordingInstructionsEnglish() throws {
        try checkCameraRecordingInstructions(language: "en", fontSize: "standard")
    }

    @MainActor
    func testCameraRecordingInstructionsGerman() throws {
        try checkCameraRecordingInstructions(language: "de", fontSize: "standard")
    }

    @MainActor
    func testCameraRecordingInstructionsGermanLargeText() throws {
        try checkCameraRecordingInstructions(language: "de", fontSize: "large")
    }

    @MainActor
    private func checkCameraRecordingInstructions(language: String, fontSize: String) throws {
        let german = language == "de"
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-recording-layout", "-appLanguage", language, "-appFontSize", fontSize]
        app.launch()
        let movement = app.tabBars.buttons[german ? "Bewegung" : "Movement"]
        XCTAssertTrue(movement.waitForExistence(timeout: 10))
        movement.tap()
        app.buttons[german ? "Starten" : "Start"].tap()
        app.buttons.containing(.staticText, identifier: german ? "Vor der Stimulation" : "Before stimulation")
            .firstMatch.tap()
        app.buttons[german ? "Weiter" : "Continue"].tap()

        for step in 1...4 {
            let record = app.buttons[german ? "Aufnahme starten" : "Start Recording"]
            XCTAssertTrue(record.waitForExistence(timeout: 5))
            record.tap()
            let instruction = app.staticTexts["movementRecordingInstruction"]
            let hand = app.staticTexts["movementRecordingHand"]
            XCTAssertTrue(instruction.waitForExistence(timeout: 3))
            let expected = step <= 2
                ? (german ? "Zeigefinger und Daumen zusammentippen.\nWeit öffnen und so schnell wie möglich wiederholen."
                          : "Tap your index finger to your thumb.\nOpen wide. Repeat as fast as you can.")
                : (german ? "Hand ganz öffnen, dann eine Faust machen.\nSo schnell wie möglich wiederholen."
                          : "Open your hand fully, then make a fist.\nRepeat as fast as you can.")
            XCTAssertEqual(instruction.label, expected)
            XCTAssertEqual(hand.label, step % 2 == 1
                ? (german ? "Rechte Hand" : "Right hand") : (german ? "Linke Hand" : "Left hand"))
            let stop = app.buttons[german ? "Stopp" : "Stop"]
            XCTAssertTrue(stop.waitForExistence(timeout: 8))
            XCTAssertTrue(stop.isHittable)
            XCTAssertGreaterThanOrEqual(stop.frame.height, 54)
            XCTAssertTrue(instruction.isHittable)
            XCTAssertLessThanOrEqual(instruction.frame.maxY, app.tabBars.firstMatch.frame.minY)
            XCTAssertTrue(app.staticTexts[german ? "Demnächst verfügbar" : "Coming soon"].exists)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Camera recording step \(step) \(language) \(fontSize)"
            screenshot.lifetime = .keepAlways
            add(screenshot)

            app.buttons["movementSessionBack"].tap()
            let alert = app.alerts[german ? "Aufnahme stoppen und zurückgehen?" : "Stop this recording and go back?"]
            XCTAssertTrue(alert.waitForExistence(timeout: 3))
            alert.buttons[german ? "Stoppen und zurück" : "Stop and go back"].tap()
            XCTAssertTrue(record.waitForExistence(timeout: 5))
            app.buttons[german ? "Diese Messung überspringen" : "Skip this measurement"].tap()
        }
    }

    @MainActor
    func testMovementBackDuringTasksAndRecording() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-session-save", UUID().uuidString,
                               "-appLanguage", "en", "-appFontSize", "standard"]
        app.launch()
        let movement = app.tabBars.buttons["Movement"]
        XCTAssertTrue(movement.waitForExistence(timeout: 10))
        movement.tap()
        app.buttons["Start"].tap()
        app.buttons.containing(.staticText, identifier: "Before stimulation").firstMatch.tap()
        app.buttons["Continue"].tap()
        let back = app.buttons["movementSessionBack"]
        let record = app.buttons["Start Recording"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(app.staticTexts["When is this measurement?"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()
        app.buttons["Skip this measurement"].tap()
        XCTAssertTrue(app.staticTexts["Step 2 of 6"].waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.staticTexts["Step 1 of 6"].waitForExistence(timeout: 5))
        record.tap()
        back.tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 8))
        back.tap()
        let alert = app.alerts["Stop this recording and go back?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["Keep recording"].tap()
        XCTAssertTrue(app.buttons["Stop"].exists)
        back.tap()
        alert.buttons["Stop and go back"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 8))
        app.buttons["Stop"].tap()
        let use = app.buttons["movementSaveContinue"]
        XCTAssertTrue(app.navigationBars["Result"].waitForExistence(timeout: 15))
        for _ in 0..<5 where !use.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(use.isHittable)
        XCTAssertFalse(back.exists)
        use.tap()
        XCTAssertTrue(app.staticTexts["Step 2 of 6"].waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.staticTexts["Step 1 of 6"].waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.staticTexts["When is this measurement?"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.containing(.staticText, identifier: "After stimulation").firstMatch.isEnabled)
        back.tap()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
        app.buttons["Start"].tap()
        XCTAssertTrue(app.buttons["Continue"].isEnabled)
        app.buttons["Continue"].tap()
        record.tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 8))
        app.buttons["Stop"].tap()
        XCTAssertTrue(app.navigationBars["Result"].waitForExistence(timeout: 15))
        for _ in 0..<5 where !use.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(use.isHittable)
        use.tap()
        for step in 2...6 {
            XCTAssertTrue(app.staticTexts["Step \(step) of 6"].waitForExistence(timeout: 5))
            app.buttons["Skip this measurement"].tap()
        }
        XCTAssertTrue(app.staticTexts["Saved recordings: 1 / 6"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["movementSavedSetStatus"].label, "Some tasks recorded")
        XCTAssertFalse(back.exists)
        app.buttons["movementSummaryDone"].tap()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["movementSavedTestCounts"].label, "sessions=1;trials=1")
        XCTAssertFalse(back.exists)
    }

    @MainActor
    private func showSaveAction(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[identifier]
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 10))
        for _ in 0..<10 where !button.isHittable || button.frame.maxY > app.tabBars.firstMatch.frame.minY {
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(button.isHittable)
        XCTAssertLessThanOrEqual(button.frame.maxY, app.tabBars.firstMatch.frame.minY)
        XCTAssertGreaterThanOrEqual(button.frame.height, 54)
        return button
    }

    @MainActor
    private func expectSavedCounts(_ count: String, in app: XCUIApplication) {
        let element = app.staticTexts["movementSavedTestCounts"]
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let ready = expectation(for: NSPredicate(format: "label == %@", count), evaluatedWith: element)
        wait(for: [ready], timeout: 5)
    }

    @MainActor
    func testSaveAndFinishPersistsOneRecordingEnglishAndGerman() throws {
        for (language, font) in [("en", "standard"), ("de", "extraLarge")] {
            let app = XCUIApplication()
            let arguments = ["--ui-test-session-save", UUID().uuidString,
                             "-appLanguage", language, "-appFontSize", font]
            app.launchArguments = arguments + ["--ui-test-save-result"]
            app.launch()
            app.tabBars.buttons[language == "de" ? "Bewegung" : "Movement"].tap()
            let finish = showSaveAction("movementSaveFinish", in: app)
            let result = XCTAttachment(screenshot: app.screenshot())
            result.name = "Reachable save actions \(language) \(font)"
            result.lifetime = .keepAlways
            add(result)
            finish.tap()
            XCTAssertTrue(app.staticTexts["movementSavedSummary"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["movementSavedSummary"].label,
                           language == "de" ? "Aufnahmen gespeichert" : "Recordings saved")
            XCTAssertEqual(app.staticTexts["movementSavedSetStatus"].label,
                           language == "de" ? "Einzelne Tests aufgezeichnet" : "Some tasks recorded")
            XCTAssertFalse(app.buttons["Save Session"].exists)
            let done = app.buttons["movementSummaryDone"]
            XCTAssertTrue(done.isHittable)
            XCTAssertLessThanOrEqual(done.frame.maxY, app.tabBars.firstMatch.frame.minY)
            let summary = XCTAttachment(screenshot: app.screenshot())
            summary.name = "Saved partial session \(language) \(font)"
            summary.lifetime = .keepAlways
            add(summary)
            let savedTask = app.staticTexts[language == "de" ? "Finger-Tapping" : "Finger Tapping"]
            for _ in 0..<8 where !savedTask.isHittable || savedTask.frame.maxY > done.frame.minY {
                app.scrollViews.firstMatch.swipeUp()
            }
            XCTAssertTrue(savedTask.isHittable)
            XCTAssertLessThanOrEqual(savedTask.frame.maxY, done.frame.minY)
            let taskSummary = XCTAttachment(screenshot: app.screenshot())
            taskSummary.name = "Reachable saved task \(language) \(font)"
            taskSummary.lifetime = .keepAlways
            add(taskSummary)
            done.tap()
            expectSavedCounts("sessions=1;trials=1", in: app)
            app.terminate()
            app.launchArguments = arguments
            app.launch()
            app.tabBars.buttons[language == "de" ? "Bewegung" : "Movement"].tap()
            expectSavedCounts("sessions=1;trials=1", in: app)
            app.buttons["Trends"].tap()
            XCTAssertTrue(app.staticTexts["trendSingleValue"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["trendSingleValue"].label, language == "de" ? "2,00 Hz" : "2.00 Hz")
            app.terminate()
        }
    }

    @MainActor
    func testContinueSavesBeforeFinishingAndSurvivesRelaunch() throws {
        let app = XCUIApplication()
        let arguments = ["--ui-test-session-save", UUID().uuidString,
                         "-appLanguage", "en", "-appFontSize", "standard"]
        app.launchArguments = arguments + ["--ui-test-save-result"]
        app.launch()
        app.tabBars.buttons["Movement"].tap()
        showSaveAction("movementSaveContinue", in: app).tap()
        XCTAssertTrue(app.staticTexts["Step 2 of 6"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved recordings: 1 / 6"].exists)
        // No final action: the first accepted recording must already be on disk.
        app.terminate()
        app.launchArguments = arguments
        app.launch()
        app.tabBars.buttons["Movement"].tap()
        expectSavedCounts("sessions=1;trials=1", in: app)
    }

    @MainActor
    func testFinishForNowDoesNotSaveSessionTwice() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-session-save", UUID().uuidString, "--ui-test-save-result",
                               "-appLanguage", "de", "-appFontSize", "extraLarge"]
        app.launch()
        app.tabBars.buttons["Bewegung"].tap()
        showSaveAction("movementSaveContinue", in: app).tap()
        let finish = app.buttons["movementFinishForNow"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        for _ in 0..<10 where !finish.isHittable || finish.frame.maxY > app.tabBars.firstMatch.frame.minY {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(finish.isHittable)
        XCTAssertLessThanOrEqual(finish.frame.maxY, app.tabBars.firstMatch.frame.minY)
        finish.tap()
        XCTAssertTrue(app.staticTexts["movementSavedSummary"].waitForExistence(timeout: 5))
        app.buttons["movementSummaryDone"].tap()
        expectSavedCounts("sessions=1;trials=1", in: app)
    }

    @MainActor
    func testFailedSaveKeepsResultForRetry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-session-save", UUID().uuidString, "--ui-test-save-result",
                               "--ui-test-session-save-failure", "-appLanguage", "de", "-appFontSize", "standard"]
        app.launch()
        app.tabBars.buttons["Bewegung"].tap()
        for action in ["movementSaveFinish", "movementSaveContinue"] {
            showSaveAction(action, in: app).tap()
            let alert = app.alerts["Aufnahme nicht gespeichert"]
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            alert.buttons["OK"].tap()
            XCTAssertTrue(app.buttons["movementSaveFinish"].exists)
            XCTAssertTrue(app.buttons["Wiederholen"].isEnabled)
            XCTAssertFalse(app.staticTexts["movementSavedSummary"].exists)
        }
    }

    @MainActor
    func testAllSixAcceptedRecordingsRemainOneSession() throws {
        let app = XCUIApplication()
        let arguments = ["--ui-test-session-save", UUID().uuidString,
                         "-appLanguage", "en", "-appFontSize", "standard"]
        app.launchArguments = arguments
        app.launch()
        app.tabBars.buttons["Movement"].tap()
        app.buttons["Start"].tap()
        app.buttons.containing(.staticText, identifier: "Before stimulation").firstMatch.tap()
        app.buttons["Continue"].tap()
        for step in 1...6 {
            XCTAssertTrue(app.staticTexts["Step \(step) of 6"].waitForExistence(timeout: 5))
            let record = app.buttons["Start Recording"]
            for _ in 0..<8 where !record.isHittable || record.frame.maxY > app.tabBars.firstMatch.frame.minY {
                app.scrollViews.firstMatch.swipeUp()
            }
            record.tap()
            let stop = app.buttons["Stop"]
            XCTAssertTrue(stop.waitForExistence(timeout: 8))
            stop.tap()
            XCTAssertTrue(app.navigationBars["Result"].waitForExistence(timeout: 15))
            let save = showSaveAction("movementSaveContinue", in: app)
            XCTAssertEqual(save.label, step == 6 ? "Save & Finish" : "Save & Continue")
            save.tap()
        }
        XCTAssertTrue(app.staticTexts["movementSavedSummary"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["movementSavedSetStatus"].label, "All tasks recorded")
        XCTAssertTrue(app.staticTexts["Saved recordings: 6 / 6"].exists)
        app.buttons["movementSummaryDone"].tap()
        expectSavedCounts("sessions=1;trials=6", in: app)
        app.terminate()
        app.launch()
        app.tabBars.buttons["Movement"].tap()
        expectSavedCounts("sessions=1;trials=6", in: app)
    }

    @MainActor
    func testUnacceptedResultIsNotSavedAutomatically() throws {
        let app = XCUIApplication()
        let arguments = ["--ui-test-session-save", UUID().uuidString,
                         "-appLanguage", "en", "-appFontSize", "standard"]
        app.launchArguments = arguments + ["--ui-test-save-result"]
        app.launch()
        app.tabBars.buttons["Movement"].tap()
        XCTAssertTrue(app.navigationBars["Result"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = arguments
        app.launch()
        app.tabBars.buttons["Movement"].tap()
        expectSavedCounts("sessions=0;trials=0", in: app)
    }

    @MainActor
    func testMovementSessionBackAndOptionalCalibrationEnglish() throws {
        try checkMovementSessionNavigation(language: "en")
    }

    @MainActor
    func testMovementSessionBackAndOptionalCalibrationGerman() throws {
        try checkMovementSessionNavigation(language: "de")
    }

    @MainActor
    private func checkMovementSessionNavigation(language: String) throws {
        let german = language == "de"
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-calibration", "-appLanguage", language, "-appFontSize", "standard",
                               "-calibratedHandScale", german ? "0.12" : "0"]
        app.launch()
        let movement = app.tabBars.buttons[german ? "Bewegung" : "Movement"]
        XCTAssertTrue(movement.waitForExistence(timeout: 10))
        movement.tap()
        let recommendation = app.staticTexts[german
            ? "Vor jeder neuen Testreihe empfehlen wir, erneut zu kalibrieren."
            : "For each new set of tests, we recommend recalibrating."]
        XCTAssertTrue(recommendation.waitForExistence(timeout: 5))
        XCTAssertTrue(recommendation.isHittable)
        let start = app.buttons[german ? "Starten" : "Start"]
        XCTAssertTrue(start.isEnabled)
        XCTAssertTrue(start.isHittable)
        let intro = XCTAttachment(screenshot: app.screenshot())
        intro.name = "Movement calibration recommendation \(language)"
        intro.lifetime = .keepAlways
        add(intro)
        start.tap()
        XCTAssertTrue(app.staticTexts[german ? "Wann ist diese Messung?" : "When is this measurement?"]
            .waitForExistence(timeout: 5))
        let back = app.buttons["movementSessionBack"]
        XCTAssertTrue(back.isHittable)
        let next = app.buttons[german ? "Weiter" : "Continue"]
        XCTAssertFalse(next.isEnabled)
        app.buttons.containing(.staticText, identifier: german ? "Vor der Stimulation" : "Before stimulation")
            .firstMatch.tap()
        XCTAssertTrue(next.isEnabled)
        let selection = XCTAttachment(screenshot: app.screenshot())
        selection.name = "Movement session back arrow \(language)"
        selection.lifetime = .keepAlways
        add(selection)
        back.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertFalse(back.exists)
        start.tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled)
        back.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
    }

    @MainActor
    func testCalibrationIntroductionAndSimulatorError() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-calibration", "-appLanguage", "en", "-appFontSize", "standard",
                               "-calibratedHandScale", "0"]
        app.launch()
        let movement = app.tabBars.buttons["Movement"]
        XCTAssertTrue(movement.waitForExistence(timeout: 10))
        movement.tap()
        let calibrate = app.buttons["Calibrate hand size"]
        XCTAssertTrue(calibrate.waitForExistence(timeout: 5))
        calibrate.tap()

        XCTAssertTrue(app.staticTexts["Hand calibration"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A quick camera check before your tests."].exists)
        XCTAssertTrue(app.staticTexts["Either hand is fine"].exists)
        XCTAssertFalse(app.staticTexts["Starting camera…"].exists)
        XCTAssertTrue(app.buttons["Continue"].isHittable)
        let introduction = XCTAttachment(screenshot: app.screenshot())
        introduction.name = "Calibration introduction"
        introduction.lifetime = .keepAlways
        add(introduction)

        app.buttons["Continue"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons.matching(
            NSPredicate(format: "label IN %@", ["Allow", "OK"])
        ).firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        XCTAssertTrue(app.staticTexts["Camera unavailable"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Try again"].isHittable)
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        let error = XCTAttachment(screenshot: app.screenshot())
        error.name = "Calibration camera unavailable"
        error.lifetime = .keepAlways
        add(error)

        app.buttons["Cancel"].tap()
        XCTAssertTrue(calibrate.waitForExistence(timeout: 5))
    }
}
