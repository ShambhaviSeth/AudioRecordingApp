//
//  RecordingManager.swift
//  AudioRecordingApp
//
//  Created by Shambhavi Seth on 7/2/25.
//

import Foundation
import AVFoundation

class RecordingManager: ObservableObject {
    static let shared = RecordingManager()

    @Published var recordings: [URL] = []
    private var audioPlayer: AVAudioPlayer?

    private init() {
        fetchRecordings()
    }

    func fetchRecordings() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
        } catch {
            print("Error reading documents directory: \(error)")
            return
        }

        recordings = contents
            .filter { $0.pathExtension == "m4a" }
            .sorted(by: { $0.lastPathComponent > $1.lastPathComponent })
    }

    func playRecording(url: URL) {
        if audioPlayer?.url == url {
            if let player = audioPlayer, player.isPlaying {
                player.pause()
            } else {
                audioPlayer?.play()
            }
        } else {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
            } catch {
                print("Failed to play recording: \(error)")
            }
        }
    }

    func deleteRecording(url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            fetchRecordings()

            DispatchQueue.main.async {
                let segmentsToDelete = TranscriptionManager.shared.segments.filter { $0.audioURL == url }

                for segment in segmentsToDelete {
                    if let session = segment.session {
                        session.segments.removeAll { $0.id == segment.id }
                    }
                }

                TranscriptionManager.shared.segments.removeAll { $0.audioURL == url }
            }
        } catch {
            print("Failed to delete recording: \(error)")
        }
    }
}

extension URL {
    func creationDateFormatted() -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        if let date = attrs?[.creationDate] as? Date {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return "Unknown"
    }
}
