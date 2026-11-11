import Foundation

nonisolated struct PreparedBroadcast: Sendable {
    let request: BroadcastRequest
    let extensionID: String
}

nonisolated struct BroadcastPoll: Sendable {
    let phase: BroadcastPhase
    let snapshot: SongRecognitionAudioSnapshot?
    var diagnostic: BroadcastDiagnostic? = nil
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
    // Two generations cover cancellation finishing just after a retry starts.
    private var sessions: [UUID: BroadcastMailboxSet] = [:]
    private var sessionOrder: [UUID] = []

    func prepare(duration: Int) throws -> PreparedBroadcast {
        let environment = try environment()
        let mailboxes = BroadcastMailboxSet(environment: environment)
        let request = try mailboxes.prepare(duration: duration)
        remember(mailboxes, id: request.id)
        return PreparedBroadcast(request: request, extensionID: environment.extensionID)
    }

    func recover() throws -> PreparedBroadcast? {
        let environment = try environment()
        let mailboxes = BroadcastMailboxSet(environment: environment)
        guard let request = try mailboxes.recover() else { return nil }
        remember(mailboxes, id: request.id)
        return PreparedBroadcast(request: request, extensionID: environment.extensionID)
    }

    func poll(_ request: BroadcastRequest) throws -> BroadcastPoll {
        guard var mailboxes = sessions[request.id] else { throw BroadcastDiagnostic(code: .handshakeMismatch) }
        let state = try mailboxes.state(request)
        sessions[request.id] = mailboxes
        let age = Date().timeIntervalSince(state.heartbeat)
        if state.phase != .waiting, !state.phase.terminal, age > 6 {
            throw mailboxes.diagnostic(.heartbeatLost)
        }
        guard age < 600 else { throw mailboxes.diagnostic(.heartbeatLost) }
        switch state.phase {
        case .noAudio, .silent: throw SongRecognitionRecordingError.broadcastSilent
        case .formatError: throw SongRecognitionRecordingError.conversionFailed
        case .failed: throw mailboxes.diagnostic(state.diagnostic ?? .handshakeMismatch)
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
        } else { snapshot = nil }
        let notice = state.phase == .waiting && Date().timeIntervalSince(request.createdAt) >= 12
            ? mailboxes.diagnostic(.startNotConfirmed) : nil
        return BroadcastPoll(phase: state.phase, snapshot: snapshot, diagnostic: notice)
    }

    func stop(_ request: BroadcastRequest, command: BroadcastStop) throws {
        try sessions[request.id]?.send(command, request: request)
    }

    func clearAudio(_ request: BroadcastRequest) throws { try sessions[request.id]?.clearAudio(request) }

    private func remember(_ mailboxes: BroadcastMailboxSet, id: UUID) {
        sessions[id] = mailboxes
        sessionOrder.removeAll { $0 == id }
        sessionOrder.append(id)
        while sessionOrder.count > 2 { sessions.removeValue(forKey: sessionOrder.removeFirst()) }
    }

    private func environment() throws -> BroadcastRuntimeEnvironment {
        #if os(iOS)
        return try BroadcastRuntime.environment(host: .main)
        #else
        throw SongRecognitionRecordingError.captureUnavailable
        #endif
    }
}
