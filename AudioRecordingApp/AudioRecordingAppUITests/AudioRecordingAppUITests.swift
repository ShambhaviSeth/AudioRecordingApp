//
//  AudioRecordingAppUITests.swift
//  AudioRecordingAppUITests
//
//  Created by Shambhavi Seth on 7/1/25.
//

import XCTest

final class AudioRecordingAppUITests: XCTestCase {

        var app: XCUIApplication!

        override func setUpWithError() throws {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments.append("--uitesting")
            app.launch()
        }

        func testStartAndStopRecording() {
            let recordButton = app.buttons["recordButton"]
            XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
            recordButton.tap()

            let recordingLabel = app.staticTexts["recordingStatusLabel"]
            XCTAssertTrue(recordingLabel.waitForExistence(timeout: 5))
            XCTAssertEqual(recordingLabel.label, "Recording...")

            recordButton.tap()
            XCTAssertEqual(recordingLabel.label, "Tap to Record")
        }

        func testSearchRecordings() {
            let searchField = app.textFields["Search recordings"]
            XCTAssertTrue(searchField.waitForExistence(timeout: 5))
            searchField.tap()
            searchField.typeText("Meeting")
            XCTAssertFalse(app.staticTexts["Meeting Notes"].exists)
        }

        func testRetryFailedTranscriptionsButton() {
            let retryButton = app.buttons["Retry Failed"]
            XCTAssertTrue(retryButton.waitForExistence(timeout: 5))
            retryButton.tap()
        }


        func testPlayRecording() {
            let playButtons = app.buttons.matching(identifier: "Play recording")
            if playButtons.count > 0 {
                let playButton = playButtons.firstMatch
                XCTAssertTrue(playButton.exists)
                playButton.tap()
                XCTAssertFalse(playButton.exists)
            }
        }

        func testNetworkStatusIndicator() {
            let onlineLabel = app.staticTexts["Online"]
            let offlineLabel = app.staticTexts["Offline"]

            XCTAssertTrue(onlineLabel.exists || offlineLabel.exists)
        }
    }
