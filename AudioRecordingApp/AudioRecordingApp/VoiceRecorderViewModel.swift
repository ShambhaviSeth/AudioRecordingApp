////  VoiceRecorderViewModel.swift
////  AudioRecordingApp
////
////  Created by Shambhavi Seth on 7/2/25.
//
import AVFoundation
import Combine
import SwiftUI
import SwiftData

class VoiceRecorderViewModel: ObservableObject {
    static let shared = VoiceRecorderViewModel()

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var outputFile: AVAudioFile?
    private var cancellables = Set<AnyCancellable>()

    // Current recording tracking
    private var currentRecordingID: String?
    private var currentRecordingURL: URL?
    private var modelContext: ModelContext?

    private(set) var audioSession = AVAudioSession.sharedInstance()
    private(set) var isRecording = CurrentValueSubject<Bool, Never>(false)
    private var recordingStartTime: Date?

    @Published var currentPower: Float = 0.0
    @Published var currentlyPlaying: URL? = nil
    private var levelTimer: Timer?


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
    func startRecording(context: ModelContext) throws {
        self.modelContext = context
        try configureSession()

        let format = engine.inputNode.outputFormat(forBus: 0)

        //Generate unique recording ID
        currentRecordingID = UUID().uuidString

        //Create a unique file name
        let outputURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recording-\(currentRecordingID!).m4a")

        currentRecordingURL = outputURL
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

    func stopRecording(context: ModelContext? = nil) {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording.send(false)
        stopMonitoring()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.outputFile = nil

            guard let context = context ?? self.modelContext else {
                print("ModelContext not available for saving")
                return
            }

            if let recordingID = self.currentRecordingID,
               let recordingURL = self.currentRecordingURL {
                let session = RecordingSession(title: "Recording-\(recordingID)", audioFileURL: recordingURL)
                context.insert(session)

                do {
                    try context.save()
                    print("Session saved to SwiftData")
                } catch {
                    print("Failed to save session: \(error)")
                }
                Task {
                    do {
                        try await TranscriptionManager.shared.segmentAudio(
                            from: recordingURL,
                            recordingID: recordingID,
                            session: session,
                            modelContext: context
                        )
                    } catch {
                        print("Error processing transcription: \(error)")
                    }
                }
            }

            self.currentRecordingID = nil
            self.currentRecordingURL = nil
        }
    }

    func pauseRecording() {
        engine.pause()
        isRecording.send(false)
    }

    func resumeRecording() throws {
        try engine.start()
        isRecording.send(true)
    }

    private func startMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in }
    }

    private func stopMonitoring() {
        levelTimer?.invalidate()
        currentPower = 0.0
    }

    private func updateLevels(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let channelDataArray = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
        let rms = sqrt(channelDataArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        let avgPower = 20 * log10(rms)

        DispatchQueue.main.async {
            self.currentPower = avgPower
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            print("Interruption began - stopping recording")
            stopRecording()
        case .ended:
            try? configureSession()
            if let options = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                print("Resuming recording after interruption")
                try? startRecording(context: self.modelContext!)
            }
        default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        switch reason {
        case .oldDeviceUnavailable:
            print("Headphones unplugged - stopping recording")
            stopRecording()
        case .newDeviceAvailable:
            print("New audio device available")
        default:
            break
        }
    }
}
