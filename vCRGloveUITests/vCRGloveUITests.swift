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
    private func revealMovementControl(_ element: XCUIElement, in app: XCUIApplication) {
        let next = app.buttons["movementContextContinue"]
        let save = app.buttons["movementSaveContinue"]
        let timer = app.staticTexts["movementRecordingTimer"]
        let record = app.buttons["movementStartRecording"]
        let summaryDone = app.buttons["movementSummaryDone"]
        let bottom = next.exists ? next.frame.minY - 12
            : save.exists ? save.frame.minY - 8
            : timer.exists ? timer.frame.minY - 8
            : summaryDone.exists ? summaryDone.frame.minY - 8
            : record.exists && element.elementType != .button
                ? record.frame.minY - 12 : app.tabBars.firstMatch.frame.minY
        let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY + 8 : 0
        let scroll = app.collectionViews.firstMatch.exists
            ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
        let contentTop = max(top, scroll.frame.minY + 8)
        let contentHeight = bottom - contentTop
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<24 {
            if element.isHittable && element.frame.maxY <= bottom && element.frame.minY >= contentTop { break }
            let frame = element.exists ? element.frame : .zero
            let downward = frame.height > 0 && frame.minY < contentTop
            let maximumDrag = contentHeight * 0.6
            let neededDrag = frame.height <= 0 ? maximumDrag
                : downward ? contentTop - frame.minY + 12 : frame.maxY - bottom + 12
            let distance = min(maximumDrag, max(20, neededDrag))
            let startY = downward ? contentTop + contentHeight * 0.2 : bottom - contentHeight * 0.15
            let start = origin.withOffset(CGVector(dx: app.frame.midX,
                                                  dy: startY))
            let end = origin.withOffset(CGVector(dx: app.frame.midX,
                                                dy: startY + (downward ? distance : -distance)))
            start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Visible movement control \(element.identifier)"
        screenshot.lifetime = .deleteOnSuccess
        add(screenshot)
        XCTAssertTrue(element.isHittable)
        XCTAssertLessThanOrEqual(element.frame.maxY, bottom)
        XCTAssertGreaterThanOrEqual(element.frame.minY, contentTop)
    }

    @MainActor
    func testStimulationChoicesAndOptionalMedicationEnglishGermanLargeText() throws {
        for (language, size) in [("en", "standard"), ("de", "extraLarge")] {
            let german = language == "de"
            let app = XCUIApplication()
            app.launchArguments = ["--ui-test-session-save", UUID().uuidString,
                                   "-appLanguage", language, "-appFontSize", size]
            app.launch()
            app.tabBars.buttons[german ? "Bewegung" : "Movement"].tap()
            app.buttons[german ? "Starten" : "Start"].tap()
            let next = app.buttons["movementContextContinue"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            XCTAssertFalse(next.isEnabled)
            XCTAssertFalse(app.buttons["movementContext-baseline"].exists)
            XCTAssertFalse(app.buttons["movementContext-unspecified"].exists)
            for context in ["preStim", "postStim", "noStimPlanned"] {
                let choice = app.buttons["movementContext-\(context)"]
                revealMovementControl(choice, in: app)
                XCTAssertGreaterThanOrEqual(choice.frame.height, 54)
                choice.tap()
            }
            XCTAssertEqual(app.buttons["movementContext-noStimPlanned"].label,
                           german ? "Heute keine Stimulation geplant" : "No stimulation planned today")
            revealMovementControl(app.buttons["movementMedicationChoice"], in: app)
            let medicationHeading = german ? "Letzte Parkinson-Medikation" : "Last Parkinson's medication"
            XCTAssertEqual(app.staticTexts.matching(identifier: medicationHeading).count, 1)
            XCTAssertFalse(app.staticTexts[german ? "Medikation (optional)" : "Medication (optional)"].exists)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Stimulation and optional medication \(language) \(size)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            XCTAssertTrue(next.isEnabled && next.isHittable)
            XCTAssertLessThanOrEqual(next.frame.maxY, app.tabBars.firstMatch.frame.minY)
            // Medication is deliberately unanswered and must not block the task.
            next.tap()
            let record = app.buttons[german ? "Aufnahme starten" : "Start Recording"]
            XCTAssertTrue(record.waitForExistence(timeout: 5))
            revealMovementControl(record, in: app)
            for step in 1...6 {
                XCTAssertTrue(app.staticTexts[german ? "Schritt \(step) von 6" : "Step \(step) of 6"].waitForExistence(timeout: 5))
                XCTAssertFalse(app.buttons["movementMedicationChoice"].exists)
                XCTAssertFalse(app.buttons[medicationHeading].exists)
                XCTAssertFalse(app.staticTexts[medicationHeading].exists)
                if step == 3 || step == 4 {
                    let clip = step == 3 ? "fist_left" : "fist_right"
                    let demo = app.descendants(matching: .any)["movementDemonstration-\(clip)"].firstMatch
                    revealMovementControl(demo, in: app)
                    let handShot = XCTAttachment(screenshot: app.screenshot())
                    handShot.name = "Open close hand instruction step \(step) \(language)"
                    handShot.lifetime = .keepAlways
                    add(handShot)
                }
                let skip = app.buttons["movementSkipMeasurement"]
                revealMovementControl(skip, in: app)
                skip.tap()
            }
            XCTAssertTrue(app.staticTexts["movementSavedSummary"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testJournalMedicationIsNotAutomaticallyConfirmed() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-session-save", UUID().uuidString, "--ui-test-medication-journal",
                               "-appLanguage", "en", "-appFontSize", "standard"]
        app.launch()
        app.tabBars.buttons["Movement"].tap()
        app.buttons["Start"].tap()
        app.buttons["movementContext-preStim"].tap()
        revealMovementControl(app.buttons["movementConfirmMedication"], in: app)
        app.buttons["movementContextContinue"].tap()
        let record = app.buttons["Start Recording"]
        revealMovementControl(record, in: app)
        record.tap()
        let stop = app.buttons["Stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 8))
        stop.tap()
        XCTAssertTrue(app.navigationBars["Result"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.descendants(matching: .any)["movementMedicationSummary"].exists)
    }

    @MainActor
    func testMedicationChoicesAndManualTimeGermanLargeText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-session-save", UUID().uuidString,
                               "-appLanguage", "de", "-appFontSize", "extraLarge"]
        app.launch()
        app.tabBars.buttons["Bewegung"].tap()
        app.buttons["Starten"].tap()
        app.buttons["movementContext-preStim"].tap()
        let choice = app.buttons["movementMedicationChoice"]
        revealMovementControl(choice, in: app)
        for label in ["Zu einer bestimmten Zeit", "Heute keine eingenommen", "Unsicher", "Nicht angegeben"] {
            revealMovementControl(choice, in: app)
            choice.tap()
            app.buttons[label].firstMatch.tap()
            XCTAssertTrue(app.buttons["movementContextContinue"].isEnabled)
            if label == "Zu einer bestimmten Zeit" {
                let time = app.descendants(matching: .any)["movementMedicationTime"].firstMatch
                revealMovementControl(time, in: app)
                XCTAssertLessThanOrEqual(time.frame.maxX, app.frame.maxX - 16)
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "Manual medication date and time German accessibility text"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            } else {
                XCTAssertFalse(app.descendants(matching: .any)["movementMedicationTime"].firstMatch.exists)
            }
        }
        app.buttons["movementContextContinue"].tap()
    }

    @MainActor
    func testConfirmedMedicationSurvivesSaveAndRelaunch() throws {
        let app = XCUIApplication()
        let arguments = ["--ui-test-session-save", UUID().uuidString, "--ui-test-medication-journal",
                         "-appLanguage", "en", "-appFontSize", "standard"]
        app.launchArguments = arguments
        app.launch()
        app.tabBars.buttons["Movement"].tap()
        app.buttons["Start"].tap()
        app.buttons["movementContext-noStimPlanned"].tap()
        let confirm = app.buttons["movementConfirmMedication"]
        revealMovementControl(confirm, in: app)
        confirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["movementMedicationTime"].firstMatch.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Confirmed journal medication time"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["movementContextContinue"].tap()
        let record = app.buttons["Start Recording"]
        revealMovementControl(record, in: app)
        record.tap()
        let stop = app.buttons["Stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 8))
        stop.tap()
        XCTAssertTrue(app.navigationBars["Result"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Last dose"].exists)
        showSaveAction("movementSaveContinue", in: app).tap()
        XCTAssertTrue(app.staticTexts["Step 2 of 6"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["movementMedicationChoice"].exists)
        XCTAssertFalse(app.buttons["Last Parkinson's medication"].exists)
        revealMovementControl(record, in: app)
        record.tap()
        XCTAssertTrue(stop.waitForExistence(timeout: 8))
        stop.tap()
        XCTAssertTrue(app.navigationBars["Result"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Last dose"].exists)
        showSaveAction("movementSaveFinish", in: app).tap()
        XCTAssertTrue(app.staticTexts["movementSavedSummary"].waitForExistence(timeout: 5))
        app.buttons["movementSummaryDone"].tap()
        app.buttons["Start"].tap()
        revealMovementControl(app.buttons["movementConfirmMedication"], in: app)
        XCTAssertEqual(app.buttons["movementMedicationChoice"].value as? String, "Not entered")
        XCTAssertFalse(app.descendants(matching: .any)["movementMedicationTime"].firstMatch.exists)
        app.terminate()
        app.launch()
        app.tabBars.buttons["Movement"].tap()
        expectSavedCounts("sessions=1;trials=2", in: app)
        app.buttons["Trends"].tap()
        let history = app.buttons["trendRecordingHistory"]
        for _ in 0..<8 where !history.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(history.isHittable)
        history.tap()
        let dose = app.staticTexts["Last dose"].firstMatch
        for _ in 0..<8 where !dose.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(dose.isHittable)
        XCTAssertTrue(app.staticTexts["No stimulation planned today"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Time since last dose:'")).firstMatch.exists)
        let saved = XCTAttachment(screenshot: app.screenshot())
        saved.name = "Saved medication context in recording history"
        saved.lifetime = .keepAlways
        add(saved)
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
    func testMovementRecordingHistoryAndDataShortcut() throws {
        for language in ["en", "de"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-test-trend-scenario", "multiple", "-appLanguage", language,
                                   "-appFontSize", language == "de" ? "extraLarge" : "standard"]
            app.launch()
            app.tabBars.buttons[language == "de" ? "Bewegung" : "Movement"].tap()
            app.buttons["Trends"].tap()
            let history = app.buttons["trendRecordingHistory"]
            for _ in 0..<12 where !history.isHittable { app.collectionViews.firstMatch.swipeUp() }
            XCTAssertTrue(history.isHittable)
            history.tap()
            XCTAssertTrue(app.navigationBars[language == "de" ? "Bisherige Aufnahmen" : "Recording history"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["trendRecordingValue"].firstMatch.exists)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Separate recording history \(language)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.buttons["trendData"].tap()
            XCTAssertTrue(app.navigationBars[language == "de" ? "Daten" : "Data"].waitForExistence(timeout: 5))
            app.terminate()
        }
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
                XCTAssertTrue(app.buttons["trendMetricPicker"].label.contains("Tapprate"))
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
                for _ in 0..<8 where !hint.exists { app.collectionViews.firstMatch.swipeUp() }
                XCTAssertTrue(hint.waitForExistence(timeout: 5))
                XCTAssertEqual(hint.label, german ? "Für einen Verlauf sind weitere Messungen nötig."
                                                  : "More measurements needed for a trend.")
                if scenario == "mixed" {
                    XCTAssertTrue(app.staticTexts[german ? "Aufnahmen ohne diesen Messwert: 1"
                                                         : "Results unavailable for this metric: 1"].exists)
                }
                let history = app.buttons["trendRecordingHistory"]
                for _ in 0..<10 where !history.isHittable {
                    app.collectionViews.firstMatch.swipeUp()
                }
                XCTAssertFalse(app.staticTexts["trendSingleValue"].exists)
                history.tap()
                XCTAssertTrue(app.staticTexts["trendRecordingValue"].firstMatch.waitForExistence(timeout: 5))
                XCTAssertEqual(app.staticTexts["trendRecordingValue"].firstMatch.label, german ? "2,0 Taps/s" : "2.0 taps/s")
                XCTAssertTrue(app.staticTexts["trendRecordingDate"].firstMatch.exists)
                XCTAssertTrue(app.staticTexts[german ? "Stimulationszeitpunkt nicht angegeben"
                                                     : "Stimulation timing not specified"].firstMatch.exists)
                app.navigationBars.buttons.element(boundBy: 0).tap()
                if fontSize == "extraLarge" {
                    for _ in 0..<10 where !hint.isHittable { app.collectionViews.firstMatch.swipeDown() }
                    XCTAssertTrue(hint.isHittable)
                    let screenshot = XCTAttachment(screenshot: app.screenshot())
                    screenshot.name = "Movement trends reachable hint \(language) \(fontSize)"
                    screenshot.lifetime = .keepAlways
                    add(screenshot)
                }
            default:
                XCTAssertTrue(app.descendants(matching: .any)["movementTrendChart"].firstMatch.exists)
                XCTAssertFalse(app.staticTexts["trendSingleMeasurement"].exists)
            }
            if scenario == "single" {
                let metricPicker = app.buttons["trendMetricPicker"]
                for _ in 0..<10 where !metricPicker.exists { app.collectionViews.firstMatch.swipeDown() }
                revealMovementControl(metricPicker, in: app)
                metricPicker.tap()
                XCTAssertFalse(app.buttons[german ? "Qualitätsindex" : "Quality index"].exists)
                XCTAssertFalse(app.buttons[german ? "Pausen" : "Pauses"].exists)
                let rhythm = app.buttons[german ? "Rhythmusvariabilität" : "Rhythm variability"]
                XCTAssertTrue(rhythm.waitForExistence(timeout: 5))
                rhythm.tap()
                let history = app.buttons["trendRecordingHistory"]
                for _ in 0..<10 where !history.isHittable {
                    app.collectionViews.firstMatch.swipeUp()
                }
                history.tap()
                XCTAssertTrue(app.staticTexts["trendRecordingValue"].firstMatch.waitForExistence(timeout: 5))
                XCTAssertEqual(app.staticTexts["trendRecordingValue"].firstMatch.label, german ? "10,0 %" : "10.0 %")
                app.navigationBars.buttons.element(boundBy: 0).tap()
                let taskPicker = app.buttons["trendTaskPicker"]
                for _ in 0..<10 where !taskPicker.exists { app.collectionViews.firstMatch.swipeDown() }
                revealMovementControl(taskPicker, in: app)
                taskPicker.tap()
                XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '3.4' OR label BEGINSWITH '3.5' OR label BEGINSWITH '3.6'")).firstMatch.exists)
                app.buttons[german ? "Hand öffnen/schließen" : "Hand Open/Close"].tap()
                XCTAssertTrue(app.staticTexts[german ? "Noch keine Aufnahmen" : "No recordings yet"].exists)
            }
            app.terminate()
        }
    }

    @MainActor
    func testMovementContextFiltersEnglish() throws { try checkMovementContextFilters(language: "en") }

    @MainActor
    func testMovementContextFiltersGerman() throws { try checkMovementContextFilters(language: "de") }

    @MainActor
    func testMovementContextFiltersGermanAccessibilityText() throws {
        try checkMovementContextFilters(language: "de", fontSize: "extraLarge")
    }

    @MainActor
    private func checkMovementContextFilters(language: String, fontSize: String = "standard") throws {
        let german = language == "de"
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-trend-scenario", "contexts", "-appLanguage", language, "-appFontSize", fontSize]
        app.launch()
        let movement = app.tabBars.buttons[german ? "Bewegung" : "Movement"]
        XCTAssertTrue(movement.waitForExistence(timeout: 10))
        movement.tap()
        app.buttons["Trends"].tap()
        func reveal(_ element: XCUIElement, upward: Bool = true) {
            let top = app.navigationBars.firstMatch.frame.maxY + 12
            let bottom = app.tabBars.firstMatch.frame.minY - 12
            for _ in 0..<12 {
                if element.isHittable, element.frame.minY >= top, element.frame.maxY <= bottom { break }
                let goUp = element.exists ? element.frame.maxY > bottom : upward
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                let end = start.withOffset(CGVector(dx: 0, dy: goUp ? -160 : 160))
                start.press(forDuration: 0.01, thenDragTo: end)
            }
            XCTAssertTrue(element.isHittable, "Not reachable: \(element)")
        }
        func choose(_ id: String, _ label: String) {
            let picker = app.buttons[id]
            reveal(picker)
            picker.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            app.buttons[label].tap()
        }
        let chart = app.descendants(matching: .any)["movementTrendChart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        choose("trendContextFilter", german ? "Vor der Stimulation" : "Before stimulation")
        func checkHistoryValue() {
            let history = app.buttons["trendRecordingHistory"]
            reveal(history)
            history.tap()
            let value = app.staticTexts["trendRecordingValue"].firstMatch
            XCTAssertTrue(value.waitForExistence(timeout: 5))
            XCTAssertEqual(value.label, german ? "2,0 Taps/s" : "2.0 taps/s")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        checkHistoryValue()
        choose("trendMedicationFilter", german ? "Heute nicht eingenommen" : "Not taken today")
        let empty = app.staticTexts[german ? "Keine passenden Aufnahmen" : "No matching recordings"]
        reveal(empty, upward: false)
        choose("trendContextFilter", german ? "Alle Stimulationszeitpunkte" : "All stimulation timings")
        checkHistoryValue()
        choose("trendMedicationFilter", german ? "Zeit seit letzter Einnahme" : "Time since last dose")
        let maximum = app.steppers["trendDoseMaximum"]
        let increase = maximum.buttons.element(boundBy: 1)
        reveal(increase)
        increase.tap()
        XCTAssertTrue(app.staticTexts[german ? "Bis 25 Stunden" : "To 25 hours"].exists)
        maximum.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts[german ? "Bis 24 Stunden" : "To 24 hours"].exists)
        XCTAssertTrue(app.steppers["trendDoseMinimum"].exists)
        checkHistoryValue()
        choose("trendMedicationFilter", german ? "Alle Medikamentenzeitpunkte" : "All medication timings")
        choose("trendPeriodFilter", german ? "7 Tage" : "7 days")
        reveal(empty, upward: false)
        choose("trendPeriodFilter", german ? "Alle Zeiträume" : "All dates")
        reveal(chart, upward: false)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Single-colour recording plot \(language)"
        image.lifetime = .keepAlways
        add(image)
        reveal(app.buttons["trendMedicationFilter"])
        let filtersImage = XCTAttachment(screenshot: app.screenshot())
        filtersImage.name = "Recording filters \(language)"
        filtersImage.lifetime = .keepAlways
        add(filtersImage)
        app.terminate()
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
                XCTAssertTrue(start.isHittable)
                XCTAssertLessThanOrEqual(start.frame.maxY, app.tabBars.firstMatch.frame.minY)
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
    func testHandDemonstrationsEnglish() throws {
        try checkHandDemonstrations(language: "en", fontSize: "standard")
    }

    @MainActor
    func testNextDemoAutoplaysAfterCompletedRecordingsAndSavesEveryTake() throws {
        let app = XCUIApplication()
        let arguments = ["--ui-test-recording-layout", "--ui-test-session-save", UUID().uuidString,
                         "-appLanguage", "en", "-appFontSize", "standard"]
        app.launchArguments = arguments
        app.launch()
        app.tabBars.buttons["Movement"].tap()
        app.buttons["Start"].tap()
        app.buttons["movementContext-preStim"].tap()
        app.buttons["movementContextContinue"].tap()
        for clip in ["finger_tapping_right", "finger_tapping_left", "fist_left"] {
            app.buttons["movementStartRecording"].tap()
            let stop = app.buttons["Stop"]
            XCTAssertTrue(stop.waitForExistence(timeout: 8))
            let demo = app.descendants(matching: .any)["movementDemonstration-\(clip)"].firstMatch
            XCTAssertTrue(demo.waitForExistence(timeout: 5))
            app.scrollViews.firstMatch.swipeUp()
            XCTAssertTrue(app.buttons["movementDemonstrationToggle"].isHittable)
            XCTAssertEqual(app.buttons["movementDemonstrationToggle"].label, "Pause demonstration")
            let initial = try XCTUnwrap(demo.value as? String)
            let advancing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", initial), object: demo)
            XCTAssertEqual(XCTWaiter.wait(for: [advancing], timeout: 8), .completed)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Autoplay after completed take \(clip)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            stop.tap()
            XCTAssertTrue(app.staticTexts["movementAutosaveStatus"].waitForExistence(timeout: 15))
            showSaveAction("movementSaveContinue", in: app).tap()
        }
        app.tabBars.buttons["Settings"].tap()
        app.tabBars.buttons["Movement"].tap()
        XCTAssertTrue(app.staticTexts["Step 4 of 6"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved recordings: 3 / 6"].exists)
        app.terminate()
        app.launch()
        app.tabBars.buttons["Movement"].tap()
        expectSavedCounts("sessions=1;trials=3", in: app)
    }

    @MainActor
    func testManualStopReachesResultsBeforeSignalAndAfterSignal() throws {
        for delayed in [true, false] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-test-recording-layout", "--ui-test-session-save", UUID().uuidString,
                                   "-appLanguage", "en", "-appFontSize", "standard"]
            if delayed { app.launchArguments.append("--ui-test-delayed-recorder-start") }
            app.launch()
            app.tabBars.buttons["Movement"].tap()
            app.buttons["Start"].tap()
            app.buttons["movementContext-preStim"].tap()
            app.buttons["movementContextContinue"].tap()
            app.buttons["movementStartRecording"].tap()
            let stop = app.buttons["Stop"]
            XCTAssertTrue(stop.waitForExistence(timeout: 8))
            if !delayed { Thread.sleep(forTimeInterval: 3) }
            stop.tap()
            XCTAssertTrue(app.navigationBars["Result"].waitForExistence(timeout: 10))
            XCTAssertFalse(stop.exists)
            XCTAssertTrue(app.buttons["movementRetake"].isHittable)
            if delayed {
                XCTAssertEqual(app.descendants(matching: .any)["movementRecordingFeedback"].firstMatch.label,
                               "No usable signal captured")
                app.buttons["movementRetake"].tap()
                app.alerts.firstMatch.buttons["Retake"].tap()
                XCTAssertTrue(app.buttons["movementStartRecording"].waitForExistence(timeout: 5))
                app.buttons["movementStartRecording"].tap()
                XCTAssertTrue(stop.waitForExistence(timeout: 8))
                stop.tap()
                XCTAssertTrue(app.navigationBars["Result"].waitForExistence(timeout: 10))
            }
            showSaveAction("movementSaveFinish", in: app).tap()
            XCTAssertTrue(app.staticTexts["movementSavedSummary"].waitForExistence(timeout: 5))
            app.buttons["movementSummaryDone"].tap()
            expectSavedCounts("sessions=1;trials=1", in: app)
            app.terminate()
        }
    }

    @MainActor
    func testMovementIntroInformationEnglishGerman() throws {
        for language in ["en", "de"] {
            let app = XCUIApplication()
            app.launchArguments = ["-appLanguage", language, "-appFontSize", "extraLarge"]
            app.launch()
            app.tabBars.buttons[language == "de" ? "Bewegung" : "Movement"].tap()
            let information = app.buttons["movementSessionInfo"]
            XCTAssertTrue(information.waitForExistence(timeout: 5))
            XCTAssertTrue(information.isHittable)
            information.tap()
            XCTAssertTrue(app.navigationBars[language == "de" ? "Über diese Aufgaben" : "About these tasks"]
                .waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "MDS-UPDRS")).count >= 1)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Movement task explanation \(language)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.buttons[language == "de" ? "Fertig" : "Done"].tap()
            XCTAssertTrue(information.isHittable)
            app.terminate()
        }
    }

    @MainActor
    func testOpenCloseRecordingFitsWithoutScrollingEnglishGerman() throws {
        try checkRecordingFitsWithoutScrolling(clips: ["fist_left", "fist_right"], skippedTasks: 2)
    }

    @MainActor
    func testFingerTappingRecordingFitsWithoutScrollingEnglishGerman() throws {
        try checkRecordingFitsWithoutScrolling(clips: ["finger_tapping_right", "finger_tapping_left"], skippedTasks: 0)
    }

    @MainActor
    private func checkRecordingFitsWithoutScrolling(clips: [String], skippedTasks: Int) throws {
        for language in ["en", "de"] {
            let german = language == "de"
            let app = XCUIApplication()
            app.launchArguments = ["--ui-test-recording-layout", "-appLanguage", language,
                                   "-appFontSize", "standard"]
            app.launch()
            app.tabBars.buttons[german ? "Bewegung" : "Movement"].tap()
            app.buttons[german ? "Starten" : "Start"].tap()
            app.buttons["movementContext-preStim"].tap()
            app.buttons["movementContextContinue"].tap()
            for _ in 0..<skippedTasks { app.buttons["movementSkipMeasurement"].tap() }
            for clip in clips {
                let record = app.buttons["movementStartRecording"]
                XCTAssertTrue(record.waitForExistence(timeout: 5))
                record.tap()
                let stop = app.buttons[german ? "Stopp" : "Stop"]
                XCTAssertTrue(stop.waitForExistence(timeout: 8))
                let top = app.navigationBars.firstMatch.frame.maxY
                let bottom = app.staticTexts["movementRecordingTimer"].frame.minY
                for id in ["movementRecordingTask", "movementRecordingHand", "movementRecordingInstruction", "movementCameraPreview",
                           "movementDemonstrationPanel-\(clip)", "movementLiveRhythm"] {
                    let element = app.descendants(matching: .any)[id].firstMatch
                    XCTAssertTrue(element.exists && element.isHittable, id)
                    XCTAssertGreaterThanOrEqual(element.frame.minY, top, id)
                    XCTAssertLessThanOrEqual(element.frame.maxY, bottom, id)
                }
                let demo = app.descendants(matching: .any)["movementDemonstration-\(clip)"].firstMatch
                XCTAssertEqual(demo.frame.width / demo.frame.height,
                               clip.hasPrefix("fist_") ? 480.0 / 560.0 : 854.0 / 480.0, accuracy: 0.03)
                if clip.hasPrefix("finger_tapping") {
                    XCTAssertGreaterThanOrEqual(demo.frame.width, 239)
                    let instruction = app.staticTexts["movementRecordingInstruction"]
                    let camera = app.descendants(matching: .any)["movementCameraPreview"].firstMatch
                    XCTAssertGreaterThanOrEqual(instruction.frame.minY, camera.frame.maxY)
                    XCTAssertGreaterThanOrEqual(demo.frame.minY, instruction.frame.maxY)
                }
                XCTAssertLessThanOrEqual(stop.frame.maxY, app.tabBars.firstMatch.frame.minY)
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "Complete recording layout \(clip) \(language)"
                screenshot.lifetime = .keepAlways
                add(screenshot)
                app.buttons["movementSessionBack"].tap()
                let alert = app.alerts[german ? "Aufnahme stoppen und zurückgehen?" : "Stop this recording and go back?"]
                XCTAssertTrue(alert.waitForExistence(timeout: 3))
                alert.buttons[german ? "Stoppen und zurück" : "Stop and go back"].tap()
                app.buttons["movementSkipMeasurement"].tap()
            }
            app.terminate()
        }
    }

    @MainActor
    func testHandDemonstrationsGermanLargeText() throws {
        try checkHandDemonstrations(language: "de", fontSize: "extraLarge")
    }

    @MainActor
    private func checkHandDemonstrations(language: String, fontSize: String) throws {
        let app = XCUIApplication()
        let german = language == "de"
        app.launchArguments = ["--ui-test-recording-layout", "-appLanguage", language, "-appFontSize", fontSize]
        app.launch()
        app.tabBars.buttons[german ? "Bewegung" : "Movement"].tap()
        app.buttons[german ? "Starten" : "Start"].tap()
        app.buttons["movementContext-preStim"].tap()
        app.buttons["movementContextContinue"].tap()

        for (index, clip) in ["finger_tapping_right", "finger_tapping_left", "fist_left", "fist_right"].enumerated() {
            let demo = app.descendants(matching: .any)["movementDemonstration-\(clip)"].firstMatch
            let panel = app.descendants(matching: .any)["movementDemonstrationPanel-\(clip)"].firstMatch
            XCTAssertTrue(demo.waitForExistence(timeout: 8))
            revealMovementControl(panel, in: app)
            XCTAssertEqual(demo.frame.width / demo.frame.height,
                           clip.hasPrefix("fist_") ? 480.0 / 560.0 : 854.0 / 480.0, accuracy: 0.03)
            let play = app.buttons["movementDemonstrationToggle"]
            XCTAssertTrue(play.waitForExistence(timeout: 8))
            let initialTime = try XCTUnwrap(demo.value as? String)
            play.tap()
            let toggle = play
            XCTAssertEqual(app.buttons.matching(identifier: "movementDemonstrationToggle").count, 1)
            XCTAssertFalse(app.buttons["movementDemonstrationPlay"].exists)
            XCTAssertTrue(toggle.isHittable)
            XCTAssertEqual(toggle.label, german ? "Beispiel pausieren" : "Pause demonstration")
            let advancing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", initialTime), object: demo)
            XCTAssertEqual(XCTWaiter.wait(for: [advancing], timeout: 8), .completed)
            let example = XCTAttachment(screenshot: demo.screenshot())
            example.name = "Instruction hand video \(clip) \(language) \(fontSize)"
            example.lifetime = .keepAlways
            add(example)
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).tap()
            XCTAssertEqual(toggle.label, german ? "Beispiel abspielen" : "Play demonstration")
            let record = app.buttons["movementStartRecording"]
            XCTAssertTrue(record.isHittable)
            XCTAssertLessThanOrEqual(record.frame.maxY, app.tabBars.firstMatch.frame.minY)
            record.tap()
            XCTAssertTrue(app.staticTexts["movementRecordingTask"].waitForExistence(timeout: 5))
            XCTAssertTrue(demo.waitForExistence(timeout: 8))
            let stop = app.buttons[german ? "Stopp" : "Stop"]
            XCTAssertTrue(stop.waitForExistence(timeout: 8))
            let timer = app.staticTexts["movementRecordingTimer"]
            XCTAssertTrue(timer.exists && timer.isHittable)
            XCTAssertLessThanOrEqual(timer.frame.maxY, stop.frame.minY)
            let camera = app.descendants(matching: .any)["movementCameraPreview"].firstMatch
            XCTAssertTrue(camera.exists)
            XCTAssertGreaterThan(camera.frame.height, demo.frame.height)
            XCTAssertGreaterThan(camera.frame.width, demo.frame.width)
            revealMovementControl(panel, in: app)
            XCTAssertTrue(toggle.isHittable)
            XCTAssertEqual(toggle.label, german ? "Beispiel pausieren" : "Pause demonstration")
            let recording = XCTAttachment(screenshot: app.screenshot())
            recording.name = "Recording with hand video \(clip) \(language) \(fontSize)"
            recording.lifetime = .keepAlways
            add(recording)
            XCTAssertTrue(stop.isHittable)
            XCTAssertLessThanOrEqual(stop.frame.maxY, app.tabBars.firstMatch.frame.minY)
            app.buttons["movementSessionBack"].tap()
            let alert = app.alerts[german ? "Aufnahme stoppen und zurückgehen?" : "Stop this recording and go back?"]
            XCTAssertTrue(alert.waitForExistence(timeout: 3))
            alert.buttons[german ? "Stoppen und zurück" : "Stop and go back"].tap()
            XCTAssertTrue(play.waitForExistence(timeout: 8))
            XCTAssertEqual(demo.value as? String, initialTime)
            app.buttons["movementSkipMeasurement"].tap()
            if index == 3 {
                XCTAssertFalse(app.descendants(matching: .any)["movementDemonstration-fist_right"].firstMatch.exists)
            }
        }
        app.terminate()
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
            let record = app.buttons["movementStartRecording"]
            XCTAssertTrue(record.waitForExistence(timeout: 5))
            XCTAssertTrue(record.isHittable)
            XCTAssertLessThanOrEqual(record.frame.maxY, app.tabBars.firstMatch.frame.minY)
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
            let taskTitle = app.staticTexts["movementRecordingTask"]
            let preview = app.descendants(matching: .any)["movementCameraPreview"].firstMatch
            XCTAssertEqual(taskTitle.label, step <= 2 ? (german ? "Finger-Tapping" : "Finger Tapping")
                           : (german ? "Hand öffnen/schließen" : "Hand Open/Close"))
            XCTAssertLessThanOrEqual(taskTitle.frame.maxY, preview.frame.minY)
            let stop = app.buttons[german ? "Stopp" : "Stop"]
            XCTAssertTrue(stop.waitForExistence(timeout: 8))
            XCTAssertTrue(stop.isHittable)
            XCTAssertGreaterThanOrEqual(stop.frame.height, 54)
            XCTAssertTrue(instruction.isHittable)
            XCTAssertLessThanOrEqual(instruction.frame.maxY, app.tabBars.firstMatch.frame.minY)
            let clip = "\(step <= 2 ? "finger_tapping" : "fist")_\(step % 2 == 1 ? "right" : "left")"
            let demo = app.descendants(matching: .any)["movementDemonstration-\(clip)"].firstMatch
            XCTAssertTrue(demo.exists)
            XCTAssertFalse(app.staticTexts[german ? "Demnächst verfügbar" : "Coming soon"].exists)
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
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
        for _ in 0..<10 where !button.isHittable || button.frame.maxY > app.tabBars.firstMatch.frame.minY {
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(button.isHittable)
        XCTAssertLessThanOrEqual(button.frame.maxY, app.tabBars.firstMatch.frame.minY)
        XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        return button
    }

    @MainActor
    func testRecordingFeedbackAndReachableActionsEnglishGerman() throws {
        for (language, font) in [("en", "standard"), ("de", "extraLarge")] {
            for (scenario, english, german) in [
                ("missing", "No usable signal captured", "Kein nutzbares Signal erfasst"),
                ("gaps", "Signal has gaps", "Signal hat Lücken"),
                ("noCycles", "No complete repetitions detected", "Keine vollständigen Wiederholungen erkannt"),
                ("lowIndex", "Recording captured", "Aufnahme erfasst")
            ] {
                let app = XCUIApplication()
                let arguments = ["--ui-test-session-save", UUID().uuidString,
                                 "-appLanguage", language, "-appFontSize", font]
                app.launchArguments = arguments + ["--ui-test-save-result", "--ui-test-recording-feedback", scenario]
                app.launch()
                app.tabBars.buttons[language == "de" ? "Bewegung" : "Movement"].tap()
                let feedback = app.descendants(matching: .any)["movementRecordingFeedback"].firstMatch
                XCTAssertTrue(feedback.waitForExistence(timeout: 5))
                XCTAssertEqual(feedback.label, language == "de" ? german : english)
                XCTAssertTrue(feedback.isHittable)
                XCTAssertLessThanOrEqual(feedback.frame.maxX, app.frame.maxX - 16)
                for id in ["movementSaveContinue", "movementSaveFinish", "movementRetake"] {
                    let action = app.buttons[id]
                    XCTAssertTrue(action.isHittable)
                    XCTAssertGreaterThanOrEqual(action.frame.height, 44)
                    XCTAssertLessThanOrEqual(action.frame.maxY, app.tabBars.firstMatch.frame.minY)
                }
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "Recording feedback \(scenario) \(language) \(font)"
                screenshot.lifetime = .keepAlways
                add(screenshot)
                if scenario == "missing" {
                    app.buttons["movementSaveFinish"].tap()
                    XCTAssertTrue(app.staticTexts["movementSavedSummary"].waitForExistence(timeout: 5))
                    app.buttons["movementSummaryDone"].tap()
                    expectSavedCounts("sessions=1;trials=1", in: app)
                    app.buttons["Trends"].tap()
                    XCTAssertTrue(app.descendants(matching: .any)["trendUnavailable"].firstMatch.waitForExistence(timeout: 5))
                    XCTAssertFalse(app.staticTexts["trendSingleValue"].exists)
                }
                app.terminate()
            }
        }
    }

    @MainActor
    func testTrailingTrackingLossWarnsAndStillAllowsSaveEnglishGerman() throws {
        for (language, font) in [("en", "standard"), ("de", "extraLarge")] {
            let german = language == "de"
            let app = XCUIApplication()
            let arguments = ["--ui-test-session-save", UUID().uuidString,
                             "-appLanguage", language, "-appFontSize", font]
            app.launchArguments = arguments + ["--ui-test-save-result", "--ui-test-recording-feedback", "trailingGap"]
            app.launch()
            app.tabBars.buttons[german ? "Bewegung" : "Movement"].tap()
            let feedback = app.descendants(matching: .any)["movementRecordingFeedback"].firstMatch
            XCTAssertTrue(feedback.waitForExistence(timeout: 5))
            XCTAssertEqual(feedback.label, german ? "Signal hat Lücken" : "Signal has gaps")
            let warning = XCTAttachment(screenshot: app.screenshot())
            warning.name = "Trailing signal loss \(language) \(font)"
            warning.lifetime = .keepAlways
            add(warning)
            let frequency = app.descendants(matching: .any)["movementResultMetric-frequency"].firstMatch
            revealMovementControl(frequency, in: app)
            XCTAssertEqual(frequency.value as? String, german ? "2,00 Hz" : "2.00 Hz")
            let gapExplanation = app.staticTexts["movementResultSignalGap"]
            revealMovementControl(gapExplanation, in: app)
            XCTAssertEqual(gapExplanation.label, german ? "In den Lücken wurde kein Signal erfasst."
                                                       : "Gaps mean no signal was captured during those intervals.")
            showSaveAction("movementRetake", in: app).tap()
            let alert = app.alerts[german ? "Diese Aufnahme wiederholen?" : "Retake this recording?"]
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            alert.buttons[german ? "Dieses Ergebnis behalten" : "Keep this result"].tap()
            showSaveAction("movementSaveFinish", in: app).tap()
            XCTAssertTrue(app.staticTexts["movementSavedSummary"].waitForExistence(timeout: 5))
            app.buttons["movementSummaryDone"].tap()
            expectSavedCounts("sessions=1;trials=1", in: app)
            app.terminate()
            app.launchArguments = arguments
            app.launch()
            app.tabBars.buttons[german ? "Bewegung" : "Movement"].tap()
            expectSavedCounts("sessions=1;trials=1", in: app)
            app.terminate()
        }
    }

    @MainActor
    func testRetakeConfirmsAndPreservesPreviouslyAcceptedRecording() throws {
        let app = XCUIApplication()
        let arguments = ["--ui-test-session-save", UUID().uuidString,
                         "-appLanguage", "de", "-appFontSize", "extraLarge"]
        app.launchArguments = arguments + ["--ui-test-save-result"]
        app.launch()
        app.tabBars.buttons["Bewegung"].tap()
        app.buttons["movementSaveContinue"].tap()
        XCTAssertTrue(app.staticTexts["Schritt 2 von 6"].waitForExistence(timeout: 5))
        let record = app.buttons["Aufnahme starten"]
        revealMovementControl(record, in: app)
        record.tap()
        XCTAssertTrue(app.buttons["Stopp"].waitForExistence(timeout: 8))
        app.buttons["Stopp"].tap()
        XCTAssertTrue(app.buttons["movementRetake"].waitForExistence(timeout: 15))
        app.buttons["movementRetake"].tap()
        let alert = app.alerts["Diese Aufnahme wiederholen?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Dieses Ergebnis behalten"].tap()
        XCTAssertTrue(app.buttons["movementSaveFinish"].exists)
        app.buttons["movementRetake"].tap()
        alert.buttons["Wiederholen"].tap()
        XCTAssertTrue(app.staticTexts["Schritt 2 von 6"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Gespeicherte Aufnahmen: 2 / 6"].exists)
        XCTAssertFalse(app.buttons["movementRetake"].exists)
        revealMovementControl(record, in: app)
        record.tap()
        XCTAssertTrue(app.buttons["Stopp"].waitForExistence(timeout: 8))
        app.buttons["Stopp"].tap()
        XCTAssertTrue(app.buttons["movementSaveFinish"].waitForExistence(timeout: 15))
        app.buttons["movementSaveFinish"].tap()
        XCTAssertTrue(app.staticTexts["movementSavedSummary"].waitForExistence(timeout: 5))
        app.buttons["movementSummaryDone"].tap()
        expectSavedCounts("sessions=1;trials=2", in: app)
        app.terminate()
        app.launchArguments = arguments
        app.launch()
        app.tabBars.buttons["Bewegung"].tap()
        expectSavedCounts("sessions=1;trials=2", in: app)
    }

    @MainActor
    func testResultMetricsAndRawPlotGermanLargeText() throws {
        for scenario in ["missing", "gaps", "lowIndex"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-test-session-save", UUID().uuidString, "--ui-test-save-result",
                                   "--ui-test-recording-feedback", scenario,
                                   "-appLanguage", "de", "-appFontSize", "extraLarge"]
            app.launch()
            app.tabBars.buttons["Bewegung"].tap()
            let duration = app.descendants(matching: .any)["movementResultDuration"].firstMatch
            revealMovementControl(duration, in: app)
            XCTAssertEqual(duration.value as? String, scenario == "missing" ? "Wert nicht verfügbar"
                           : scenario == "gaps" ? "10.2 s" : "30.0 s")
            let frequency = app.descendants(matching: .any)["movementResultMetric-frequency"].firstMatch
            revealMovementControl(frequency, in: app)
            XCTAssertEqual(frequency.value as? String, scenario == "missing" ? "Wert nicht verfügbar" : "2,00 Hz")
            let metricShot = XCTAttachment(screenshot: app.screenshot())
            metricShot.name = "Result metric rows \(scenario) German large text"
            metricShot.lifetime = .keepAlways
            add(metricShot)
            let index = app.descendants(matching: .any)["movementResultMetric-quality"].firstMatch
            XCTAssertFalse(index.exists)
            let plot = app.descendants(matching: .any)["movementResultSignal"].firstMatch
            revealMovementControl(plot, in: app)
            let signalShot = XCTAttachment(screenshot: app.screenshot())
            signalShot.name = "Result raw signal \(scenario) German large text"
            signalShot.lifetime = .keepAlways
            add(signalShot)
            if scenario == "gaps" {
                let gapExplanation = app.staticTexts["movementResultSignalGap"]
                revealMovementControl(gapExplanation, in: app)
                XCTAssertEqual(gapExplanation.label, "In den Lücken wurde kein Signal erfasst.")
            }
            XCTAssertTrue(app.buttons["movementRetake"].isHittable)
            app.terminate()
        }
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
            let history = app.buttons["trendRecordingHistory"]
            for _ in 0..<10 where !history.isHittable {
                app.collectionViews.firstMatch.swipeUp()
            }
            history.tap()
            XCTAssertTrue(app.staticTexts["trendRecordingValue"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["trendRecordingValue"].firstMatch.label, language == "de" ? "2,0 Taps/s" : "2.0 taps/s")
            app.terminate()
        }
    }

    @MainActor
    func testConciseVideoDeletionPromptsEnglishGerman() throws {
        for language in ["en", "de"] {
            let german = language == "de"
            let app = XCUIApplication()
            app.launchArguments = ["--ui-test-session-save", UUID().uuidString, "--ui-test-video-library",
                                   "-appLanguage", language, "-appFontSize", german ? "extraLarge" : "standard"]
            app.launch()
            app.tabBars.buttons[german ? "Einstellungen" : "Settings"].tap()
            let data = app.staticTexts[german ? "Daten" : "Data"]
            revealMovementControl(data, in: app)
            data.tap()
            let video = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "movementOpenVideo_")).firstMatch
            XCTAssertTrue(video.waitForExistence(timeout: 15))
            revealMovementControl(video, in: app)
            video.tap()
            let delete = app.buttons["movementDeleteVideo"]
            XCTAssertTrue(delete.waitForExistence(timeout: 10))
            delete.tap()
            let single = german
                ? "Diese gespeicherte Kopie wird endgültig von diesem iPhone gelöscht. Dies lässt sich nicht rückgängig machen."
                : "This saved copy will be permanently deleted from this phone. This cannot be undone."
            XCTAssertTrue(app.alerts.staticTexts[single].waitForExistence(timeout: 5))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Concise video deletion \(language)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.alerts.buttons[german ? "Abbrechen" : "Cancel"].tap()
            XCTAssertTrue(app.buttons["movementShareVideo"].exists)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.buttons["movementSelectVideos"].tap()
            let choice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "movementSelectVideo_")).firstMatch
            revealMovementControl(choice, in: app)
            choice.tap()
            app.buttons["movementDeleteVideos"].tap()
            let multiple = german
                ? "Diese gespeicherten Kopien werden endgültig von diesem iPhone gelöscht. Dies lässt sich nicht rückgängig machen."
                : "These saved copies will be permanently deleted from this phone. This cannot be undone."
            XCTAssertTrue(app.alerts.staticTexts[multiple].waitForExistence(timeout: 5))
            app.alerts.buttons[german ? "Abbrechen" : "Cancel"].tap()
            XCTAssertTrue(app.buttons["movementFinishSelection"].exists)
            app.terminate()
        }
    }

    @MainActor
    func testJournalNoteExampleEnglishGerman() throws {
        for language in ["en", "de"] {
            let german = language == "de"
            let app = XCUIApplication()
            app.launchArguments = ["--ui-test-session-save", UUID().uuidString,
                                   "-appLanguage", language, "-appFontSize", german ? "extraLarge" : "standard"]
            func openToday() {
                app.tabBars.buttons["Journal"].tap()
                let today = app.buttons[german ? "HEUTIGES PROTOKOLL ÖFFNEN" : "OPEN TODAY'S LOG"]
                revealMovementControl(today, in: app)
                today.tap()
            }
            app.launch()
            openToday()
            let addNote = app.buttons[german ? "NOTIZ HINZUFÜGEN" : "ADD NOTE"]
            revealMovementControl(addNote, in: app)
            addNote.tap()
            let field = app.descendants(matching: .any)["journalNoteField"]
            let save = app.buttons["journalSaveNote"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            let examples = german
                ? ["Zum Beispiel: Heute fühle ich mich stark.", "Zum Beispiel: Heute bin ich niedergeschlagen.",
                   "Zum Beispiel: Ich habe letzte Nacht gut geschlafen.", "Zum Beispiel: Das Gehen fiel mir heute leichter.",
                   "Zum Beispiel: Heute brauchte ich mehr Pausen.", "Zum Beispiel: Heute war ein ruhiger Tag."]
                : ["For example: Today I feel strong.", "For example: My mood is low today.",
                   "For example: I slept well last night.", "For example: Walking felt easier today.",
                   "For example: I needed more breaks today.", "For example: Today was a quiet day."]
            let example = try XCTUnwrap(field.placeholderValue)
            XCTAssertTrue(examples.contains(example))
            XCTAssertTrue(["", example].contains(field.value as? String ?? ""))
            XCTAssertFalse(save.isEnabled)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Empty Notes example \(language)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            field.tap()
            field.typeText("   ")
            XCTAssertFalse(save.isEnabled)
            XCTAssertNotEqual(field.value as? String, example)
            XCTAssertTrue(["", example].contains(field.placeholderValue ?? ""))
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
            XCTAssertTrue(["", example].contains(field.value as? String ?? ""))
            XCTAssertTrue(["", example].contains(field.placeholderValue ?? ""))
            XCTAssertFalse(save.isEnabled)
            let note = "Journal UI test \(UUID().uuidString)"
            field.typeText("  \(note)  ")
            XCTAssertEqual((field.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), note)
            XCTAssertTrue(["", example].contains(field.placeholderValue ?? ""))
            XCTAssertTrue(save.isEnabled)
            save.tap()
            XCTAssertFalse(field.exists)
            let saved = app.staticTexts[note]
            revealMovementControl(saved, in: app)
            XCTAssertTrue(saved.exists)
            XCTAssertFalse(app.staticTexts[example].exists)
            app.terminate()
            app.launch()
            openToday()
            revealMovementControl(app.staticTexts[note], in: app)
            XCTAssertTrue(app.staticTexts[note].exists)
            let anotherNote = app.buttons[german ? "NOTIZ HINZUFÜGEN" : "ADD NOTE"]
            let scroll = app.scrollViews.firstMatch
            for _ in 0..<12 where !anotherNote.exists { scroll.swipeDown() }
            revealMovementControl(anotherNote, in: app)
            anotherNote.tap()
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            XCTAssertTrue(examples.contains(try XCTUnwrap(field.placeholderValue)))
            XCTAssertFalse(save.isEnabled)
            app.terminate()
        }
    }

    @MainActor
    func testCalendarLegendEnglishGermanLargeText() throws {
        for language in ["en", "de"] {
            let german = language == "de"
            let app = XCUIApplication()
            app.launchArguments = ["--ui-test-session-save", UUID().uuidString,
                                   "-appLanguage", language, "-appFontSize", german ? "extraLarge" : "standard"]
            app.launch()
            app.tabBars.buttons["Journal"].tap()
            let keys = german ? ["vCR-Eintrag", "Journaleintrag", "Bewegungssitzung", "Ausgewählter Tag"]
                : ["vCR log", "Journal entry", "Movement session", "Selected day"]
            for key in keys {
                let label = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", key)).firstMatch
                revealMovementControl(label, in: app)
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Calendar legend \(language)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let day = app.buttons["journalCalendarDay-1"]
            revealMovementControl(day, in: app)
            XCTAssertFalse(day.label == "1")
            let now = Date()
            let firstDay = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now))!
            let expectedDate = firstDay.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(Locale(identifier: language)))
            XCTAssertEqual(day.label, expectedDate)
            day.tap()
            XCTAssertTrue(day.isSelected)
            let openLog = app.buttons[german ? "TAGESPROTOKOLL ÖFFNEN" : "OPEN DAILY LOG"]
            revealMovementControl(openLog, in: app)
            openLog.tap()
            XCTAssertTrue(app.navigationBars.firstMatch.buttons.element(boundBy: 0).waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testVideoLibraryLongPressBatchShareDeleteEnglishGerman() throws {
        for language in ["en", "de"] {
            let german = language == "de"
            let app = XCUIApplication()
            let arguments = ["--ui-test-session-save", UUID().uuidString, "-appLanguage", language,
                             "-appFontSize", german ? "extraLarge" : "standard"]
            func openData() {
                app.tabBars.buttons[german ? "Einstellungen" : "Settings"].tap()
                let title = app.staticTexts[german ? "Daten" : "Data"]
                for _ in 0..<8 where !title.isHittable { app.swipeUp() }
                title.tap()
            }
            func rows(_ prefix: String) -> XCUIElementQuery {
                app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            }
            func videoIDs(_ prefix: String, expected: Int) -> [String] {
                var ids: [String] = []
                let scroll = app.collectionViews.firstMatch
                // Form loads only visible rows at accessibility text sizes.
                for _ in 0..<8 {
                    for row in rows(prefix).allElementsBoundByIndex where !ids.contains(row.identifier) {
                        ids.append(row.identifier)
                    }
                    if ids.count >= expected { break }
                    scroll.swipeUp()
                }
                let heading = app.staticTexts[german ? "Aufgezeichnete Daten" : "Recorded data"]
                for _ in 0..<8 where !heading.isHittable { scroll.swipeDown() }
                return ids
            }
            app.launchArguments = arguments + ["--ui-test-video-library"]
            app.launch()
            openData()
            XCTAssertTrue(rows("movementOpenVideo_").firstMatch.waitForExistence(timeout: 15))
            let ids = videoIDs("movementOpenVideo_", expected: 4)
            XCTAssertEqual(ids.count, 4)
            guard ids.count == 4 else { return }
            XCTAssertFalse(app.buttons["movementDeleteVideos"].exists)
            XCTAssertFalse(app.buttons["movementSelectLatestVideos"].exists)
            let first = app.buttons[ids[0]]
            revealMovementControl(first, in: app)
            first.press(forDuration: 1.2)
            app.buttons[german ? "Videos auswählen" : "Select videos"].tap()
            let firstChoice = app.buttons[ids[0].replacingOccurrences(of: "movementOpenVideo_", with: "movementSelectVideo_")]
            XCTAssertEqual(firstChoice.value as? String, german ? "Ausgewählt" : "Selected")
            let secondChoice = app.buttons[ids[1].replacingOccurrences(of: "movementOpenVideo_", with: "movementSelectVideo_")]
            revealMovementControl(secondChoice, in: app)
            secondChoice.tap()
            let share = app.buttons["movementShareVideos"]
            XCTAssertTrue(share.isEnabled && share.isHittable)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Multiple video selection \(language)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            share.tap()
            XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5))
            app.terminate()
            app.launchArguments = arguments
            app.launch()
            openData()
            XCTAssertEqual(videoIDs("movementOpenVideo_", expected: 4).count, 4)
            app.buttons["movementSelectVideos"].tap()
            revealMovementControl(firstChoice, in: app)
            firstChoice.tap()
            revealMovementControl(secondChoice, in: app)
            secondChoice.tap()
            let delete = app.buttons["movementDeleteVideos"]
            XCTAssertTrue(delete.isHittable)
            delete.tap()
            app.alerts.buttons[german ? "Abbrechen" : "Cancel"].tap()
            XCTAssertEqual(videoIDs("movementSelectVideo_", expected: 4).count, 4)
            delete.tap()
            app.alerts.buttons[german ? "Videos löschen" : "Delete videos"].tap()
            let deletionMessage = app.staticTexts[german ? "Videos gelöscht: 2. Messungen bleiben erhalten."
                                                          : "Videos deleted: 2. Measurements kept."]
            revealMovementControl(deletionMessage, in: app)
            app.buttons["movementFinishSelection"].tap()
            XCTAssertEqual(videoIDs("movementOpenVideo_", expected: 2).count, 2)
            app.terminate()
            app.launchArguments = arguments
            app.launch()
            openData()
            XCTAssertEqual(videoIDs("movementOpenVideo_", expected: 2).count, 2)
            app.terminate()
        }
    }

    @MainActor
    func testPrivateVideoSavePlaybackAndRelaunchEnglishGerman() throws {
        for language in ["en", "de"] {
            let app = XCUIApplication()
            let arguments = ["--ui-test-session-save", UUID().uuidString,
                "-appLanguage", language, "-appFontSize", language == "de" ? "extraLarge" : "standard"]
            app.launchArguments = arguments + ["--ui-test-save-result", "--ui-test-private-video"]
            app.launch()
            app.tabBars.buttons[language == "de" ? "Bewegung" : "Movement"].tap()
            XCTAssertTrue(app.staticTexts["movementAutosaveStatus"].waitForExistence(timeout: 15))
            let notice = app.staticTexts["movementVideoNotice"]
            revealMovementControl(notice, in: app)
            showSaveAction("movementSaveFinish", in: app).tap()
            XCTAssertTrue(app.staticTexts["movementSavedSummary"].waitForExistence(timeout: 10))
            let link = app.buttons["movementSavedVideo"]
            revealMovementControl(link, in: app)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Private video saved \(language)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            link.tap()
            XCTAssertTrue(app.otherElements["movementVideoPlayer"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.alerts.firstMatch.exists)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.staticTexts["movementSavedSummary"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["movementSavedVideo"].exists)
            app.tabBars.buttons[language == "de" ? "Einstellungen" : "Settings"].tap()
            app.tabBars.buttons[language == "de" ? "Bewegung" : "Movement"].tap()
            XCTAssertTrue(app.staticTexts["movementSavedSummary"].waitForExistence(timeout: 5))
            revealMovementControl(link, in: app)
            link.tap()
            XCTAssertTrue(app.otherElements["movementVideoPlayer"].waitForExistence(timeout: 10))
            let share = app.buttons["movementShareVideo"]
            XCTAssertTrue(share.isHittable)
            XCTAssertLessThanOrEqual(share.frame.maxY, app.tabBars.firstMatch.frame.minY)
            share.tap()
            let shareSheet = app.otherElements["ActivityListView"]
            XCTAssertTrue(shareSheet.waitForExistence(timeout: 5))
            app.terminate()
            app.launchArguments = arguments
            app.launch()
            app.tabBars.buttons[language == "de" ? "Einstellungen" : "Settings"].tap()
            let export = app.buttons.containing(.staticText, identifier:
                language == "de" ? "Daten" : "Data").firstMatch
            // Settings rows are NavigationLinks; find by their existing title.
            let title = app.staticTexts[language == "de" ? "Daten" : "Data"]
            for _ in 0..<8 where !title.isHittable { app.swipeUp() }
            if export.exists { export.tap() } else { title.tap() }
            let recording = app.buttons.containing(.staticText, identifier:
                language == "de" ? "Finger-Tapping · Rechts" : "Finger Tapping · Right").firstMatch
            XCTAssertTrue(recording.waitForExistence(timeout: 10))
            revealMovementControl(recording, in: app)
            recording.tap()
            XCTAssertTrue(app.otherElements["movementVideoPlayer"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["movementShareVideo"].isHittable)
            let delete = app.buttons["movementDeleteVideo"]
            XCTAssertTrue(delete.isHittable)
            XCTAssertLessThanOrEqual(delete.frame.maxY, app.tabBars.firstMatch.frame.minY)
            delete.tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
            app.alerts.buttons[language == "de" ? "Abbrechen" : "Cancel"].tap()
            XCTAssertTrue(app.otherElements["movementVideoPlayer"].exists)
            delete.tap()
            let deletionScreenshot = XCTAttachment(screenshot: app.screenshot())
            deletionScreenshot.name = "Confirm player video deletion \(language)"
            deletionScreenshot.lifetime = .keepAlways
            add(deletionScreenshot)
            app.alerts.buttons[language == "de" ? "Video löschen" : "Delete video"].tap()
            XCTAssertTrue(app.otherElements["movementNoSavedVideos"].waitForExistence(timeout: 10)
                || app.staticTexts["movementNoSavedVideos"].exists)
            XCTAssertFalse(recording.exists)
            app.terminate()
            app.launchArguments = arguments
            app.launch()
            app.tabBars.buttons[language == "de" ? "Einstellungen" : "Settings"].tap()
            let dataTitle = app.staticTexts[language == "de" ? "Daten" : "Data"]
            for _ in 0..<8 where !dataTitle.isHittable { app.swipeUp() }
            dataTitle.tap()
            XCTAssertTrue(app.otherElements["movementNoSavedVideos"].waitForExistence(timeout: 10)
                || app.staticTexts["movementNoSavedVideos"].exists)
            XCTAssertFalse(app.buttons["movementManageVideos"].exists)
            app.terminate()
        }
    }

    @MainActor
    func testFailedVideoSaveOffersMeasurementOnlyWithoutLosingResult() throws {
        let app = XCUIApplication()
        let arguments = ["--ui-test-session-save", UUID().uuidString,
                         "-appLanguage", "de", "-appFontSize", "standard"]
        app.launchArguments = arguments + ["--ui-test-save-result", "--ui-test-private-video",
                                           "--ui-test-video-save-failure"]
        app.launch()
        app.tabBars.buttons["Bewegung"].tap()
        let alert = app.alerts["Aufnahme nicht gespeichert"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["Ohne Video speichern"].tap()
        XCTAssertTrue(app.staticTexts["movementAutosaveStatus"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["movementVideoNotice"].label,
                       "Video nicht gespeichert. Ihr Messwert ist gespeichert.")
        XCTAssertFalse(app.staticTexts["movementSavedSummary"].exists)
        showSaveAction("movementSaveFinish", in: app).tap()
        XCTAssertTrue(app.staticTexts["movementSavedSummary"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["movementSavedVideo"].exists)
        app.buttons["movementSummaryDone"].tap()
        expectSavedCounts("sessions=1;trials=1", in: app)
    }

    @MainActor
    func testPrivateVideoRetakeKeepsSavedTakeUntilReplacement() throws {
        let app = XCUIApplication()
        let arguments = ["--ui-test-session-save", UUID().uuidString,
                         "-appLanguage", "en", "-appFontSize", "standard"]
        app.launchArguments = arguments + ["--ui-test-save-result", "--ui-test-private-video"]
        app.launch()
        app.tabBars.buttons["Movement"].tap()
        XCTAssertTrue(app.staticTexts["movementAutosaveStatus"].waitForExistence(timeout: 15))
        showSaveAction("movementRetake", in: app).tap()
        let alert = app.alerts["Retake this recording?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Retake"].tap()
        XCTAssertTrue(app.staticTexts["Step 1 of 6"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = arguments
        app.launch()
        app.tabBars.buttons["Movement"].tap()
        expectSavedCounts("sessions=1;trials=1", in: app)
        app.tabBars.buttons["Settings"].tap()
        let export = app.staticTexts["Data"]
        for _ in 0..<8 where !export.isHittable { app.swipeUp() }
        XCTAssertTrue(export.isHittable)
        export.tap()
        XCTAssertTrue(app.staticTexts["Recorded videos"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["movementNoSavedVideos"].firstMatch.exists)
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Finger Tapping · Right").firstMatch.exists)
        XCTAssertFalse(app.buttons["movementShareVideo"].exists)
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
        let initialAlert = app.alerts["Aufnahme nicht gespeichert"]
        XCTAssertTrue(initialAlert.waitForExistence(timeout: 10))
        initialAlert.buttons["OK"].tap()
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
    func testCompletedResultSavesAutomaticallyAndSurvivesLeavingAndRelaunch() throws {
        let app = XCUIApplication()
        let arguments = ["--ui-test-session-save", UUID().uuidString,
                         "-appLanguage", "en", "-appFontSize", "standard"]
        app.launchArguments = arguments + ["--ui-test-save-result"]
        app.launch()
        app.tabBars.buttons["Movement"].tap()
        XCTAssertTrue(app.navigationBars["Result"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["movementAutosaveStatus"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()
        app.tabBars.buttons["Movement"].tap()
        XCTAssertTrue(app.navigationBars["Result"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = arguments
        app.launch()
        app.tabBars.buttons["Movement"].tap()
        expectSavedCounts("sessions=1;trials=1", in: app)
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
            ? "Für jede neue Sitzung empfehlen wir, erneut zu kalibrieren."
            : "For each new session, we recommend recalibrating."]
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
