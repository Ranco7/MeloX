@preconcurrency import AVFoundation
import Foundation

@MainActor
final class SongRecognitionAppAudioCapture: SongRecognitionAudioCapture {
    private let playbackAudio: PlaybackAudioCapture
    private let sink: SongRecognitionPlaybackSink
    private var token: UUID?
    var failure: (any Error)? { sink.failure }

    init(buffer: SongRecognitionCapturedAudioBuffer, playbackAudio: PlaybackAudioCapture) {
        self.playbackAudio = playbackAudio
        sink = SongRecognitionPlaybackSink(buffer: buffer)
    }

    func start() async throws {
        try Task.checkCancellation()
        guard token == nil,
              let token = playbackAudio.start(receiver: { [sink] in sink.append($0) }) else {
            throw SongRecognitionRecordingError.captureUnavailable
        }
        self.token = token
    }

    func stop() {
        guard let token else { return }
        playbackAudio.stop(token)
        self.token = nil
    }
}

/// Records failure/limit once without scheduling a MainActor task per buffer.
nonisolated private final class SongRecognitionPlaybackSink: @unchecked Sendable {
    private let buffer: SongRecognitionCapturedAudioBuffer
    private let lock = NSLock()
    private var finished = false
    private var error: (any Error)?
    var failure: (any Error)? { lock.withLock { error } }

    init(buffer: SongRecognitionCapturedAudioBuffer) { self.buffer = buffer }

    func append(_ pcm: AVAudioPCMBuffer) {
        lock.withLock {
            guard !finished else { return }
            do { finished = try buffer.append(pcm) }
            catch {
                self.error = error
                finished = true
            }
        }
    }
}
