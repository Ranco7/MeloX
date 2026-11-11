// PCM fixtures only. No audio engine, microphone, recording panel or network.
import AVFoundation
import Foundation

enum SongRecognitionRecordingError: Error { case conversionFailed, captureUnavailable }

@main
struct PlaybackCaptureChecks {
    @MainActor
    static func main() async throws {
        let playback = PlaybackAudioCapture()
        let firstDeck = UUID(), secondDeck = UUID()
        let samples = SongRecognitionSampleBuffer(retainedFrameCount: 960, stoppingFrameCount: 960)
        let capture = SongRecognitionAppAudioCapture(
            buffer: SongRecognitionCapturedAudioBuffer(recordingBuffer: samples), playbackAudio: playback)
        try await capture.start()
        let pcm = makePCM(rate: 48_000, frames: 480, interleaved: false)
        playback.append(pcm, from: firstDeck)
        precondition(samples.snapshot().totalFrameCount == 0, "Paused/loading sources supply no PCM")
        playback.select(source: firstDeck)
        playback.append(pcm, from: secondDeck)
        precondition(samples.snapshot().totalFrameCount == 0, "The standby deck must not double the capture duration")
        playback.append(pcm, from: firstDeck)
        precondition(samples.snapshot().samples.allSatisfy { abs($0 - 0.5) < 0.001 })
        precondition(samples.snapshot().totalFrameCount == 480)

        let competing = SongRecognitionAppAudioCapture(
            buffer: SongRecognitionCapturedAudioBuffer(recordingBuffer: samples), playbackAudio: playback)
        do { try await competing.start(); fatalError("Duplicate capture accepted") }
        catch SongRecognitionRecordingError.captureUnavailable { }
        competing.stop()
        playback.select(source: secondDeck)
        playback.append(pcm, from: firstDeck)
        precondition(samples.snapshot().totalFrameCount == 480)
        playback.append(pcm, from: secondDeck)
        precondition(samples.snapshot().reachedLimit)
        playback.append(pcm, from: secondDeck)
        precondition(samples.snapshot().totalFrameCount == 960)
        precondition(capture.failure == nil)
        capture.stop(); capture.stop()
        print("PASS: active-deck routing, duplicate refusal, downmix, limit and idempotent stop")

        let rolling = SongRecognitionSampleBuffer(retainedFrameCount: 960, stoppingFrameCount: nil)
        let next = SongRecognitionAppAudioCapture(
            buffer: SongRecognitionCapturedAudioBuffer(recordingBuffer: rolling), playbackAudio: playback)
        try await next.start()
        capture.stop()
        let converted = makePCM(rate: 44_100, frames: 441, interleaved: true)
        for _ in 0..<4 { playback.append(converted, from: secondDeck) }
        precondition(rolling.snapshot().samples.count == 960)
        precondition(rolling.snapshot().totalFrameCount > 960)
        precondition(rolling.snapshot().samples.allSatisfy { abs($0 - 0.5) < 0.01 })
        playback.select(source: nil)
        let beforePause = rolling.snapshot().totalFrameCount
        playback.append(converted, from: secondDeck)
        precondition(rolling.snapshot().totalFrameCount == beforePause)
        next.stop()
        print("PASS: 44.1 kHz interleaved conversion, bounded rolling capture and pause gating")

        let cancelled = SongRecognitionAppAudioCapture(
            buffer: SongRecognitionCapturedAudioBuffer(recordingBuffer: rolling), playbackAudio: playback)
        let startup = Task { @MainActor in
            do { try await cancelled.start(); fatalError("Cancelled startup accepted") }
            catch is CancellationError { }
        }
        startup.cancel()
        try await startup.value
        try await cancelled.start()
        cancelled.stop()
        print("PASS: cancelled startup does not retain the playback subscription")
    }

    private static func makePCM(rate: Double, frames: UInt32, interleaved: Bool) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                   channels: 2, interleaved: interleaved)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        pcm.frameLength = frames
        for frame in 0..<Int(frames) {
            if interleaved {
                pcm.floatChannelData![0][frame * 2] = 1
                pcm.floatChannelData![0][frame * 2 + 1] = 0
            } else {
                pcm.floatChannelData![0][frame] = 1
                pcm.floatChannelData![1][frame] = 0
            }
        }
        return pcm
    }
}
