import Foundation

nonisolated struct PreparedBroadcast: Sendable {
    let request: BroadcastRequest
    let extensionID: String
}

nonisolated struct BroadcastPoll: Sendable {
    let phase: BroadcastPhase
    let snapshot: SongRecognitionAudioSnapshot?
}

nonisolated protocol SongRecognitionBroadcasting: Sendable {
    func prepare(duration: Int) async throws -> PreparedBroadcast
    func recover() async throws -> PreparedBroadcast?
    func poll(_ request: BroadcastRequest) async throws -> BroadcastPoll
    func stop(_ request: BroadcastRequest, command: BroadcastStop) async throws
    func clearAudio(_ request: BroadcastRequest) async throws
}

/// All App Group discovery, disk access and PCM decoding run off MainActor.
actor SongRecognitionBroadcastClient: SongRecognitionBroadcasting {
    private var mailbox: BroadcastMailbox?

    func prepare(duration: Int) throws -> PreparedBroadcast {
        let (mailbox, extensionID) = try environment()
        self.mailbox = mailbox
        return PreparedBroadcast(request: try mailbox.prepare(duration: duration), extensionID: extensionID)
    }

    func recover() throws -> PreparedBroadcast? {
        let (mailbox, extensionID) = try environment()
        self.mailbox = mailbox
        guard let request = try mailbox.currentRequest(),
              Date().timeIntervalSince(request.createdAt) < 600,
              let state = try mailbox.state(request.id), state.phase != .waiting,
              state.phase != .cancelled,
              (state.phase != .completed || state.frameCount > 0),
              try mailbox.control(request.id)?.command != .cancel else { return nil }
        return PreparedBroadcast(request: request, extensionID: extensionID)
    }

    func poll(_ request: BroadcastRequest) throws -> BroadcastPoll {
        guard let mailbox, try mailbox.currentRequest()?.id == request.id,
              let state = try mailbox.state(request.id) else { throw SongRecognitionRecordingError.captureUnavailable }
        let age = Date().timeIntervalSince(state.heartbeat)
        if state.phase == .waiting {
            guard request.permitsStart(at: Date()) else { throw SongRecognitionRecordingError.broadcastStartExpired }
        } else if !state.phase.terminal, age > 6 {
            throw SongRecognitionRecordingError.captureTimedOut
        }
        guard age < 600 else { throw SongRecognitionRecordingError.captureTimedOut }
        switch state.phase {
        case .noAudio, .silent: throw SongRecognitionRecordingError.broadcastSilent
        case .formatError: throw SongRecognitionRecordingError.conversionFailed
        case .failed: throw SongRecognitionRecordingError.captureUnavailable
        case .cancelled: throw CancellationError()
        default: break
        }
        let frames = (state.frameCount / BroadcastResampler.rate) * BroadcastResampler.rate
        let snapshot: SongRecognitionAudioSnapshot?
        if state.phase == .completed, frames >= BroadcastResampler.rate {
            let samples = try state.samples()
            guard samples.allSatisfy(\.isFinite) else { throw SongRecognitionRecordingError.conversionFailed }
            snapshot = SongRecognitionAudioSnapshot(samples: Array(samples.suffix(frames)),
                duration: frames / BroadcastResampler.rate, totalDuration: frames / BroadcastResampler.rate,
                reachedLimit: state.phase.terminal)
        } else {
            snapshot = nil
        }
        return BroadcastPoll(phase: state.phase, snapshot: snapshot)
    }

    func stop(_ request: BroadcastRequest, command: BroadcastStop) throws {
        try mailbox?.send(command, id: request.id)
    }

    func clearAudio(_ request: BroadcastRequest) throws { try mailbox?.clearAudio(request.id) }

    private func environment() throws -> (BroadcastMailbox, String) {
        #if os(iOS)
        guard let group = Bundle.main.object(forInfoDictionaryKey: "MeloXBroadcastAppGroup") as? String,
              let extensionID = Bundle.main.object(forInfoDictionaryKey: "MeloXBroadcastExtensionID") as? String,
              let plugins = Bundle.main.builtInPlugInsURL,
              let embedded = Bundle(url: plugins.appendingPathComponent("MeloXBroadcastUpload.appex")),
              embedded.bundleIdentifier == extensionID,
              embedded.object(forInfoDictionaryKey: "MeloXBroadcastAppGroup") as? String == group,
              let info = embedded.object(forInfoDictionaryKey: "NSExtension") as? [String: Any],
              info["NSExtensionPointIdentifier"] as? String == "com.apple.broadcast-services-upload",
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw SongRecognitionRecordingError.captureUnavailable
        }
        do {
            let mailbox = try BroadcastMailbox(container: container)
            let probe = mailbox.root.appendingPathComponent("host-probe")
            try Data([0]).write(to: probe, options: .atomic)
            guard try Data(contentsOf: probe) == Data([0]) else { throw BroadcastCoreError.mailbox }
            try FileManager.default.removeItem(at: probe)
            return (mailbox, extensionID)
        } catch { throw SongRecognitionRecordingError.captureUnavailable }
        #else
        throw SongRecognitionRecordingError.captureUnavailable
        #endif
    }
}
