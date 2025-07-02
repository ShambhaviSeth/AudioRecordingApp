//
//  ContentView.swift
//  AudioRecordingApp
//
//  Created by Shambhavi Seth on 7/1/25.
//

import SwiftUI

struct VoiceRecorderView: View {
    @StateObject private var viewModel = VoiceRecorderViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()

                //Record Button View
                Button(action: {
                    viewModel.toggleRecording()
                }) {
                    ZStack {
                        Circle()
                            .fill(viewModel.isRecording ? Color.red : Color.blue)
                            .frame(width: 100, height: 100)
                            .shadow(radius: 10)

                        Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 40))
                    }
                }

                Text(viewModel.isRecording ? "Recording..." : "Tap to Record")
                    .font(.headline)
                    .foregroundColor(.gray)

                Spacer()

                //Recordings List View
                VStack(alignment: .leading) {
                    Text("Recordings")
                        .font(.headline)
                        .padding(.horizontal)

                    List(viewModel.recordings, id: \.self) { recording in
                        HStack {
                            Image(systemName: "waveform")
                                .foregroundColor(.blue)
                            Text(recording.lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                            Button(action: {
                                viewModel.playRecording(url: recording)
                            }) {
                                Image(systemName: "play.fill")
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                }

                Spacer()
            }
            .navigationTitle("Voice Recorder")
        }
    }
}

#Preview {
    VoiceRecorderView()
}
