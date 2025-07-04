//
//  TranscriptionManagerTest.swift
//  AudioRecordingAppTests
//
//  Created by Shambhavi Seth on 7/4/25.
//

import XCTest
@testable import AudioRecordingApp

class TranscriptionManagerTests: XCTestCase {
    func testCreateSegmentURLIncludesRecordingID() {
        let result = TranscriptionManager.shared.createSegmentURL(recordingID: "abc123", segmentIndex: 0)
        XCTAssertTrue(result.lastPathComponent.contains("segment-abc123-0"))
    }
    
    func testGetTranscriptionForRecordingReturnsCorrectText() {
        let session = RecordingSession(
            title: "Mock Session",
            audioFileURL: URL(fileURLWithPath: "/tmp/testAudio.m4a")
        )

        let segment1 = TranscriptionSegment(
            startTime: 0,
            endTime: 10,
            transcription: "Hello world",
            status: .completed,
            retryCount: 0,
            session: session,
            segmentURL: URL(fileURLWithPath: "/tmp/seg1.m4a")
        )

        let segment2 = TranscriptionSegment(
            startTime: 10,
            endTime: 20,
            transcription: "this is a test",
            status: .completed,
            retryCount: 0,
            session: session,
            segmentURL: URL(fileURLWithPath: "/tmp/seg2.m4a")
        )

        TranscriptionManager.shared.segments = [segment1, segment2]

        let combined = TranscriptionManager.shared.getTranscriptionForRecording(session.id.uuidString)

        XCTAssertEqual(combined, "Hello world this is a test")
    }
    
    func testGetTranscriptionForRecordingReturnsEmptyForNoSegments() {
        let session = RecordingSession(
            title: "Empty Session",
            audioFileURL: URL(fileURLWithPath: "/tmp/mock.m4a")
        )

        TranscriptionManager.shared.segments = []
        let result = TranscriptionManager.shared.getTranscriptionForRecording(session.id.uuidString)
        XCTAssertEqual(result, "")
    }

    func testClearCompletedSegments() {
        let session = RecordingSession(
            title: "Session",
            audioFileURL: URL(fileURLWithPath: "/tmp/file.m4a")
        )

        let completed = TranscriptionSegment(
            startTime: 0, endTime: 5,
            transcription: "done", status: .completed,
            retryCount: 0, session: session,
            segmentURL: URL(fileURLWithPath: "/tmp/1.m4a")
        )

        let failed = TranscriptionSegment(
            startTime: 5, endTime: 10,
            transcription: nil, status: .failed,
            retryCount: 2, session: session,
            segmentURL: URL(fileURLWithPath: "/tmp/2.m4a")
        )

        TranscriptionManager.shared.segments = [completed, failed]
        TranscriptionManager.shared.clearCompletedSegments()

        XCTAssertEqual(TranscriptionManager.shared.segments.count, 1)
        XCTAssertEqual(TranscriptionManager.shared.segments.first?.status, .failed)
    }

    func testCreateSegmentURLGeneratesCorrectPath() {
        let url1 = TranscriptionManager.shared.createSegmentURL(recordingID: "xyz", segmentIndex: 0)
        let url2 = TranscriptionManager.shared.createSegmentURL(recordingID: "xyz", segmentIndex: 1)
        
        XCTAssertNotEqual(url1, url2)
        XCTAssertTrue(url1.lastPathComponent.contains("segment-xyz-0"))
        XCTAssertTrue(url2.lastPathComponent.contains("segment-xyz-1"))
    }

}

