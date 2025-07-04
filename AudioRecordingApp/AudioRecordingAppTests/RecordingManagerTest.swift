//
//  RecordingManagerTest.swift
//  AudioRecordingAppTests
//
//  Created by Shambhavi Seth on 7/4/25.
//

import XCTest
@testable import AudioRecordingApp

class RecordingManagerTests: XCTestCase {
    func testFetchRecordingsDoesNotCrash() {
        let manager = RecordingManager.shared
        manager.fetchRecordings()
        XCTAssertNotNil(manager.recordings)
    }

    func testDeleteNonexistentFileGracefully() {
        let fakeURL = FileManager.default.temporaryDirectory.appendingPathComponent("nonexistent.m4a")
        XCTAssertNoThrow(RecordingManager.shared.deleteRecording(url: fakeURL))
    }
}
