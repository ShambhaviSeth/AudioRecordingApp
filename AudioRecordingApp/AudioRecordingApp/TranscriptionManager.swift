import Foundation
import AVFoundation
import Speech
import Network
import SwiftData


struct TranscriptionResult {
    let segmentId: UUID
    let text: String
    let confidence: Float?
    let source: TranscriptionSource
}

enum TranscriptionSource {
    case openAI
    case appleSpeech
    case localWhisper
}

struct TranscriptionSettings {
    var segmentDuration: TimeInterval = 30.0
    var maxRetries: Int = 5
    var usePreprocessing: Bool = true
    var apiTimeout: TimeInterval = 30.0
    var batchSize: Int = 3
    var enableVoiceActivityDetection: Bool = true
    
    // OpenAI Whisper settings
    var whisperModel: String = "whisper-1"
    var responseFormat: String = "json"
    var temperature: Float = 0.0
    var language: String? = nil
    
    // Fallback settings
    var enableLocalFallback: Bool = true
    var fallbackThreshold: Int = 5
}


class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var isConnected = false
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}


class TranscriptionManager: ObservableObject {
    static let shared = TranscriptionManager()
    
    @Published var segments: [TranscriptionSegment] = []
    @Published var isProcessing = false
    
    private let networkMonitor = NetworkMonitor()
    private let segmentDuration: TimeInterval = 30.0
    private let maxRetries = 5
    private let apiKey = "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"
    
