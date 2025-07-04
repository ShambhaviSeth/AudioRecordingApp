//
//  AudioSegmentProcessorTests.swift
//  AudioRecordingAppTests
//
//  Created by Shambhavi Seth on 7/4/25.
//

import XCTest
@testable import AudioRecordingApp
import AVFAudio

class AudioSegmentProcessorTests: XCTestCase {
    func testPreprocessingProducesValidOutput() throws {
        let processor = AudioSegmentProcessor.shared
        let input = Bundle(for: type(of: self)).url(forResource: "testAudio", withExtension: "m4a")!
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("processed.m4a")

        try processor.preprocessAudio(inputURL: input, outputURL: output)

        let fileExists = FileManager.default.fileExists(atPath: output.path)
        XCTAssertTrue(fileExists, "Processed file should exist.")
    }

    func testVoiceActivityDetectionLowEnergyReturnsFalse() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        buffer.floatChannelData?.pointee.initialize(repeating: 0.00001, count: 1024)

        let result = AudioSegmentProcessor.shared.detectVoiceActivity(in: buffer)
        XCTAssertFalse(result)
    }
}
