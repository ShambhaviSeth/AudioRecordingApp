//
//  ContentView.swift
//  AudioRecordingApp

import SwiftUI
import SwiftData

struct VoiceRecorderView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var engineManager = VoiceRecorderViewModel.shared
    @State private var searchText: String = ""
    @ObservedObject private var networkMonitor = NetworkMonitor()
    @Query(sort: \RecordingSession.createdAt, order: .reverse) var sessions: [RecordingSession]

    @State private var selectedSession: RecordingSession?
    @State private var showingTranscriptionDetail = false

    var filteredSessions: [RecordingSession] {
        if searchText.isEmpty {
            return sessions
        }
        return sessions.filter { $0.title.lowercased().contains(searchText.lowercased()) }
    }

    var groupedSessions: [String: [RecordingSession]] {
        Dictionary(grouping: filteredSessions) { session in
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: session.createdAt)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Button(action: {
                    if engineManager.isRecording.value {
                        engineManager.stopRecording(context: modelContext)
                    } else {
                        try? engineManager.startRecording(context: modelContext)
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(engineManager.isRecording.value ? Color.red : Color.blue)
                            .frame(width: 80, height: 80)
                            .shadow(radius: 10)

                        Image(systemName: engineManager.isRecording.value ? "stop.fill" : "mic.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 40))
                    }
                }
                .padding(.top)
                .accessibilityIdentifier("recordButton")
                .accessibilityLabel(engineManager.isRecording.value ? "Stop recording" : "Start recording")

                Text(engineManager.isRecording.value ? "Recording..." : "Tap to Record")
                    .font(.headline)
                    .foregroundColor(.gray)
                    .accessibilityLabel(engineManager.isRecording.value ? "Currently recording" : "Ready to record")

                LevelMeter(level: engineManager.currentPower)
                    .accessibilityLabel("Recording level meter")

                Text(networkMonitor.isConnected ? "Online" : "Offline")
                    .font(.caption)
                    .foregroundColor(networkMonitor.isConnected ? .green : .red)
                    .accessibilityLabel("Network status: \(networkMonitor.isConnected ? "Online" : "Offline")")

                Divider()

                HStack {
                    Text("Recordings")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    Spacer()

                    Button("Retry Failed") {
                        TranscriptionManager.shared.retryFailedTranscriptions()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                    .accessibilityLabel("Retry failed transcriptions")
                }
                .padding(.horizontal)

                TextField("Search", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .accessibilityLabel("Search recordings")

                if sessions.isEmpty {
                    Text("No recordings found")
                        .foregroundColor(.gray)
                        .accessibilityLabel("No recordings found")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(groupedSessions.keys.sorted(), id: \.self) { date in
                                Text(date)
                                    .font(.subheadline)
                                    .padding(.horizontal)
                                    .padding(.top, 8)
                                    .accessibilityAddTraits(.isHeader)
                                    .accessibilityLabel("Recordings from \(date)")

                                ForEach(groupedSessions[date] ?? []) { session in
                                    RecordingSessionRow(
                                        session: session,
                                        onPlay: {
                                            engineManager.currentlyPlaying = session.audioFileURL
                                            RecordingManager.shared.playRecording(url: session.audioFileURL)
                                        },
                                        onViewTranscription: {
                                            selectedSession = session
                                            showingTranscriptionDetail = true
                                        }
                                    )
                                    .padding(.horizontal)
                                }
                            }
                        }
                        .refreshable {
                            TranscriptionManager.shared.loadSegments(from: modelContext)
                        }
                    }
                }

                Spacer()
            }
            .navigationTitle("Voice Recorder")
            .sheet(isPresented: $showingTranscriptionDetail) {
                if let session = selectedSession {
                    TranscriptionDetailView(session: session)
                }
            }
        }
        .onAppear {
            TranscriptionManager.shared.loadSegments(from: modelContext)
        }
    }
}

struct RecordingSessionRow: View {
    let session: RecordingSession
    let onPlay: () -> Void
    let onViewTranscription: () -> Void

    @State private var isPlaying = false

    var body: some View {
        HStack {
            Text(session.title)
                .font(.subheadline)

            Spacer()

            Button(action: {
                isPlaying.toggle()
                onPlay()
            }) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(isPlaying ? "Pause recording" : "Play recording")

            Button(action: onViewTranscription) {
                Image(systemName: "doc.text")
                    .foregroundColor(.green)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("View transcription")
        }
        .swipeActions {
            Button(role: .destructive) {
                RecordingManager.shared.deleteRecording(url: session.audioFileURL)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct TranscriptionDetailView: View {
    let session: RecordingSession
    @StateObject private var transcriptionManager = TranscriptionManager.shared
    @Environment(\.dismiss) private var dismiss

    var recordingSegments: [TranscriptionSegment] {
        session.segments.sorted { $0.startTime < $1.startTime }
    }

    var fullTranscription: String {
        recordingSegments
            .filter { $0.status == .completed }
            .compactMap { $0.transcription }
            .joined(separator: " ")
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
        case .pending: return .orange
        case .processing: return .blue
        case .completed: return .green
        case .failed: return .red
        case .queued: return .purple
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
