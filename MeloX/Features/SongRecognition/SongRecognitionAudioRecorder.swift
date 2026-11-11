@preconcurrency import AVFoundation
import Foundation

@MainActor
final class SongRecognitionAudioRecorder: SongRecognitionRecording {
    static let fingerprintSampleRate = 8_000.0
    private static let continuousWindowDuration = 9

    private var engine: AVAudioEngine?
    private var sampleBuffer: SongRecognitionSampleBuffer?
    private var sourceSampleRate = 0.0
    private var isTapInstalled = false
    private var isSessionActive = false
    private var shouldPreservePlaybackSession = false
    private var audioCapture: (any SongRecognitionAudioCapture)?

    func start(maximumDuration: Int?, source: SongRecognitionAudioSource, playbackAudio: PlaybackAudioCapture?) async throws {
        stop()
        resetCapture()
        shouldPreservePlaybackSession = false

        if let maximumDuration,
           maximumDuration <= 0 {
            throw SongRecognitionRecordingError.conversionFailed
        }

        if source != .microphone {
            let recordingBuffer = makeSampleBuffer(
                sampleRate: SongRecognitionCapturedAudioBuffer.sampleRate,
                maximumDuration: maximumDuration
            )
            let buffer = SongRecognitionCapturedAudioBuffer(recordingBuffer: recordingBuffer)
            guard source == .appAudio, let playbackAudio else {
                resetCapture()
                throw SongRecognitionRecordingError.captureUnavailable
            }
            let capture = SongRecognitionAppAudioCapture(buffer: buffer, playbackAudio: playbackAudio)
            audioCapture = capture
            do { try await capture.start() }
            catch {
                stop()
                resetCapture()
                throw error
            }
            return
        }

        try await ensureMicrophonePermission()
        try Task.checkCancellation()

        let session = AVAudioSession.sharedInstance()
        do {
            let category: AVAudioSession.Category =
                maximumDuration == nil ? .playAndRecord : .record
            let options: AVAudioSession.CategoryOptions =
                maximumDuration == nil
                ? [.allowBluetoothHFP, .defaultToSpeaker]
                : [.allowBluetoothHFP]
            try session.setCategory(
                category,
                mode: .measurement,
                options: options
            )
            try session.setActive(true)
            isSessionActive = true
        } catch {
            throw SongRecognitionRecordingError.recordingFailed(
                error.localizedDescription
            )
        }

        let recordingEngine = AVAudioEngine()
        let inputNode = recordingEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              inputFormat.channelCount > 0,
              inputFormat.commonFormat == .pcmFormatFloat32 else {
            stopAudioSession()
            throw SongRecognitionRecordingError.microphoneUnavailable
        }

        let recordingBuffer = makeSampleBuffer(
            sampleRate: inputFormat.sampleRate,
            maximumDuration: maximumDuration
        )

        engine = recordingEngine

        inputNode.installTap(
            onBus: 0,
            bufferSize: 2_048,
            format: inputFormat
        ) { [weak self] buffer, _ in
            guard recordingBuffer.append(buffer) else { return }
            Task { @MainActor [weak self] in
                guard let self,
                      sampleBuffer === recordingBuffer else {
                    return
                }
                stopEngine()
                stopAudioSession()
            }
        }
        isTapInstalled = true

        do {
            recordingEngine.prepare()
            try recordingEngine.start()
        } catch {
            stop()
            resetCapture()
            throw SongRecognitionRecordingError.recordingFailed(
                error.localizedDescription
            )
        }
    }

    func snapshot() throws -> SongRecognitionAudioSnapshot? {
        if let failure = audioCapture?.failure { throw failure }
        guard let sampleBuffer,
              sourceSampleRate > 0 else {
            return nil
        }

        let rawSnapshot = sampleBuffer.snapshot()
        let availableDuration = Int(
            Double(rawSnapshot.samples.count)
                / sourceSampleRate
        )
        let totalDuration = Int(
            Double(rawSnapshot.totalFrameCount)
                / sourceSampleRate
        )
        guard availableDuration > 0 else { return nil }

        let sourceFrameCount = min(
            rawSnapshot.samples.count,
            Int(
                (Double(availableDuration) * sourceSampleRate)
                    .rounded(.down)
            )
        )
        let sourceSamples = Array(
            rawSnapshot.samples.suffix(sourceFrameCount)
        )
        let targetFrameCount =
            availableDuration * Int(Self.fingerprintSampleRate)

        return SongRecognitionAudioSnapshot(
            samples: try resample(
                sourceSamples,
                sourceSampleRate: sourceSampleRate,
                targetFrameCount: targetFrameCount
            ),
            duration: availableDuration,
            totalDuration: totalDuration,
            reachedLimit: rawSnapshot.reachedLimit
        )
    }

