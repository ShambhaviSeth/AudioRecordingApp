# Audio Recording & Transcription App Documentation

## 1. Architecture Document

This app uses a modular MVVM-inspired architecture with a focus on real-time audio recording, preprocessing, and transcription. Key components:

### Components:
- **UI Layer**: `VoiceRecorderView` for recording control, playback, and viewing transcriptions.
- **ViewModel**: `VoiceRecorderViewModel` manages AVAudioEngine and session control.
- **Data Layer**: `RecordingSession` and `TranscriptionSegment` managed with SwiftData.
- **Managers**:
  - `RecordingManager`: Handles playback, deletion.
  - `TranscriptionManager`: Handles segmentation and transcription.
  - `AudioSegmentProcessor`: Preprocesses audio for better transcription quality.

### Design Highlights:
- **Segmented Transcription**: 30s segments processed individually.
- **Fallback Architecture**: Prioritizes OpenAI Whisper API, falls back to Apple Speech API when offline or on failure.
- **Audio Enhancements**: Downsampling to 16kHz mono, high-pass filtering, and normalization for better transcription performance.

---

## 2. Audio System Design

### Audio Session Configuration:
- `.playAndRecord` mode with Bluetooth/speaker support.
- Activated with `.notifyOthersOnDeactivation` for seamless transitions.

### Route and Interruption Handling:
- **Interruptions**:
  - Stops recording on `.began`
  - Resumes if `.shouldResume` is signaled after `.ended`
- **Route Changes**:
  - Stops on `.oldDeviceUnavailable`
  - Logs `.newDeviceAvailable`

This ensures the app adapts gracefully to hardware changes and user behavior.

---

## 3. Data Model Design

### SwiftData Entities

#### `RecordingSession`
| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique ID |
| title | String | Recording title |
| createdAt | Date | Timestamp |
| audioFileURL | URL | Full audio file path |
| segments | [Segment] | Related transcription segments |

#### `TranscriptionSegment`
| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Segment ID |
| startTime / endTime | TimeInterval | Time range in audio |
| transcription | String? | Transcribed text |
| status | Enum | pending, queued, processing, etc. |
| retryCount | Int | For exponential retry strategy |
| audioURL | URL | Path to segment audio file |

### Performance Optimizations:
- Async/queued transcription
- Efficient fetches with `@Query`, `@Published`
- Retry and fallback for robustness
- Cascade deletion of segments

---

## 4. Known Issues & Improvements

| Area | Issue | Recommendation |
|------|-------|----------------|
| Segment Buildup | Failed segments accumulate when offline | Add auto-cleanup or limit |
| Manual Pause | No resume option in UI | Add pause/resume buttons |
| Transcript Editing | Not editable | Add inline edit support |
| Settings | Hardcoded params | Allow user customization in settings |

