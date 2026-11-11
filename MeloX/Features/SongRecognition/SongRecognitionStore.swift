import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

enum SongRecognitionPhase: Equatable {
    case ready
    case requestingPermission
    case waitingForBroadcast
    case listening
    case matching
    case results
    case noMatch
    case failed(SongRecognitionFailure)

    var isWorking: Bool {
        switch self {
        case .requestingPermission, .waitingForBroadcast, .listening, .matching:
            true
        case .ready, .results, .noMatch, .failed:
            false
        }
    }
}

struct SongRecognitionFailure: Equatable {
    let message: String
    let opensSystemSettings: Bool
    var diagnostic: String? = nil
}

@MainActor
@Observable
final class SongRecognitionStore {
    private static let queryInterval = 3
    private static let maximumStoredResults = 100

    private(set) var phase: SongRecognitionPhase = .ready
    private(set) var results: [SongRecognitionResult] = []
    private(set) var isContinuous = false
    private(set) var audioSource: SongRecognitionAudioSource = .microphone
    private(set) var broadcastExtensionID: String?
    private(set) var broadcastPaused = false
    private(set) var broadcastStartupDiagnostic: String?

    @ObservationIgnored private let broadcastClient: any SongRecognitionBroadcasting
    @ObservationIgnored private var broadcastRequest: BroadcastRequest?

    @ObservationIgnored
    private let recorder: any SongRecognitionRecording

    @ObservationIgnored
    private let fingerprintGenerator: any AudioFingerprintGenerating

    @ObservationIgnored
    private var recognitionTask: Task<Void, Never>?

    @ObservationIgnored
    private var generation = 0

    init() {
        broadcastClient = SongRecognitionBroadcastClient()
        recorder = SongRecognitionAudioRecorder()
        fingerprintGenerator = NeteaseAudioFingerprintGenerator()
    }

    init(
        recorder: any SongRecognitionRecording,
        fingerprintGenerator: any AudioFingerprintGenerating,
        broadcastClient: any SongRecognitionBroadcasting = SongRecognitionBroadcastClient()
    ) {
        self.broadcastClient = broadcastClient
        self.recorder = recorder
        self.fingerprintGenerator = fingerprintGenerator
    }

    func start(
        api: NeteaseAPI,
        duration: SongRecognitionDuration,
        source: SongRecognitionAudioSource
    ) {
        guard !phase.isWorking else { return }

        let previousTask = recognitionTask
        previousTask?.cancel()
        recorder.cancel()
        generation &+= 1
        let currentGeneration = generation
        results = []
        isContinuous = source == .microphone && duration.isContinuous
        audioSource = source
        phase = .requestingPermission

        recognitionTask = Task { @MainActor [weak self] in
            // Let an earlier asynchronous capture startup finish its cleanup.
            await previousTask?.value
            guard let self else { return }
            guard !Task.isCancelled, generation == currentGeneration else { return }
            if source != .microphone {
                await recognizeBroadcast(api: api, duration: duration, generation: currentGeneration)
                return
            }
            await recognize(
                api: api,
                duration: duration,
                source: source,
                generation: currentGeneration
            )
        }
    }

    func stopContinuousRecognition() {
        guard isContinuous, phase.isWorking else { return }

        generation &+= 1
        recognitionTask?.cancel()
        recorder.cancel()
        phase = results.isEmpty ? .noMatch : .results
    }

    func prepareForResultPlayback() {
        guard isContinuous, phase.isWorking else { return }
        recorder.prepareForConcurrentPlayback()
    }

    func cancel() {
        if let request = broadcastRequest {
            let client = broadcastClient
            Task { try? await client.stop(request, command: .cancel) }
        }
        broadcastRequest = nil
        broadcastExtensionID = nil
        broadcastPaused = false
        broadcastStartupDiagnostic = nil
        let wasWorking = phase.isWorking
        generation &+= 1
        recognitionTask?.cancel()
        recorder.cancel()
        if wasWorking {
            phase = .ready
        }
    }

