//
//  ContentView.swift
//  AudioRecordingApp
//
//  Created by Shambhavi Seth on 7/1/25.
//

import SwiftUI

import SwiftUI
import Combine

struct VoiceRecorderView: View {
        @StateObject private var engineManager = VoiceRecorderViewModel.shared
        @StateObject private var recordingManager = RecordingManager.shared

        var body: some View {
            NavigationView {
                VStack(spacing: 20) {
                    Spacer()

                    Button(action: {
                        if engineManager.isRecording.value {
                            engineManager.stopRecording()
                        } else {
                            try? engineManager.startRecording()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(engineManager.isRecording.value ? Color.red : Color.blue)
                                .frame(width: 100, height: 100)
                                .shadow(radius: 10)

                            Image(systemName: engineManager.isRecording.value ? "stop.fill" : "mic.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 40))
                        }
                    }

                    Text(engineManager.isRecording.value ? "Recording..." : "Tap to Record")
                        .font(.headline)
                        .foregroundColor(.gray)

                    LevelMeter(level: engineManager.currentPower)

                    Divider()
                        .padding(.vertical)
                    
                    //List view to show past recordings
                    Text("Recordings")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    List {
                        ForEach(recordingManager.recordings, id: \.self) { recording in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(recording.lastPathComponent)
                                        .lineLimit(1)
                                        .font(.subheadline)
                                    Text(recording.creationDateFormatted())
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }

                                Spacer()

                                Button(action: {
                                    recordingManager.playRecording(url: recording)
                                }) {
                                    Image(systemName: "play.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }

                    Spacer()
                }
                .navigationTitle("Voice Recorder")
            }
        }
    }


// View to show level meter while recording
struct LevelMeter: View {
    var level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                Rectangle()
                    .fill(Color.green)
                    .frame(width: CGFloat(max(0, level + 60) / 60) * geo.size.width)
            }
            .frame(height: 10)
            .cornerRadius(5)
        }
        .frame(height: 10)
    }
}

#Preview {
    VoiceRecorderView()
}