    private var processingQueue = DispatchQueue(label: "transcription.processing", qos: .userInitiated)
    private var pendingSegments: [TranscriptionSegment] = []
    private var consecutiveFailures = 0
    private var shouldUseLocalFallback = false
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private init() {
        setupNotifications()
        requestSpeechRecognitionPermission()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(networkStatusChanged),
            name: .networkStatusChanged,
            object: nil
        )
    }
    
    @objc private func networkStatusChanged() {
        if networkMonitor.isConnected {
            processQueuedSegments()
        }
    }
    
    func segmentAudio(from fileURL: URL, recordingID: String, session: RecordingSession, modelContext: ModelContext) async throws {
        let audioFile = try AVAudioFile(forReading: fileURL)
        let format = audioFile.processingFormat
        let totalFrames = audioFile.length
        let sampleRate = format.sampleRate
        let totalDuration = Double(totalFrames) / sampleRate

        let segmentDuration: TimeInterval = 30.0
        let segmentFrames = AVAudioFrameCount(segmentDuration * sampleRate)
        var currentFrame: AVAudioFramePosition = 0
        var segmentIndex = 0

        while currentFrame < totalFrames {
            let remainingFrames = totalFrames - currentFrame
            let framesToRead = min(segmentFrames, AVAudioFrameCount(remainingFrames))

            let segmentURL = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("segment-\(recordingID)-\(segmentIndex).m4a")

            let segmentFile = try AVAudioFile(forWriting: segmentURL, settings: format.settings)

            audioFile.framePosition = currentFrame
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead)!
            try audioFile.read(into: buffer, frameCount: framesToRead)
            try segmentFile.write(from: buffer)

            let startTime = Double(currentFrame) / sampleRate
            let endTime = min(startTime + segmentDuration, totalDuration)

            let segment = TranscriptionSegment(
                startTime: startTime,
                endTime: endTime,
                transcription: nil,
                status: .pending,
                retryCount: 0,
                session: session,
                segmentURL: segmentURL
            )

            DispatchQueue.main.async {
                modelContext.insert(segment)
                try? modelContext.save()
                self.segments.append(segment)
                self.queueSegmentForTranscription(segment)
            }

            currentFrame += AVAudioFramePosition(framesToRead)
            segmentIndex += 1
        }
    }

    
    private func createSegmentURL(recordingID: String, segmentIndex: Int, suffix: String = "") -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent("segment-\(recordingID)-\(segmentIndex)\(suffix).m4a")
    }
    
    private func queueSegmentForTranscription(_ segment: TranscriptionSegment) {
        processingQueue.async {
            if self.networkMonitor.isConnected && !self.shouldUseLocalFallback {
                self.transcribeWithOpenAI(segment)
            } else if self.shouldUseLocalFallback {
                self.transcribeWithAppleSpeech(segment)
            } else {
                self.pendingSegments.append(segment)
                self.updateSegmentStatus(segment.id, status: .queued)
            }
        }
    }
    
    private func processQueuedSegments() {
        processingQueue.async {
            let segmentsToProcess = self.pendingSegments
            self.pendingSegments.removeAll()
            
            for segment in segmentsToProcess {
                if !self.shouldUseLocalFallback {
                    self.transcribeWithOpenAI(segment)
                } else {
                    self.transcribeWithAppleSpeech(segment)
                }
            }
        }
    }
    
    private func transcribeWithOpenAI(_ segment: TranscriptionSegment) {
        updateSegmentStatus(segment.id, status: .processing)
        
        guard let apiKey = getOpenAIAPIKey() else {
            handleTranscriptionFailure(segment, error: NSError(domain: "TranscriptionError", code: 1, userInfo: [NSLocalizedDescriptionKey: "API key not configured"]))
            return
        }
        
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        do {
            let audioData = try Data(contentsOf: segment.audioURL)
            let body = createMultipartBody(audioData: audioData, boundary: boundary)
            request.httpBody = body
            
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                self?.handleOpenAIResponse(segment: segment, data: data, response: response, error: error)
            }
            task.resume()
            
        } catch {
            handleTranscriptionFailure(segment, error: error)
        }
    }
    
    private func createMultipartBody(audioData: Data, boundary: String) -> Data {
        var body = Data()
        
        //Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        //Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)

        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        //Add response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("json\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
    
    private func handleOpenAIResponse(segment: TranscriptionSegment, data: Data?, response: URLResponse?, error: Error?) {
        if let error = error {
            handleTranscriptionFailure(segment, error: error)
            return
        }
        
        guard let data = data else {
            handleTranscriptionFailure(segment, error: NSError(domain: "TranscriptionError", code: 2, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
            return
        }
        
        do {
            let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            
            if let text = jsonResponse?["text"] as? String {
                let result = TranscriptionResult(
                    segmentId: segment.id,
                    text: text,
                    confidence: nil,
                    source: .openAI
                )
                handleTranscriptionSuccess(segment, result: result)
                consecutiveFailures = 0
            } else {
                handleTranscriptionFailure(segment, error: NSError(domain: "TranscriptionError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"]))
            }
        } catch {
            handleTranscriptionFailure(segment, error: error)
        }
    }
    
    private func transcribeWithAppleSpeech(_ segment: TranscriptionSegment) {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            handleTranscriptionFailure(segment, error: NSError(domain: "SpeechError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition not available"]))
            return
        }
        
        updateSegmentStatus(segment.id, status: .processing)
        
        let recognitionRequest = SFSpeechURLRecognitionRequest(url: segment.audioURL)
        recognitionRequest.shouldReportPartialResults = false
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let error = error {
                self?.handleTranscriptionFailure(segment, error: error)
                return
            }
            
            if let result = result, result.isFinal {
                let transcriptionResult = TranscriptionResult(
                    segmentId: segment.id,
                    text: result.bestTranscription.formattedString,
                    confidence: result.bestTranscription.segments.first?.confidence,
                    source: .appleSpeech
                )
                self?.handleTranscriptionSuccess(segment, result: transcriptionResult)
            }
        }
    }
    

    private func handleTranscriptionSuccess(_ segment: TranscriptionSegment, result: TranscriptionResult) {
        DispatchQueue.main.async {
            segment.transcription = result.text
            segment.status = .completed
            do {
                try segment.modelContext?.save()
                print("Transcription saved for segment \(segment.id)")
            } catch {
                print("Failed to save segment: \(error)")
            }
        }
        
        try? FileManager.default.removeItem(at: segment.audioURL)
    }
    
    private func handleTranscriptionFailure(_ segment: TranscriptionSegment, error: Error) {
        consecutiveFailures += 1
        
        if consecutiveFailures >= maxRetries {
            shouldUseLocalFallback = true
            print("Switching to local fallback after \(consecutiveFailures) consecutive failures")
        }
        
        DispatchQueue.main.async {
            if let index = self.segments.firstIndex(where: { $0.id == segment.id }) {
                self.segments[index].retryCount += 1
                
                if self.segments[index].retryCount < self.maxRetries {
                    //Retry with exponential backoff
                    let delay = pow(2.0, Double(self.segments[index].retryCount))
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        self.queueSegmentForTranscription(self.segments[index])
                    }
                } else {
                    self.segments[index].status = .failed
                    
                    //Try local fallback for this segment
                    if self.speechRecognizer?.isAvailable == true {
                        self.transcribeWithAppleSpeech(self.segments[index])
                    }
                }
            }
        }
    }
    
    private func updateSegmentStatus(_ segmentId: UUID, status: TranscriptionStatus) {
        DispatchQueue.main.async {
            if let index = self.segments.firstIndex(where: { $0.id == segmentId }) {
                self.segments[index].status = status
            }
        }
    }
    
    private func getOpenAIAPIKey() -> String? {
        return apiKey.isEmpty ? nil : apiKey
    }
    
    private func requestSpeechRecognitionPermission() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("Speech recognition authorized")
                case .denied, .restricted, .notDetermined:
                    print("Speech recognition not authorized")
                @unknown default:
                    print("Unknown speech recognition authorization status")
                }
            }
        }
    }
    
    func getTranscriptionForRecording(_ recordingID: String) -> String {
        let recordingSegments = segments.filter {
            $0.session?.id.uuidString == recordingID && $0.status == .completed
        }
        return recordingSegments
            .sorted { $0.startTime < $1.startTime }
            .compactMap { $0.transcription }
            .joined(separator: " ")
    }
    
    func retryFailedTranscriptions() {
        let failedSegments = segments.filter { $0.status == .failed }
        for segment in failedSegments {
            queueSegmentForTranscription(segment)
        }
    }
    
    func clearCompletedSegments() {
        segments.removeAll { $0.status == .completed }
    }
    
    func loadSegments(from context: ModelContext) {
        do {
            let descriptor = FetchDescriptor<TranscriptionSegment>()
            let allSegments = try context.fetch(descriptor)

            DispatchQueue.main.async {
                self.segments = allSegments
                for segment in allSegments where segment.status == .pending || segment.status == .queued {
                    self.queueSegmentForTranscription(segment)
                }
            }
        } catch {
            print("Failed to load segments: \(error)")
        }
    }
}

extension Notification.Name {
    static let networkStatusChanged = Notification.Name("networkStatusChanged")
}
