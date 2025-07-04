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
    @StateObject private var transcriptionManager = TranscriptionManager.shared
    @State private var showingTranscriptionDetail = false
    @State private var selectedRecordingID: String?
    
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
                
                // Transcription Status
                if transcriptionManager.isProcessing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Processing transcription...")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal)
                }
                
                Divider()
                    .padding(.vertical)
                
                //List view to show past recordings
                HStack {
                    Text("Recordings")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button("Retry Failed") {
                        transcriptionManager.retryFailedTranscriptions()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .padding(.horizontal)
                
                List {
                    ForEach(recordingManager.recordings, id: \.self) { recording in
                        RecordingRow(
                            recording: recording,
                            onPlay: {
                                recordingManager.playRecording(url: recording)
                            },
                            onViewTranscription: {
                                let recordingID = extractRecordingID(from: recording)
                                selectedRecordingID = recordingID
                                showingTranscriptionDetail = true
                            }
                        )
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Voice Recorder")
            .sheet(isPresented: $showingTranscriptionDetail) {
                if let recordingID = selectedRecordingID {
                    TranscriptionDetailView(recordingID: recordingID)
                }
            }
        }
    }
    
    private func extractRecordingID(from url: URL) -> String {
        let filename = url.lastPathComponent
        let recordingPrefix = "Recording-"
        let extensionSuffix = ".m4a"
        
        if filename.hasPrefix(recordingPrefix) && filename.hasSuffix(extensionSuffix) {
            let startIndex = filename.index(filename.startIndex, offsetBy: recordingPrefix.count)
            let endIndex = filename.index(filename.endIndex, offsetBy: -extensionSuffix.count)
            return String(filename[startIndex..<endIndex])
        }
        
        return filename
    }
}
struct RecordingRow: View {
    let recording: URL
    let onPlay: () -> Void
    let onViewTranscription: () -> Void
    
    var body: some View {
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
            
            Button(action: onPlay) {
                Image(systemName: "play.fill")
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: onViewTranscription) {
                Image(systemName: "doc.text")
                    .foregroundColor(.green)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

struct TranscriptionDetailView: View {
    let recordingID: String
    @StateObject private var transcriptionManager = TranscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var recordingSegments: [TranscriptionSegment] {
        transcriptionManager.segments.filter { $0.recordingID == recordingID }
            .sorted { $0.startTime < $1.startTime }
    }
    
    var fullTranscription: String {
        transcriptionManager.getTranscriptionForRecording(recordingID)
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if !fullTranscription.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Full Transcription")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            Text(fullTranscription)
                                .padding(.horizontal)
                                .textSelection(.enabled)
                            
                            Divider()
                            
                            Text("Segments")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(recordingSegments, id: \.id) { segment in
                                SegmentRow(segment: segment)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        if recordingSegments.isEmpty {
                            Text("No segments found")
                                .foregroundColor(.gray)
                        } else {
                            Text("Transcription in progress...")
                                .font(.headline)
                            
                            ForEach(recordingSegments, id: \.id) { segment in
                                SegmentRow(segment: segment)
                            }
                        }
                    }
                    .padding()
                }
                
                Spacer()
            }
            .navigationTitle("Transcription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SegmentRow: View {
    let segment: TranscriptionSegment
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Segment \(timeRangeText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                StatusBadge(status: segment.status)
            }
            
            if let transcription = segment.transcription, !transcription.isEmpty {
                Text(transcription)
                    .font(.body)
                    .textSelection(.enabled)
            } else {
                Text("Processing...")
                    .font(.body)
                    .foregroundColor(.gray)
                    .italic()
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
    
    private var timeRangeText: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        
        let start = formatter.string(from: segment.startTime) ?? "0:00"
        let end = formatter.string(from: segment.endTime) ?? "0:00"
        
        return "\(start) - \(end)"
    }
}

struct StatusBadge: View {
    let status: TranscriptionStatus
    
    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.caption)
                .foregroundColor(statusColor)
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .pending:
            return .orange
        case .processing:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .queued:
            return .purple
        }
    }
    
    private var statusText: String {
        switch status {
        case .pending:
            return "Pending"
        case .processing:
            return "Processing"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .queued:
            return "Queued"
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
