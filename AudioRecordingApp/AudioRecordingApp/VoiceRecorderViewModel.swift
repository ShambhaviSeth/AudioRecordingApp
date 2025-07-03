//
//  VoiceRecorderViewModel.swift
//  AudioRecordingApp
//
//  Created by Shambhavi Seth on 7/2/25.
//

import AVFoundation
import Combine
import SwiftUI

class VoiceRecorderViewModel: ObservableObject {
    static let shared = VoiceRecorderViewModel()

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var outputFile: AVAudioFile?
    private var cancellables = Set<AnyCancellable>()

    private(set) var audioSession = AVAudioSession.sharedInstance()
    private(set) var isRecording = CurrentValueSubject<Bool, Never>(false)
    private var recordingStartTime: Date?

    @Published var currentPower: Float = 0.0
    private var levelTimer: Timer?

    struct Settings {
        var sampleRate: Double = 44100
        var bitDepth: AVAudioCommonFormat = .pcmFormatInt16
        var format: AudioFormatID = kAudioFormatMPEG4AAC
    }
    var settings = Settings()

    private init() {
        setupNotifications()
    }

    //Configures the audio session for recording and playback
    func configureSession() throws {
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    //Register for system audio notifications
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in self?.handleInterruption(notification) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] notification in self?.handleRouteChange(notification) }
            .store(in: &cancellables)
    }

    //Begins a new audio recording session
    func startRecording() throws {
        try configureSession()

        let format = engine.inputNode.outputFormat(forBus: 0)

        //Create a unique file name
        let outputURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recording-\(UUID().uuidString).m4a")

        outputFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)

        //Start recording using a tap on the input node
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            do {
                try self.outputFile?.write(from: buffer)
                self.updateLevels(buffer: buffer)
            } catch {
                print("Error writing buffer: \(error)")
            }
        }

        try engine.start()
        isRecording.send(true)
        recordingStartTime = Date()
        startMonitoring()
    }

    //Ends the current recording session
    func stopRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording.send(false)
        outputFile = nil
        stopMonitoring()
        RecordingManager.shared.fetchRecordings()
    }


    //Starts a timer that periodically reads audio power levels from the input buffer
    private func startMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
        }
    }

    //Stops level monitoring and resets power
    private func stopMonitoring() {
        levelTimer?.invalidate()
        currentPower = 0.0
    }

    //Computes audio power level from buffer and updates the UI.
    private func updateLevels(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let channelDataArray = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
        let rms = sqrt(channelDataArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        let avgPower = 20 * log10(rms)

        DispatchQueue.main.async {
            self.currentPower = avgPower
        }
    }

    //Handles system interruptions like phone calls or Siri
    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            print("Interruption began — stopping recording")
            stopRecording()
        case .ended:
            try? configureSession()
            if let options = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                print("Resuming recording after interruption")
                try? startRecording()
            }
        default:
            break
        }
    }

    //Handles audio route changes like plugging/unplugging headphones
    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        switch reason {
        case .oldDeviceUnavailable:
            print("Headphones unplugged — stopping recording")
            stopRecording()
        case .newDeviceAvailable:
            print("New audio device available")
        default:
            break
        }
    }
}
