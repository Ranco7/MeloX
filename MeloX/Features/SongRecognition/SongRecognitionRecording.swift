import Foundation

enum SongRecognitionRecordingError: LocalizedError {
    case microphonePermissionDenied
    case microphoneUnavailable
    case recordingFailed(String)
    case recordingTimedOut
    case conversionFailed
    case captureUnavailable
    case captureTimedOut

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            L10n.string("ui.recognition.error.microphone_permission")
        case .microphoneUnavailable:
            L10n.string("ui.recognition.error.microphone_unavailable")
        case .recordingFailed(let message):
            L10n.format("ui.recognition.error.recording_failed", message)
        case .recordingTimedOut:
            L10n.string("ui.recognition.error.recording_timed_out")
        case .conversionFailed:
            L10n.string("ui.recognition.error.conversion_failed")
        case .captureUnavailable:
            L10n.string("ui.recognition.error.capture_unavailable")
        case .captureTimedOut:
            L10n.string("ui.recognition.error.capture_timed_out")
        }
    }

    var opensSystemSettings: Bool {
        if case .microphonePermissionDenied = self {
            true
        } else {
            false
        }
    }
}

struct SongRecognitionAudioSnapshot {
    let samples: [Float]
    let duration: Int
    let totalDuration: Int
    let reachedLimit: Bool
}

@MainActor
protocol SongRecognitionRecording: AnyObject {
    func start(
        maximumDuration: Int?,
        source: SongRecognitionAudioSource,
        playbackAudio: PlaybackAudioCapture?
    ) async throws
    func snapshot() throws -> SongRecognitionAudioSnapshot?
    func prepareForConcurrentPlayback()
    func cancel()
    func stop()
}

@MainActor
protocol AudioFingerprintGenerating: AnyObject {
    func generate(from samples: [Float]) async throws -> String
}
