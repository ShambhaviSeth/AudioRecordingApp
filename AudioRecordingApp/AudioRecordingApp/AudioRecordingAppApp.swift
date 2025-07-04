//
//  AudioRecordingAppApp.swift
//  AudioRecordingApp
//
//  Created by Shambhavi Seth on 7/1/25.
//

import SwiftUI
import SwiftData

@main
struct AudioRecordingAppApp: App {
    var body: some Scene {
        WindowGroup {
            VoiceRecorderView()
        }
        .modelContainer(for: [RecordingSession.self, TranscriptionSegment.self])
    }
}