    func stopBroadcastCapture() {
        guard let request = broadcastRequest else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await broadcastClient.stop(request, command: .complete) }
            catch {
                guard broadcastRequest?.id == request.id else { return }
                cancel()
                phase = .failed(SongRecognitionFailure(
                    message: SongRecognitionRecordingError.captureUnavailable.localizedDescription,
                    opensSystemSettings: false,
                    diagnostic: (error as? BroadcastDiagnostic).map { localizedDiagnostic($0) }))
            }
        }
    }

    func resumeBroadcastIfNeeded(api: NeteaseAPI) async {
        guard phase == .ready, recognitionTask == nil else { return }
        let currentGeneration = generation
        guard let prepared = try? await broadcastClient.recover(),
              generation == currentGeneration, phase == .ready else { return }
        audioSource = .appAudio
        isContinuous = false
        phase = .requestingPermission
        recognitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await recognizeBroadcast(api: api, duration: .extended,
                generation: currentGeneration, prepared: prepared)
        }
    }

    private func recognizeBroadcast(api: NeteaseAPI, duration: SongRecognitionDuration,
                                    generation currentGeneration: Int,
                                    prepared recovered: PreparedBroadcast? = nil) async {
        var request: BroadcastRequest?
        defer {
            if generation == currentGeneration {
                recognitionTask = nil
                broadcastExtensionID = nil
                broadcastRequest = nil
                broadcastPaused = false
                broadcastStartupDiagnostic = nil
            }
        }
        do {
            let prepared: PreparedBroadcast
            if let recovered { prepared = recovered }
            else { prepared = try await broadcastClient.prepare(duration: duration.maximumDuration ?? 9) }
            request = prepared.request
            // Cancellation may arrive while the actor is preparing its files.
            // Invalidate that exact UUID even if it never reached the UI.
            try Task.checkCancellation()
            guard generation == currentGeneration else { throw CancellationError() }
            broadcastRequest = prepared.request
            broadcastExtensionID = prepared.extensionID
            phase = .waitingForBroadcast
            var finalSnapshot: SongRecognitionAudioSnapshot?
            while finalSnapshot == nil {
                try Task.checkCancellation()
                // ReplayKit keeps running in its own process. Do not execute
                // the WebKit fingerprint runtime while the host is suspended.
                #if canImport(UIKit)
                while UIApplication.shared.applicationState != .active {
                    try await Task.sleep(for: .milliseconds(500))
                }
                #endif
                let update = try await broadcastClient.poll(prepared.request)
                try Task.checkCancellation()
                guard generation == currentGeneration else { throw CancellationError() }
                broadcastStartupDiagnostic = update.diagnostic.map { localizedDiagnostic($0) }
                if update.phase != .waiting {
                    broadcastExtensionID = nil
                    broadcastPaused = update.phase == .paused
                    phase = .listening
                }
                if update.phase == .completed {
                    guard let snapshot = update.snapshot else { throw SongRecognitionRecordingError.broadcastSilent }
                    finalSnapshot = snapshot
                } else {
                    try await Task.sleep(for: .milliseconds(500))
                }
            }
            guard let snapshot = finalSnapshot else { return }
            phase = .matching
            let fingerprint = try await fingerprintGenerator.generate(from: snapshot.samples)
            let candidates = try await api.audioMatches(fingerprint: fingerprint, duration: snapshot.duration)
            try Task.checkCancellation()
            guard generation == currentGeneration else { return }
            let immediate = candidateResults(from: candidates)
            try await broadcastClient.stop(prepared.request, command: .matched)
            try await broadcastClient.clearAudio(prepared.request)
            try Task.checkCancellation()
            guard generation == currentGeneration else { return }
            results = immediate
            phase = immediate.isEmpty ? .noMatch : .results
            if !immediate.isEmpty {
                let detailed = await resolvedResults(from: immediate, api: api)
                guard generation == currentGeneration else { return }
                results = detailed
            }
        } catch {
            if let request { try? await broadcastClient.stop(request, command: .cancel) }
            guard generation == currentGeneration else { return }
            if error is CancellationError { phase = .ready }
            else {
                let displayError: any Error
                var diagnostic: String?
                if let setup = error as? BroadcastDiagnostic {
                    displayError = setup.code == .heartbeatLost ? SongRecognitionRecordingError.captureTimedOut
                        : SongRecognitionRecordingError.captureUnavailable
                    diagnostic = localizedDiagnostic(setup)
                } else if let coreError = error as? BroadcastCoreError {
                    switch coreError {
                    case .invalidPCM: displayError = SongRecognitionRecordingError.conversionFailed
                    case .invalidSession: displayError = SongRecognitionRecordingError.captureTimedOut
                    case .unavailable, .mailbox: displayError = SongRecognitionRecordingError.captureUnavailable
                    }
                } else { displayError = error }
                phase = .failed(SongRecognitionFailure(message: displayError.localizedDescription,
                    opensSystemSettings: false, diagnostic: diagnostic))
            }
        }
    }

    private func localizedDiagnostic(_ diagnostic: BroadcastDiagnostic) -> String {
        var message = "[" + diagnostic.code.rawValue + "] " + L10n.string("ui.recognition.diagnostic." + diagnostic.code.rawValue)
        if diagnostic.candidateCount > 0 {
            message += "\n" + L10n.format("ui.recognition.diagnostic.counts", diagnostic.usableCount, diagnostic.candidateCount)
        }
        if diagnostic.profileIssue {
            message += "\n" + L10n.string("ui.recognition.diagnostic.profileIssue")
        }
        return message
    }

    private func recognize(
        api: NeteaseAPI,
        duration: SongRecognitionDuration,
        source: SongRecognitionAudioSource,
        generation currentGeneration: Int
    ) async {
        defer {
            if generation == currentGeneration {
                recognitionTask = nil
            }
        }

        do {
            try await recorder.start(
                maximumDuration: duration.maximumDuration,
                source: source
            )
            defer {
                if generation == currentGeneration { recorder.stop() }
            }
            try Task.checkCancellation()
            guard generation == currentGeneration else { return }

            phase = .listening
            var nextQueryDuration = min(
                Self.queryInterval,
                duration.maximumDuration ?? Self.queryInterval
            )

            while true {
                let snapshot = try await waitForSnapshot(
                    minimumTotalDuration: nextQueryDuration
                )

                try Task.checkCancellation()
                guard generation == currentGeneration else { return }

                if snapshot.reachedLimit {
                    recorder.stop()
                    phase = .matching
                }

                let fingerprint =
                    try await fingerprintGenerator.generate(
                        from: snapshot.samples
                    )
                let candidates = try await api.audioMatches(
                    fingerprint: fingerprint,
                    duration: snapshot.duration
                )

                try Task.checkCancellation()
                guard generation == currentGeneration else { return }

                let immediateResults = candidateResults(
                    from: candidates
                )
                if !immediateResults.isEmpty {
                    if duration.isContinuous {
                        mergeContinuousResults(immediateResults)
                        phase = .listening
                    } else {
                        recorder.stop()
                        results = immediateResults
                        phase = .results
                    }

                    let detailedResults = await resolvedResults(
                        from: immediateResults,
                        api: api
                    )
                    guard generation == currentGeneration else {
                        return
                    }
                    if duration.isContinuous {
                        mergeContinuousResults(detailedResults)
                    } else {
                        results = detailedResults
                        return
                    }
                }

                if snapshot.reachedLimit {
                    phase = .noMatch
                    return
                }

                phase = .listening
                let nextDuration =
                    snapshot.totalDuration + Self.queryInterval
                nextQueryDuration = min(
                    duration.maximumDuration ?? nextDuration,
                    nextDuration
                )
            }
        } catch is CancellationError {
            guard generation == currentGeneration else { return }
            phase = .ready
        } catch {
            guard generation == currentGeneration else { return }
            let recordingError =
                error as? SongRecognitionRecordingError
            phase = .failed(
                SongRecognitionFailure(
                    message: error.localizedDescription,
                    opensSystemSettings:
                        recordingError?.opensSystemSettings ?? false
                )
            )
        }
    }

    private func waitForSnapshot(
        minimumTotalDuration: Int
    ) async throws -> SongRecognitionAudioSnapshot {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(
            by: .seconds(Self.queryInterval + 4)
        )

        while true {
            try Task.checkCancellation()
            if let snapshot = try recorder.snapshot(),
               snapshot.totalDuration >= minimumTotalDuration
                    || snapshot.reachedLimit {
                return snapshot
            }
            guard clock.now < deadline else {
                throw audioSource != .microphone
                    ? SongRecognitionRecordingError.captureTimedOut
                    : SongRecognitionRecordingError.recordingTimedOut
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func candidateResults(
        from candidates: [AudioMatchCandidate]
    ) -> [SongRecognitionResult] {
        var results: [SongRecognitionResult] = []
        var seenIDs = Set<Int>()

        for candidate in candidates
        where candidate.song.id > 0
            && seenIDs.insert(candidate.song.id).inserted {
            results.append(
                SongRecognitionResult(
                    song: candidate.song,
                    startTimeMilliseconds: candidate.startTime
                )
            )
        }
        return results
    }

    private func resolvedResults(
        from results: [SongRecognitionResult],
        api: NeteaseAPI
    ) async -> [SongRecognitionResult] {
        let orderedIDs = results.map(\.id)
        guard !orderedIDs.isEmpty else { return [] }

        let detailedSongs = try? await api.songDetails(ids: orderedIDs)
        var detailByID: [Int: Song] = [:]
        for song in detailedSongs ?? [] {
            detailByID[song.id] = song
        }

        return results.map { result in
            var resolvedResult = result
            if let detailedSong = detailByID[result.id] {
                resolvedResult.song = detailedSong
            }
            return resolvedResult
        }
    }

    private func mergeContinuousResults(
        _ newResults: [SongRecognitionResult]
    ) {
        for newResult in newResults.reversed() {
            if let index = results.firstIndex(
                where: { $0.id == newResult.id }
            ) {
                results[index] = newResult
            } else {
                results.insert(newResult, at: 0)
            }
        }

        if results.count > Self.maximumStoredResults {
            results.removeLast(
                results.count - Self.maximumStoredResults
            )
        }
    }
}
