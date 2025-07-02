//
//  VoiceRecorderViewModel.swift
//  AudioRecordingApp
//
//  Created by Shambhavi Seth on 7/2/25.
//

import SwiftUI
import AVFoundation

class VoiceRecorderViewModel: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var recordings: [URL] = []

    var audioRecorder: AVAudioRecorder?
    var audioPlayer: AVAudioPlayer?

    override init() {
        super.init()
        fetchRecordings()
    }

    func startRecording() {
        let recordingSession = AVAudioSession.sharedInstance()

        do {
            try recordingSession.setCategory(.playAndRecord, mode: .default)
            try recordingSession.setActive(true)

            let url = getNewRecordingURL()
            let settings = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()

            isRecording = true
        } catch {
            print("Failed to start recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        fetchRecordings()
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    func fetchRecordings() {
        let fileManager = FileManager.default
        let documents = getDocumentsDirectory()

        do {
            let urls = try fileManager.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil)
            recordings = urls.filter { $0.pathExtension == "m4a" }.sorted(by: { $0.lastPathComponent > $1.lastPathComponent })
        } catch {
            print("Failed to fetch recordings: \(error)")
        }
    }

    func playRecording(url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("Playback failed: \(error.localizedDescription)")
        }
    }

    // Helpers
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func getNewRecordingURL() -> URL {
        let timestamp = Date().timeIntervalSince1970
        return getDocumentsDirectory().appendingPathComponent("Recording-\(timestamp).m4a")
    }
}

