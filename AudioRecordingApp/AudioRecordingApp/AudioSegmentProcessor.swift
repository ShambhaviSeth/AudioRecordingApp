//
//  AudioSegmentProcessor.swift
//  AudioRecordingApp
//
//  Created by Shambhavi Seth on 7/3/25.
//

import Foundation
import Foundation
import AVFoundation
import Accelerate

class AudioSegmentProcessor {
    static let shared = AudioSegmentProcessor()
    
    private init() {}
    
    //Enhanced audio preprocessing for better transcription accuracy
    func preprocessAudio(inputURL: URL, outputURL: URL) throws {
        let audioFile = try AVAudioFile(forReading: inputURL)
        let format = audioFile.processingFormat
        
        //Create processing format (16kHz, mono for optimal Whisper performance)
        let processingFormat = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        )!
        
        let converter = AVAudioConverter(from: format, to: processingFormat)!
        
        //Read input audio
        let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(audioFile.length)
        )!
        
        try audioFile.read(into: inputBuffer)
        
        //Convert to processing format
        let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: processingFormat,
            frameCapacity: AVAudioFrameCount(Double(inputBuffer.frameLength) * processingFormat.sampleRate / format.sampleRate)
        )!
        
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        
        if let error = error {
            throw error
        }
        
        //Apply noise reduction and normalization
        let processedBuffer = try applyAudioEnhancements(buffer: outputBuffer)
        
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: processingFormat.settings
        )
        
        try outputFile.write(from: processedBuffer)
    }
    
    private func applyAudioEnhancements(buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let channelData = buffer.floatChannelData?[0] else {
            throw NSError(domain: "AudioProcessingError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No channel data"])
        }
        
        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        
        let filteredSamples = applyHighPassFilter(samples: samples, sampleRate: buffer.format.sampleRate)

        let normalizedSamples = normalizeAudio(samples: filteredSamples)
        
        let outputBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity)!
        outputBuffer.frameLength = buffer.frameLength
        
        guard let outputChannelData = outputBuffer.floatChannelData?[0] else {
            throw NSError(domain: "AudioProcessingError", code: 2, userInfo: [NSLocalizedDescriptionKey: "No output channel data"])
        }
        
        normalizedSamples.withUnsafeBufferPointer { bufferPointer in
            outputChannelData.assign(from: bufferPointer.baseAddress!, count: frameCount)
        }
        
        return outputBuffer
    }
    
    private func applyHighPassFilter(samples: [Float], sampleRate: Double) -> [Float] {
        let cutoffFrequency: Float = 80.0
        let rc = 1.0 / (2.0 * .pi * cutoffFrequency)
        let dt = 1.0 / Float(sampleRate)
        let alpha = rc / (rc + dt)
        
        var filteredSamples = [Float]()
        var previousInput: Float = 0.0
        var previousOutput: Float = 0.0
        
        for sample in samples {
            let output = alpha * (previousOutput + sample - previousInput)
            filteredSamples.append(output)
            previousInput = sample
            previousOutput = output
        }
        
        return filteredSamples
    }
    
    private func normalizeAudio(samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }
        
        let maxAmplitude = samples.map { abs($0) }.max() ?? 1.0
        let targetAmplitude: Float = 0.8
        let scaleFactor = maxAmplitude > 0 ? targetAmplitude / maxAmplitude : 1.0
        
        return samples.map { $0 * scaleFactor }
    }
    
    //Detect voice activity to optimize segmentation
    func detectVoiceActivity(in buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.floatChannelData?[0] else { return false }
        
        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        
        //Calculate RMS energy
        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(frameCount))
        
        //Simple voice activity detection based on energy threshold
        let threshold: Float = 0.002
        return rms > threshold
    }
}