    func cancel() {
        stop()
    }

    func prepareForConcurrentPlayback() {
        shouldPreservePlaybackSession = true
    }

    func stop() {
        stopEngine()
        stopAudioSession()
    }

    private func stopEngine() {
        audioCapture?.stop()
        audioCapture = nil
        guard let engine else { return }
        if isTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        engine.stop()
        self.engine = nil
    }

    private func stopAudioSession() {
        guard isSessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        if session.category == .playAndRecord {
            // Continuous recognition leaves the shared session in
            // .playAndRecord. The playback configurator preserves that
            // category while capture is live, so restore playback here or
            // playback would keep using the recording route afterwards.
            let mixMode = AudioPlaybackSessionConfigurator.preferredMixMode
            let options: AVAudioSession.CategoryOptions =
                mixMode == .mixWithOthers ? [.mixWithOthers] : []
            try? session.setCategory(
                .playback,
                mode: .default,
                options: options
            )
        }
        if shouldPreservePlaybackSession {
            try? AudioPlaybackSessionConfigurator.activate()
        } else {
            try? session.setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
        isSessionActive = false
    }

    private func resetCapture() {
        sampleBuffer = nil
        sourceSampleRate = 0
    }

    private func makeSampleBuffer(sampleRate: Double, maximumDuration: Int?) -> SongRecognitionSampleBuffer {
        let duration = maximumDuration ?? Self.continuousWindowDuration
        let buffer = SongRecognitionSampleBuffer(
            retainedFrameCount: Int((Double(duration) * sampleRate).rounded(.up)),
            stoppingFrameCount: maximumDuration.map { Int((Double($0) * sampleRate).rounded(.up)) }
        )
        sourceSampleRate = sampleRate
        sampleBuffer = buffer
        return buffer
    }

    private func ensureMicrophonePermission() async throws {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return
        case .denied:
            throw SongRecognitionRecordingError
                .microphonePermissionDenied
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { isGranted in
                    continuation.resume(returning: isGranted)
                }
            }
            guard granted else {
                throw SongRecognitionRecordingError
                    .microphonePermissionDenied
            }
        @unknown default:
            throw SongRecognitionRecordingError
                .microphonePermissionDenied
        }
    }

    private func resample(
        _ samples: [Float],
        sourceSampleRate: Double,
        targetFrameCount: Int
    ) throws -> [Float] {
        guard !samples.isEmpty,
              targetFrameCount > 0 else {
            throw SongRecognitionRecordingError.conversionFailed
        }

        if sourceSampleRate == Self.fingerprintSampleRate {
            return normalizedFrameCount(
                samples,
                targetFrameCount: targetFrameCount
            )
        }

        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceSampleRate,
            channels: 1,
            interleaved: false
        ),
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.fingerprintSampleRate,
            channels: 1,
            interleaved: false
        ),
        let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ),
        let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: AVAudioFrameCount(targetFrameCount + 32)
        ),
        let inputChannel = inputBuffer.floatChannelData?[0],
        let converter = AVAudioConverter(
            from: sourceFormat,
            to: targetFormat
        ) else {
            throw SongRecognitionRecordingError.conversionFailed
        }

        samples.withUnsafeBufferPointer { source in
            guard let baseAddress = source.baseAddress else { return }
            inputChannel.update(
                from: baseAddress,
                count: samples.count
            )
        }
        inputBuffer.frameLength = AVAudioFrameCount(samples.count)
        converter.primeMethod = .none

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(
            to: outputBuffer,
            error: &conversionError
        ) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .endOfStream
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error,
              conversionError == nil,
              let outputChannel = outputBuffer.floatChannelData?[0] else {
            throw SongRecognitionRecordingError.conversionFailed
        }

        let output = Array(
            UnsafeBufferPointer(
                start: outputChannel,
                count: Int(outputBuffer.frameLength)
            )
        )
        return normalizedFrameCount(
            output,
            targetFrameCount: targetFrameCount
        )
    }

    private func normalizedFrameCount(
        _ samples: [Float],
        targetFrameCount: Int
    ) -> [Float] {
        if samples.count >= targetFrameCount {
            return Array(samples.prefix(targetFrameCount))
        }
        return samples + Array(
            repeating: 0,
            count: targetFrameCount - samples.count
        )
    }
}
