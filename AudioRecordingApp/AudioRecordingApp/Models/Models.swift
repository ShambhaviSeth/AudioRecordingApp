//
//  Model.swift
//  AudioRecordingApp
//
//  Created by Shambhavi Seth on 7/3/25.
//
import Foundation
import SwiftData

@Model
class RecordingSession {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var audioFileURL: URL
    @Relationship(deleteRule: .cascade) var segments: [TranscriptionSegment] = []

    init(title: String, audioFileURL: URL, createdAt: Date = Date()) {
        self.id = UUID()
        self.title = title
        self.audioFileURL = audioFileURL
        self.createdAt = createdAt
    }
}

@Model
class TranscriptionSegment {
    @Attribute(.unique) var id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var transcription: String?
    var status: TranscriptionStatus
    var retryCount: Int
    var createdAt: Date
    var audioURL: URL
    @Relationship var session: RecordingSession?

    init(startTime: TimeInterval, endTime: TimeInterval, transcription: String? = nil,
         status: TranscriptionStatus = .pending, retryCount: Int = 0, session: RecordingSession?, segmentURL: URL) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.transcription = transcription
        self.status = status
        self.retryCount = retryCount
        self.createdAt = Date()
        self.session = session
        self.audioURL = segmentURL
    }
}

enum TranscriptionStatus: String, Codable {
    case pending
    case processing
    case completed
    case failed
    case queued
}

